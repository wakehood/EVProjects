import XCTest

/// Simulates the sendNextPollingCommand scheduling loop without BLE hardware.
///
/// Compares the "before" queue structure (9-item slow queue, no x-slow tier)
/// against the "after" structure (4-item slow + 2-item x-slow every 30 slots,
/// runtime driven by local timer) using the same tick-counter logic as the
/// production code.
///
/// Run with the hardware-measured round-trip time from PollingCadenceTestResults.docx
/// substituted for rttMs to get real-world rotation estimates.
final class PollingCadenceSimulationTests: XCTestCase {

    // MARK: - Simulation core

    struct Config {
        let name: String
        let slowQueue: [String]
        let xSlowQueue: [String]
        let xSlowInterval: Int   // 0 = no x-slow tier
    }

    struct Results {
        var currentCount  = 0
        var voltageCount  = 0
        var slowCounts:  [String: Int] = [:]
        var xSlowCounts: [String: Int] = [:]
        let totalTicks: Int
        let config: Config

        var totalDispatches: Int { currentCount + voltageCount + slowTotal + xSlowTotal }
        var slowTotal:  Int { slowCounts.values.reduce(0, +) }
        var xSlowTotal: Int { xSlowCounts.values.reduce(0, +) }

        // Ticks for all slow items to each be dispatched once
        var slowRotationTicks: Double {
            guard !config.slowQueue.isEmpty else { return 0 }
            let slowSlots = Double(totalTicks) / 3.0
            let slowDispatched = Double(slowTotal)
            guard slowDispatched > 0 else { return 0 }
            let slotsPerRotation = slowSlots / (slowDispatched / Double(config.slowQueue.count))
            return slotsPerRotation * 3.0
        }

        // Ticks for all x-slow items to each be dispatched once
        var xSlowRotationTicks: Double {
            guard !config.xSlowQueue.isEmpty else { return 0 }
            let xSlowDispatched = Double(xSlowTotal)
            guard xSlowDispatched > 0 else { return 0 }
            let slowSlots = Double(totalTicks) / 3.0
            let slotsPerXSlowItem = slowSlots / (xSlowDispatched / Double(config.xSlowQueue.count))
            return slotsPerXSlowItem * 3.0
        }
    }

    private func simulate(config: Config, ticks: Int) -> Results {
        var r = Results(totalTicks: ticks, config: config)
        for name in config.slowQueue  { r.slowCounts[name]  = 0 }
        for name in config.xSlowQueue { r.xSlowCounts[name] = 0 }

        var pollTick      = 0
        var slowIndex     = 0
        var xSlowIndex    = 0
        var xSlowCounter  = 0

        for _ in 0..<ticks {
            switch pollTick % 3 {
            case 0:
                r.currentCount += 1
            case 1:
                r.voltageCount += 1
            default:
                if config.xSlowInterval > 0 {
                    xSlowCounter += 1
                    if xSlowCounter % config.xSlowInterval == 0 {
                        let name = config.xSlowQueue[xSlowIndex % config.xSlowQueue.count]
                        r.xSlowCounts[name, default: 0] += 1
                        xSlowIndex += 1
                    } else {
                        let name = config.slowQueue[slowIndex % config.slowQueue.count]
                        r.slowCounts[name, default: 0] += 1
                        slowIndex += 1
                    }
                } else {
                    let name = config.slowQueue[slowIndex % config.slowQueue.count]
                    r.slowCounts[name, default: 0] += 1
                    slowIndex += 1
                }
            }
            pollTick += 1
        }
        return r
    }

    // MARK: - Report printer

    private func printReport(_ r: Results, rttMs: Double) {
        let secPerTick = rttMs / 1000.0
        let totalSec   = Double(r.totalTicks) * secPerTick

        print("")
        print("╔══════════════════════════════════════════════════════╗")
        print("║  \(r.config.name.padding(toLength: 51, withPad: " ", startingAt: 0))║")
        print("╠══════════════════════════════════════════════════════╣")
        print("  Simulated ticks : \(r.totalTicks)  (\(String(format: "%.0f", totalSec)) s at \(Int(rttMs)) ms/tick)")
        print("  Total dispatches: \(r.totalDispatches)")
        print("  ── Fast lane ──────────────────────────────────────────")
        let curHz  = Double(r.currentCount) / totalSec
        let voltHz = Double(r.voltageCount) / totalSec
        print("  Current : \(r.currentCount) dispatches  \(String(format: "%.2f", curHz)) Hz")
        print("  Voltage : \(r.voltageCount) dispatches  \(String(format: "%.2f", voltHz)) Hz")
        print("  ── Slow queue (\(r.config.slowQueue.count) items) ─────────────────────────")
        for name in r.config.slowQueue {
            let n = r.slowCounts[name] ?? 0
            print("  \(name.padding(toLength: 12, withPad: " ", startingAt: 0)): \(n) dispatches")
        }
        let slowRotSec = r.slowRotationTicks * secPerTick
        print("  Rotation period : ~\(String(format: "%.1f", r.slowRotationTicks)) ticks  (~\(String(format: "%.1f", slowRotSec)) s)")
        if !r.config.xSlowQueue.isEmpty {
            print("  ── X-slow queue (\(r.config.xSlowQueue.count) items, every \(r.config.xSlowInterval) slow slots) ──────")
            for name in r.config.xSlowQueue {
                let n = r.xSlowCounts[name] ?? 0
                print("  \(name.padding(toLength: 12, withPad: " ", startingAt: 0)): \(n) dispatches")
            }
            let xSlowRotSec = r.xSlowRotationTicks * secPerTick
            print("  Rotation period : ~\(String(format: "%.0f", r.xSlowRotationTicks)) ticks  (~\(String(format: "%.0f", xSlowRotSec)) s)")
        }
        print("╚══════════════════════════════════════════════════════╝")
    }

    // MARK: - Configurations

    // Original queue structure before Nov-2026 optimisation.
    private let configBefore = Config(
        name: "BEFORE  (9-item slow queue, no x-slow tier)",
        slowQueue: ["runTime", "SOC", "status", "temp", "curKwh",
                    "cellMin", "cellMax", "cellAvg", "cellStdDev"],
        xSlowQueue: [],
        xSlowInterval: 0
    )

    // Current queue structure after Nov-2026 optimisation.
    private let configAfter = Config(
        name: "AFTER   (3-item slow + 3-item x-slow @ 67)",
        slowQueue: ["status", "cellMin", "cellMax"],
        xSlowQueue: ["SOC", "curKwh", "temp"],
        xSlowInterval: 67
    )

    // MARK: - Tests

    /// Theoretical cadence at the ideal 150 ms/tick round-trip from earlier bench data.
    func testCadenceIdealRTT() {
        let ticks = 3_000
        let rttMs = 150.0
        let before = simulate(config: configBefore, ticks: ticks)
        let after  = simulate(config: configAfter,  ticks: ticks)
        printReport(before, rttMs: rttMs)
        printReport(after,  rttMs: rttMs)
        printImprovement(before: before, after: after, rttMs: rttMs)
    }

    /// Theoretical cadence at the observed real-world ~300 ms/tick round-trip.
    func testCadenceRealWorldRTT() {
        let ticks = 3_000
        let rttMs = 300.0
        let before = simulate(config: configBefore, ticks: ticks)
        let after  = simulate(config: configAfter,  ticks: ticks)
        printReport(before, rttMs: rttMs)
        printReport(after,  rttMs: rttMs)
        printImprovement(before: before, after: after, rttMs: rttMs)
    }

    private func printImprovement(before: Results, after: Results, rttMs: Double) {
        let secPerTick = rttMs / 1000.0
        let bRot = before.slowRotationTicks * secPerTick
        let aRot = after.slowRotationTicks  * secPerTick
        let speedup = bRot / aRot
        print("")
        print("  ── Improvement summary (\(Int(rttMs)) ms/tick) ─────────────────")
        print("  Slow rotation  BEFORE: \(String(format: "%.1f", bRot)) s")
        print("  Slow rotation  AFTER : \(String(format: "%.1f", aRot)) s")
        print("  Speedup               : \(String(format: "%.2f", speedup))×")
        if !after.config.xSlowQueue.isEmpty {
            let xRot = after.xSlowRotationTicks * secPerTick
            print("  X-slow poll interval  : ~\(String(format: "%.0f", xRot)) s per item")
        }
        print("  ────────────────────────────────────────────────────────")
    }
}
