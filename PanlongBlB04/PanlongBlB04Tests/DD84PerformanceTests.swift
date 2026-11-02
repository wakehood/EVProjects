import XCTest
import OBD2Kit
@testable import PanlongBlB04

final class DD84PerformanceTests: XCTestCase {

    // Overrides sendCommand so no BLE hardware is needed.
    private final class FastCommandManager: OBD2ConnectionManager {
        nonisolated(unsafe) var callCount = 0
        override func sendCommand(_ command: String) {
            callCount += 1
        }
    }

    // XCTest baseline benchmark — 10 iterations, builds a statistical baseline.
    func testDD84XCTestMeasure() {
        let manager = FastCommandManager()
        measure {
            for _ in 0..<10_000 {
                manager.sendCommand("22 DD 84")
            }
        }
    }

    // Single-run burst: reports commands/second to the console.
    func testDD84BurstThroughput() {
        let manager = FastCommandManager()
        let iterations = 100_000

        let start = ContinuousClock.now
        for _ in 0..<iterations {
            manager.sendCommand("22 DD 84")
        }
        let elapsed = ContinuousClock.now - start

        let totalSeconds = Double(elapsed.components.seconds) +
                           Double(elapsed.components.attoseconds) / 1e18
        let rate = Double(iterations) / totalSeconds

        print("22 DD 84 burst: \(iterations) commands in \(String(format: "%.4f", totalSeconds))s")
        print("Throughput: \(Int(rate)) commands/sec")

        XCTAssertEqual(manager.callCount, iterations)
    }
}
