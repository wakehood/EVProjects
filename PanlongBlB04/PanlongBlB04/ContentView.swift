//
//  ContentView.swift
//  PanlongBlB04
//
//  Created by Sylvia Wake-Hood on 7/7/26.
import SwiftUI
import OBD2Kit
import CoreBluetooth

struct ContentView: View {
    var body: some View { OBD2DashboardView() }
}

struct OBD2DashboardView: View {
    @State private var bluetoothManager = OBD2ConnectionManager(autoConnect: false)

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    // Status Header Connection Display Card
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hardware Node Connection").font(.caption).foregroundColor(.secondary)
                            Text(bluetoothManager.connectionStatus)
                                .font(.body).fontWeight(.bold).foregroundColor(statusColor)
                        }
                        Spacer()
                        Button("Forget") {
                            bluetoothManager.forgetPreferredPeripheral()
                        }
                        .font(.caption2).fontWeight(.bold).padding(8)
                        .background(bluetoothManager.isConnected ? Color.secondary.opacity(0.3) : Color.orange)
                        .foregroundColor(.white).cornerRadius(6)
                        .disabled(bluetoothManager.isConnected)
                        Button(bluetoothManager.isConnected ? "Disconnect" : "Connect") {
                            if bluetoothManager.isConnected { bluetoothManager.disconnect() }
                            else { bluetoothManager.connect() }
                        }
                        .font(.caption2).fontWeight(.bold).padding(8)
                        .background(bluetoothManager.isScanning ? Color.secondary.opacity(0.3)
                                    : bluetoothManager.isConnected ? Color.red : Color.blue)
                        .foregroundColor(.white).cornerRadius(6)
                        .disabled(bluetoothManager.isScanning)
                    }
                    .frame(maxWidth: .infinity).padding(10).background(Color(.systemBackground)).cornerRadius(10).shadow(radius: 1)

                    // System Fault Indicator Warning Flags Panel Block
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MCU Diagnostic Warning Status Flags").font(.caption).foregroundColor(.secondary).fontWeight(.bold)
                        HStack(spacing: 6) {
                            AlertLamp(name: "Hardware", state: bluetoothManager.alertHardware)
                            AlertLamp(name: "CCensus", state: bluetoothManager.alertCCensus)
                            AlertLamp(name: "TCensus", state: bluetoothManager.alertTCensus)
                            AlertLamp(name: "HVC", state: bluetoothManager.alertHVC)
                            AlertLamp(name: "LVC", state: bluetoothManager.alertLVC)
                            AlertLamp(name: "HiTemp", state: bluetoothManager.alertHiTemp)
                            AlertLamp(name: "LoTemp", state: bluetoothManager.alertLoTemp)
                        }
                    }
                    .frame(maxWidth: .infinity).padding(10).background(Color(.systemBackground)).cornerRadius(10)

                    // Core Telemetry Parameter Rows
                    Group {
                        MetricRow(title: "MCU RunTime", color: .green, val: bluetoothManager.mcuRunTime, cmd: "01 1F", btn: "Live", bm: bluetoothManager)
                        MetricRow(title: "MCU Version", color: .blue, val: bluetoothManager.mcuVersion, cmd: "22 DD 80", btn: "Query", bm: bluetoothManager)
                        MetricRow(title: "MCU Pack Voltage", color: .purple, val: bluetoothManager.mcuPackVoltage, cmd: "22 DD 83", btn: "Live", bm: bluetoothManager)
                        MetricRow(title: "MCU Pack Current", color: .orange, val: bluetoothManager.mcuPackCurrent, cmd: "22 DD 84", btn: "Live", bm: bluetoothManager)
                        MetricRow(title: "Pack State of Charge", color: .cyan, val: bluetoothManager.mcuSOC, cmd: "22 DD 85", btn: "Live", bm: bluetoothManager)
                    }

                    // Battery Cell Parameter Rows
                    Group {
                        MetricRow(title: "Cell Minimum", color: .indigo, val: bluetoothManager.cellMin, cmd: "22 DD 86", btn: "Live", bm: bluetoothManager)
                        MetricRow(title: "Cell Maximum", color: .pink, val: bluetoothManager.cellMax, cmd: "22 DD 87", btn: "Live", bm: bluetoothManager)
                        MetricRow(title: "Cell Mean", color: .teal, val: bluetoothManager.cellMean, cmd: "22 DD 88", btn: "Live", bm: bluetoothManager)
                        MetricRow(title: "Cell Std Dev", color: .red, val: bluetoothManager.cellStdDev, cmd: "22 DD 89", btn: "Live", bm: bluetoothManager)
                    }

                    // Cutoff Thresholds and Energy Parameters
                    Group {
                        MetricRow(title: "MCU High Voltage Cutoff", color: .mint, val: String(format: "%.2f V", bluetoothManager.rawMcuHighVoltageCutoff), cmd: "22 DD 8A", btn: "Query", bm: bluetoothManager)
                        MetricRow(title: "MCU Low Voltage Cutoff", color: .brown, val: String(format: "%.2f V", bluetoothManager.rawMcuLowVoltageCutoff), cmd: "22 DD 8B", btn: "Query", bm: bluetoothManager)
                        MetricRow(title: "MCU Temp (Hi / Lo)", color: .yellow, val: String(format: "%.0f° / %.0f° C", bluetoothManager.rawMcuHighTemp, bluetoothManager.rawMcuLowTemp), cmd: "22 DD 8C", btn: "Live", bm: bluetoothManager)
                        MetricRow(title: "Pack Max Capacity", color: .purple, val: String(format: "%.1f kWh", bluetoothManager.rawPackCapacityKwh), cmd: "22 DD 8D", btn: "Query", bm: bluetoothManager)
                        MetricRow(title: "Pack Current Energy", color: .teal, val: String(format: "%.1f kWh", bluetoothManager.rawCurrentKwh), cmd: "22 DD 8E", btn: "Live", bm: bluetoothManager)
                    }

                    // Burst Performance Test Toggle Card
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("DD84 Burst Performance Test").font(.caption).foregroundColor(.orange).fontWeight(.bold)
                            if bluetoothManager.isBurstTesting {
                                Text("Run #\(bluetoothManager.burstRunCount + 1) \u{2014}  Sent: \(bluetoothManager.burstSentCount)   Rcvd: \(bluetoothManager.burstReplyCount)   TO: \(bluetoothManager.burstTimeoutCount)")
                                    .font(.system(.caption2, design: .monospaced)).foregroundColor(.orange)
                            }
                        }
                        Spacer()
                        Button("Start Test") { bluetoothManager.startBurstTest() }
                            .font(.caption2).fontWeight(.bold).padding(8)
                            .background(bluetoothManager.isBurstTesting || !bluetoothManager.isConnected ? Color.secondary.opacity(0.3) : Color.orange)
                            .foregroundColor(.white).cornerRadius(6)
                            .disabled(!bluetoothManager.isConnected || bluetoothManager.isBurstTesting)
                    }
                    .frame(maxWidth: .infinity).padding(10).background(Color(.systemBackground)).cornerRadius(10)

                    // Polling Cadence Metrics Test Card
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Polling Cadence Test (30 s)").font(.caption).foregroundColor(.teal).fontWeight(.bold)
                            if bluetoothManager.isPollingMetricsRunning {
                                Text("Cur: \(bluetoothManager.pollingMetricsCurrentCount)  Volt: \(bluetoothManager.pollingMetricsVoltageCount)  Slow: \(bluetoothManager.pollingMetricsSlowCount)  Total: \(bluetoothManager.pollingMetricsTotalCount)")
                                    .font(.system(.caption2, design: .monospaced)).foregroundColor(.teal)
                            }
                        }
                        Spacer()
                        Button(bluetoothManager.isPollingMetricsRunning ? "Stop" : "Start Test") {
                            if bluetoothManager.isPollingMetricsRunning { bluetoothManager.stopPollingMetricsTest() }
                            else { bluetoothManager.startPollingMetricsTest() }
                        }
                        .font(.caption2).fontWeight(.bold).padding(8)
                        .background(!bluetoothManager.isConnected || bluetoothManager.isBurstTesting ? Color.secondary.opacity(0.3) : Color.teal)
                        .foregroundColor(.white).cornerRadius(6)
                        .disabled(!bluetoothManager.isConnected || bluetoothManager.isBurstTesting)
                    }
                    .frame(maxWidth: .infinity).padding(10).background(Color(.systemBackground)).cornerRadius(10)

                    // CAN Bus Monitor Mode Card
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CAN Bus Monitor Mode (AT MA)").font(.caption).foregroundColor(.purple).fontWeight(.bold)
                            Text(bluetoothManager.isMonitorModeActive
                                 ? (bluetoothManager.isConnected ? "Active — all CAN frames printing to console" : "Enabled — will activate on next connect")
                                 : "Disabled — normal polling on connect")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(bluetoothManager.isMonitorModeActive ? .purple : .secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $bluetoothManager.isMonitorModeActive)
                            .labelsHidden()
                            .tint(.purple)
                            .disabled(bluetoothManager.isConnected)
                    }
                    .frame(maxWidth: .infinity).padding(10).background(Color(.systemBackground)).cornerRadius(10)

                    // BLE Peripheral Scanner — scan all BLE devices to diagnose adapter service UUIDs
                    BLEScanCard()

                    // Active Console Line Trace Output Window Terminal
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bus Active Line Traces").font(.caption2).foregroundColor(.secondary)
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(0..<bluetoothManager.receivedLogs.count, id: \.self) { index in
                                        Text(bluetoothManager.receivedLogs[index]).font(.system(.caption2, design: .monospaced)).foregroundColor(.green).frame(maxWidth: .infinity, alignment: .leading).id(index)
                                    }
                                }
                                .padding(6)
                            }
                            .frame(height: 80).background(Color.black).cornerRadius(6)
                            .onChange(of: bluetoothManager.receivedLogs.count) { _, newValue in
                                if newValue > 0 { withAnimation { proxy.scrollTo(newValue - 1) } }
                            }
                        }
                    }
                }.padding(.horizontal, 12).padding(.top, 10)
            }
            .background(Color(.systemGroupedBackground)).navigationTitle("MCU Monitor")
        }
    }

    private var statusColor: Color {
        switch bluetoothManager.connectionStatus {
        case "Connected": return .green
        case "Scanning...", "Connecting...", "Initializing...": return .orange
        case "Ready to Connect", "Ready to Scan": return .blue
        default: return .red
        }
    }
}

struct MetricRow: View {
    let title: String; let color: Color; let val: String; let cmd: String; let btn: String; let bm: OBD2ConnectionManager
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).font(.caption).foregroundColor(color).fontWeight(.bold)
                Text(val).font(.system(.body, design: .rounded)).fontWeight(.black)
            }
            Spacer()
            Button(btn) { bm.sendCommand(cmd) }.font(.caption2).fontWeight(.bold).padding(8).background(bm.connectionStatus == "Connected" ? color : Color.secondary.opacity(0.3)).foregroundColor(.white).cornerRadius(6).disabled(bm.connectionStatus != "Connected")
        }.padding(10).background(Color(.systemBackground)).cornerRadius(10)
    }
}

struct AlertLamp: View {
    let name: String; let state: Int
    var body: some View {
        VStack(spacing: 4) {
            Circle().fill(state == 1 ? Color.red : Color.green).frame(width: 14, height: 14).shadow(color: state == 1 ? Color.red : Color.clear, radius: 4)
            Text(name).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity).padding(.vertical, 6).background(Color(.systemGroupedBackground).opacity(0.5)).cornerRadius(6)
    }
}

// MARK: - BLE Peripheral Scanner

@Observable
class BLEPeripheralScanner: NSObject, CBCentralManagerDelegate {
    struct Entry: Identifiable {
        let id: UUID
        let name: String
        var rssi: Int
        var serviceUUIDs: [String]
    }

    var isScanning = false
    var discovered: [Entry] = []
    private var central: CBCentralManager?

    func startScan() {
        discovered = []
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil)
        } else if central?.state == .poweredOn {
            beginScan()
        }
    }

    func stopScan() {
        central?.stopScan()
        isScanning = false
    }

    private func beginScan() {
        isScanning = true
        central?.scanForPeripherals(withServices: nil,
                                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { beginScan() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
            .map { $0.uuidString.uppercased() } ?? []
        let entry = Entry(id: peripheral.identifier,
                          name: peripheral.name ?? "(unnamed)",
                          rssi: RSSI.intValue,
                          serviceUUIDs: services)
        if let idx = discovered.firstIndex(where: { $0.id == peripheral.identifier }) {
            discovered[idx] = entry
        } else {
            discovered.append(entry)
        }
    }
}

struct BLEScanCard: View {
    @State private var scanner = BLEPeripheralScanner()

    var sorted: [BLEPeripheralScanner.Entry] {
        scanner.discovered.sorted { $0.rssi > $1.rssi }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BLE Peripheral Scanner").font(.caption).foregroundColor(.indigo).fontWeight(.bold)
                    Text(scanner.isScanning ? "Scanning all BLE devices…" : "Tap Start to discover all nearby BLE devices")
                        .font(.system(.caption2, design: .monospaced)).foregroundColor(.secondary)
                }
                Spacer()
                Button(scanner.isScanning ? "Stop" : "Start") {
                    scanner.isScanning ? scanner.stopScan() : scanner.startScan()
                }
                .font(.caption2).fontWeight(.bold).padding(8)
                .background(scanner.isScanning ? Color.red : Color.indigo)
                .foregroundColor(.white).cornerRadius(6)
            }

            if !scanner.discovered.isEmpty {
                Text("\(sorted.count) device(s) found — sorted by signal strength")
                    .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)

                ForEach(sorted) { entry in
                    let isFFF0 = entry.serviceUUIDs.contains(where: { $0.contains("FFF0") })
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(isFFF0 ? Color.green : Color.secondary.opacity(0.4))
                            .frame(width: 8, height: 8)
                            .padding(.top, 3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(isFFF0 ? .green : .primary)
                            Text("RSSI: \(entry.rssi) dBm  |  UUID: \(entry.id.uuidString)")
                                .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                            if entry.serviceUUIDs.isEmpty {
                                Text("Services: (none advertised)")
                                    .font(.system(size: 9, design: .monospaced)).foregroundColor(.orange)
                            } else {
                                Text("Services: \(entry.serviceUUIDs.joined(separator: ", "))")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(isFFF0 ? .green : .orange)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10).background(Color(.systemBackground)).cornerRadius(10)
    }
}

#Preview { ContentView() }
