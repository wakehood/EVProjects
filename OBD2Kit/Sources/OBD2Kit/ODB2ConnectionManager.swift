//
//  ODB2ConnectionManager.swift
//  OBD2Kit
//

import Foundation
import CoreBluetooth
import Observation

@Observable
open class OBD2ConnectionManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    public var connectionStatus = String(localized: "Initializing...")
    public var isScanning = false
    public var receivedLogs: [String] = []

    public var isConnected: Bool = false
    public var hasReceivedStatus: Bool = false
    public var isChargingAllowed: Bool = false
    public var isChargePlugConnected: Bool = false
    private var mockTimer: Timer?

    public var mcuRunTime = "--:--:--"
    public var mcuVersion = "--.--"
    public var mcuPackVoltage = "--.- V"
    public var mcuPackCurrent = "--.- A"
    public var mcuSOC = "--%"
    public var cellMin = "--.---- V"
    public var cellMax = "--.---- V"
    public var cellMean = "--.---- V"
    public var cellStdDev = "--.---- V"

    public var rawRunTimeSeconds = 0
    public var rawVersionData: (major: Int, minor: Int, patch: Int) = (0, 0, 0)
    public var firmwareTooOld: Bool = false
    public var rawPackVoltage = 0.0
    public var rawPackCurrent = 0.0
    public var rawSOCPercentage = 0
    public var rawCellMin = 0.0
    public var rawCellMax = 0.0
    public var rawCellMean = 0.0
    public var rawCellStdDev = 0.0
    public var rawMcuHighVoltageCutoff = 0.0  //volts
    public var rawMcuLowVoltageCutoff  = 0.0 //volts

    public var rawMcuHighTemp = 0.0
    public var rawMcuLowTemp = 0.0

    public var rawPackCapacityKwh = 0.0
    public var rawCurrentKwh = 0.0
    public var rawAvailableEnergyKwh: Double { Double(rawSOCPercentage) / 100.0 * rawPackCapacityKwh }

    public var rawVcuMotorRPM = 0.0
    public var rawVcuHighTemp = 35.0
    public var rawVcuLowTemp  = 28.0

    public var alertGroundFault = 0
    public var alertHardware = 0
    public var alertCCensus = 0
    public var alertTCensus = 0
    public var alertHVC = 0
    public var alertLVC = 0
    public var alertHiTemp = 0
    public var alertLoTemp = 0
    public var alertNotLocked = 0
    public var alertIllegalConf = 0

    public var isBurstTesting = false
    public var burstSentCount = 0
    public var burstReplyCount = 0
    public var burstTimeoutCount = 0
    public var burstRunCount = 0

    public var isPollingMetricsRunning = false
    public var pollingMetricsTotalCount = 0
    public var pollingMetricsCurrentCount = 0
    public var pollingMetricsVoltageCount = 0
    public var pollingMetricsSlowCount = 0

    // When true, handshake ends with AT MA (Monitor All) instead of starting polling.
    // The ELM327 streams every CAN frame it sees; use this to verify injected frames
    // reach the bus before testing the autonomous message path.
    // Must be set before connecting. To stop, disconnect.
    public var isMonitorModeActive = false

    private var centralManager: CBCentralManager?
    private var obdPeripheral: CBPeripheral?
    private var scanTimeoutTask: DispatchWorkItem?
    private var connectTimeoutTask: DispatchWorkItem?
    public var scanTimedOut: Bool = false
    private var txCharacteristic: CBCharacteristic?
    private var rxCharacteristic: CBCharacteristic?
    private var incomingBuffer = ""
    private var currentInitStep = 0
    // Response gate: tracks which PID we're waiting on.
    // An arriving message only clears the gate if its prefix matches pendingResponsePrefix.
    // Autonomous (unsolicited) messages are parsed for data but leave the gate intact.
    private var waitingForResponse = false
    private var pendingResponsePrefix: String? = nil
    private var responseTimeoutTask: DispatchWorkItem?
    private var isPollingActive = false
    private var pollingWatchdog: DispatchWorkItem?
    private var pollTickCounter = 0
    private var slowQueueIndex = 0
    private var burstStartDate: Date?
    private var burstStartInstant: ContinuousClock.Instant?
    private var burstTimeoutWorkItem: DispatchWorkItem?
    private var burstDurationWorkItem: DispatchWorkItem?
    private var burstStopRequested = false
    private var burstRunResults: [(rps: Double, successRate: Double, timeouts: Int)] = []
    private var pollingMetricsStartInstant: ContinuousClock.Instant?
    private var pollingMetricsDurationWorkItem: DispatchWorkItem?
    private var mockAlertTick = 0

    public let isPreviewMock: Bool
    public private(set) var isDemoModeActive: Bool = false

    private let serialServiceUUID = CBUUID(string: "FFF0")
    private let writeCharacteristicUUID = CBUUID(string: "FFF1")
    private let notifyCharacteristicUUID = CBUUID(string: "FFF2")
    private let preferredPeripheralUUIDKey = "preferredOBDPeripheralUUID"
    private let rssiConnectThreshold = -85  // dBm; ignores adapters too far away to be "ours"

    //MCU PIDs and commands
    private let customServiceReq  = "22 "
    private let customServiceResp = "62 "

    //MCU Run Time
    private let mcuRunTimeReq: String   = "01 1F"
    private let mcuRunTimeResp: String  = "411F"

    //MCU Version
    private let mcuVersionPid: String   = "DD 80"
    var mcuVersionReq: String {
        get {self.customServiceReq + self.mcuVersionPid}
    }
    var mcuVersionResp: String {
        get {(self.customServiceResp + self.mcuVersionPid).replacingOccurrences(of: " ", with: "")}
    }

    //MCU Status/Alerts
    private let mcuStatusPid: String    = "DD 81"
    var mcuStatusReq: String {
        get {self.customServiceReq + self.mcuStatusPid}
    }
    var mcuStatusResp: String {
        get {(self.customServiceResp + self.mcuStatusPid).replacingOccurrences(of: " ", with: "")}
    }

    //MCU Pack Voltage
    private let mcuPackVoltPid: String  = "DD 83"
    var mcuPackVoltReq: String {
        get {self.customServiceReq + self.mcuPackVoltPid}
    }
    var mcuPackVoltResp: String {
        get {(self.customServiceResp + self.mcuPackVoltPid).replacingOccurrences(of: " ", with: "")}
    }

    //MCU Pack Current
    private let mcuPackCurPid: String   = "DD 84"
    var mcuPackCurReq: String {
        get {self.customServiceReq + self.mcuPackCurPid}
    }
    var mcPackCurResp: String {
        get {(self.customServiceResp + self.mcuPackCurPid).replacingOccurrences(of: " ", with: "")}
    }

    //MCU State of Charge
    private let mcuSocPid: String       = "DD 85"
    var mcuSocReq: String {
        get {self.customServiceReq + self.mcuSocPid}
    }
    var mcuSocResp: String {
        get {(self.customServiceResp + self.mcuSocPid).replacingOccurrences(of: " ", with: "")}
    }

    //MCU Cell Min Voltage
    private let mcuCellMinPid: String   = "DD 86"
    var mcuCellMinReq: String {
        get {self.customServiceReq + self.mcuCellMinPid}
    }
    var mcuCellMinResp: String {
        get {(self.customServiceResp + self.mcuCellMinPid).replacingOccurrences(of: " ", with: "")}
    }

    //MCU Cell Max Voltage
    private let mcuCellMaxPid: String   = "DD 87"
    var mcuCellMaxReq: String {
        get {self.customServiceReq + self.mcuCellMaxPid}
    }
    var mcuCellMaxResp: String {
        get {(self.customServiceResp + self.mcuCellMaxPid).replacingOccurrences(of: " ", with: "")}
    }

    //MCU Cell Mean Voltage
    private let mcuCellAvgPid: String   = "DD 88"
    var mcuCellAvgReq: String {
        get {self.customServiceReq + self.mcuCellAvgPid}
    }
    var mcuCellAvgResp: String {
        get {(self.customServiceResp + self.mcuCellAvgPid).replacingOccurrences(of: " ", with: "")}
    }

    //MCU Std Deviation Cell Voltages
    private let mcuStdDevPid: String    = "DD 89"
    var mcuStdDevReq: String {
        get {self.customServiceReq + self.mcuStdDevPid}
    }
    var mcuStdDevResp: String {
        get {(self.customServiceResp + self.mcuStdDevPid).replacingOccurrences(of: " ", with: "")}
    }

    //MCU High Voltage Cutoff
    private let mcuHvcPid: String       = "DD 8A"
    var mcuHvcReq: String {
        get {self.customServiceReq + self.mcuHvcPid}
    }
    var mcuHvcResp: String {
        get {(self.customServiceResp + self.mcuHvcPid).replacingOccurrences(of: " ", with: "")}
    }

    //MCU Low voltage Cutoff
    private let mcuLvcPid: String       = "DD 8B"
    var mcuLvcReq: String {
        get {self.customServiceReq + self.mcuLvcPid}
    }
    var mcuLvcResp: String {
        get {(self.customServiceResp + self.mcuLvcPid).replacingOccurrences(of: " ", with: "")}
    }

    //MCU High and Low temperature
    private let mcuTempPid: String      = "DD 8C"
    var mcuTempReq: String {
        get {self.customServiceReq + self.mcuTempPid}
    }
    var mcuTempResp: String {
        get {(self.customServiceResp + self.mcuTempPid).replacingOccurrences(of: " ", with: "")}
    }

    //MCU Max capacity in kWh
    private let mcuMaxKwhPid: String    = "DD 8D"
    var mcuMaxKwhReq: String {
        get {self.customServiceReq + self.mcuMaxKwhPid}
    }
    var mcuMaxKwhResp: String {
        get {(self.customServiceResp + self.mcuMaxKwhPid).replacingOccurrences(of: " ", with: "")}
    }

    //MCU Current Capacity in kWh
    private let mcuCurKwhPid: String    = "DD 8E"
    var mcuCurKwhReq: String {
        get {self.customServiceReq + self.mcuCurKwhPid}
    }
    var mcuCurKwhResp: String {
        get {(self.customServiceResp + self.mcuCurKwhPid).replacingOccurrences(of: " ", with: "")}
    }



    public init(isPreviewMock: Bool = false, autoConnect: Bool = true) {
        self.isPreviewMock = isPreviewMock
        super.init()

        if isPreviewMock {
            startMockDataStream()
        } else if autoConnect {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        } else {
            connectionStatus = String(localized: "Ready to Connect")
        }
    }

    public func connect() {
        guard !isPreviewMock else { return }
        if centralManager == nil {
            connectionStatus = String(localized: "Initializing...")
            centralManager = CBCentralManager(delegate: self, queue: nil)
        } else {
            retryScanning()
        }
    }

    public func startMockDataStream() {
        self.rawSOCPercentage = 78
        self.isConnected = true
        self.isChargingAllowed = true
        self.isChargePlugConnected = true

        self.rawPackVoltage = 147.0
        self.rawPackCurrent = 16.8 // ~2.47 kW

        self.rawCellMin = 2.9
        self.rawCellMax = 3.1
        self.rawCellMean = 3.0
        self.rawCellStdDev = 0.008
        self.rawMcuHighVoltageCutoff = 3.40  //volts
        self.rawMcuLowVoltageCutoff  = 2.40 //volts

        self.rawMcuLowTemp = 24.0
        self.rawMcuHighTemp = 31.0
        self.rawVcuMotorRPM = 3_500.0
        self.rawVcuLowTemp  = 35.0
        self.rawVcuHighTemp = 42.0

        self.rawPackCapacityKwh = 20.0
        self.rawCurrentKwh = Double(self.rawSOCPercentage) / 100.0 * self.rawPackCapacityKwh

        self.alertGroundFault = 0
        self.alertHardware    = 0
        self.alertCCensus     = 0
        self.alertTCensus     = 0
        self.alertHVC         = 0
        self.alertLVC         = 0
        self.alertHiTemp      = 0
        self.alertLoTemp      = 0
        self.alertNotLocked   = 0
        self.alertIllegalConf = 0

        mockAlertTick = 0
        mockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            Task { @MainActor in
                self.rawPackVoltage = max(100.0, min(160.0, self.rawPackVoltage + Double.random(in: -0.5...0.5)))
                self.rawPackCurrent = max(-100.0, min(150.0, self.rawPackCurrent + Double.random(in: -1.5...1.5)))

                let variance = Double.random(in: -0.01...0.01)
                self.rawCellMean = max(3.2, min(4.2, self.rawCellMean + variance))
                self.rawCellMin = self.rawCellMean - Double.random(in: 0.01...0.03)
                self.rawCellMax = self.rawCellMean + Double.random(in: 0.01...0.03)
                self.rawCellStdDev = max(0.002, min(0.040, self.rawCellStdDev + Double.random(in: -0.001...0.001)))

                // Temperatures drift slowly; high always stays above low
                self.rawMcuLowTemp  = max(15.0, min(45.0, self.rawMcuLowTemp  + Double.random(in: -0.3...0.3)))
                self.rawMcuHighTemp = max(self.rawMcuLowTemp + 2.0, min(60.0, self.rawMcuHighTemp + Double.random(in: -0.3...0.3)))

                self.rawVcuMotorRPM = max(0, min(18_000, self.rawVcuMotorRPM + Double.random(in: -300...300)))
                self.rawVcuLowTemp  = max(20.0, min(55.0, self.rawVcuLowTemp  + Double.random(in: -0.5...0.5)))
                self.rawVcuHighTemp = max(self.rawVcuLowTemp + 2.0, min(75.0, self.rawVcuHighTemp + Double.random(in: -0.5...0.5)))

                if self.rawSOCPercentage > 1 && Double.random(in: 0...1) > 0.7 {
                    self.rawSOCPercentage -= 1
                }
                self.rawCurrentKwh = Double(self.rawSOCPercentage) / 100.0 * self.rawPackCapacityKwh

                // Every 8 seconds toggle a random alert bit to demonstrate the alert UI
                self.mockAlertTick += 1
                if self.mockAlertTick % 8 == 0 {
                    switch Int.random(in: 0...9) {
                    case 0:  self.alertGroundFault  = self.alertGroundFault  == 0 ? 1 : 0
                    case 1:  self.alertHardware     = self.alertHardware     == 0 ? 1 : 0
                    case 2:  self.alertCCensus      = self.alertCCensus      == 0 ? 1 : 0
                    case 3:  self.alertTCensus      = self.alertTCensus      == 0 ? 1 : 0
                    case 4:  self.alertHVC          = self.alertHVC          == 0 ? 1 : 0
                    case 5:  self.alertLVC          = self.alertLVC          == 0 ? 1 : 0
                    case 6:  self.alertHiTemp       = self.alertHiTemp       == 0 ? 1 : 0
                    case 7:  self.alertLoTemp       = self.alertLoTemp       == 0 ? 1 : 0
                    case 8:  self.alertNotLocked    = self.alertNotLocked    == 0 ? 1 : 0
                    default: self.alertIllegalConf  = self.alertIllegalConf  == 0 ? 1 : 0
                    }
                }
            }
        }
    }

    @MainActor deinit {
        mockTimer?.invalidate()
    }

    public func activateDemoMode() {
        isDemoModeActive = true
        centralManager?.stopScan()
        scanTimeoutTask?.cancel()
        connectTimeoutTask?.cancel()
        stopAutomaticPolling()
        if let p = obdPeripheral {
            centralManager?.cancelPeripheralConnection(p)
        }
        obdPeripheral = nil
        isScanning = false
        scanTimedOut = false
        mockTimer?.invalidate()
        mockTimer = nil
        startMockDataStream()
        hasReceivedStatus = true
        mcuVersion = MCUConstants.minimumFirmwareString
        rawVersionData = (MCUConstants.minimumFirmwareMajor, MCUConstants.minimumFirmwareMinor, MCUConstants.minimumFirmwarePatch)
        connectionStatus = String(localized: "Demo Mode")
    }

    public func deactivateDemoMode() {
        mockTimer?.invalidate()
        mockTimer = nil
        isDemoModeActive = false
        resetTelemetry()
        hasReceivedStatus = false
        if let cm = centralManager, cm.state == .poweredOn {
            connectionStatus = String(localized: "Initializing...")
            connect()
        } else {
            connectionStatus = String(localized: "Bluetooth Off")
        }
    }

    public func startScanning() {
        guard let cm = centralManager, cm.state == .poweredOn else { return }

        // If we've connected to an adapter before, reconnect directly without scanning.
        // This avoids grabbing a neighbour's FFF0 adapter in a multi-vehicle environment.
        if let uuidString = UserDefaults.standard.string(forKey: preferredPeripheralUUIDKey),
           let uuid = UUID(uuidString: uuidString),
           let peripheral = cm.retrievePeripherals(withIdentifiers: [uuid]).first {
            scanTimeoutTask?.cancel()
            obdPeripheral = peripheral
            peripheral.delegate = self
            DispatchQueue.main.async {
                self.connectionStatus = String(localized: "Connecting...")
            }
            cm.connect(peripheral, options: nil)
            armConnectTimeout()
            return
        }

        // Full scan — arm a timeout so the user isn't stuck on "Scanning…" forever.
        scanTimedOut = false
        isScanning = true
        connectionStatus = String(localized: "Scanning...")
        cm.scanForPeripherals(withServices: [serialServiceUUID], options: nil)

        scanTimeoutTask?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.isScanning else { return }
            self.centralManager?.stopScan()
            DispatchQueue.main.async {
                self.isScanning = false
                self.scanTimedOut = true
                self.connectionStatus = String(localized: "No Adapter Found")
            }
            print("[scan] timed out after 20s — no FFF0 adapter found")
            self.logMessage("Scan timed out — no adapter found")
        }
        scanTimeoutTask = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeout)
    }

    public func retryScanning() {
        guard !isPreviewMock else { return }
        scanTimedOut = false
        startScanning()
    }

    public func forgetPreferredPeripheral() {
        UserDefaults.standard.removeObject(forKey: preferredPeripheralUUIDKey)
    }

    public func disconnect() {
        if let p = obdPeripheral {
            centralManager?.cancelPeripheralConnection(p)
        }
    }

    open func sendCommand(_ command: String) {
        guard let p = obdPeripheral, let ch = txCharacteristic else { return }
        if let data = (command + "\r").data(using: .utf8) {
            let writeType: CBCharacteristicWriteType = ch.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            p.writeValue(data, for: ch, type: writeType)
            if !isBurstTesting {
                logMessage("Sent: \(command)")
                waitingForResponse = true
                pendingResponsePrefix = expectedResponsePrefix(for: command)
                responseTimeoutTask?.cancel()
                let task = DispatchWorkItem { [weak self] in
                    self?.waitingForResponse = false
                    self?.pendingResponsePrefix = nil
                }
                responseTimeoutTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: task)
            }
        }
    }

    private func logMessage(_ msg: String) {
        DispatchQueue.main.async {
            self.receivedLogs.append(msg)
            if self.receivedLogs.count > 25 {
                self.receivedLogs.removeFirst()
            }
        }
    }

    private func expectedResponsePrefix(for command: String) -> String? {
        switch command {
        case mcuRunTimeReq:  return mcuRunTimeResp
        case mcuVersionReq:  return mcuVersionResp
        case mcuStatusReq:   return mcuStatusResp
        case mcuPackVoltReq: return mcuPackVoltResp
        case mcuPackCurReq:  return mcPackCurResp
        case mcuSocReq:      return mcuSocResp
        case mcuCellMinReq:  return mcuCellMinResp
        case mcuCellMaxReq:  return mcuCellMaxResp
        case mcuCellAvgReq:  return mcuCellAvgResp
        case mcuStdDevReq:   return mcuStdDevResp
        case mcuHvcReq:      return mcuHvcResp
        case mcuLvcReq:      return mcuLvcResp
        case mcuTempReq:     return mcuTempResp
        case mcuMaxKwhReq:   return mcuMaxKwhResp
        case mcuCurKwhReq:   return mcuCurKwhResp
        default:             return nil  // AT commands and unknowns
        }
    }

    private func advanceHandshake() {
        currentInitStep += 1
        // AT Z needs ~1s for the chip to fully reset before accepting the next command.
        // A brief pause before polling starts lets the adapter settle after the version query.
        let delay: TimeInterval
        switch currentInitStep {
        case 1:  delay = 1.5
        case 11: delay = 0.5
        default: delay = 0.4
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            switch self.currentInitStep {
            case 1:  self.sendCommand("AT Z")
            case 2:  self.sendCommand("AT E0")
            case 3:  self.sendCommand("AT H1")
            case 4:  self.sendCommand("AT ST FF")  // maximum bus-search timeout (~1s)
            case 5:  self.sendCommand("AT SP 6")
            case 6:  self.sendCommand("AT SH 7DF")
            case 7:  self.sendCommand(self.mcuVersionReq)
            case 8:  self.sendCommand(self.mcuHvcReq)
            case 9:  self.sendCommand(self.mcuLvcReq)
            case 10: self.sendCommand(self.mcuMaxKwhReq)
            case 11:
                if self.isMonitorModeActive { self.sendCommand("AT MA") }
                else { self.startAutomaticPolling() }
            default: break
            }
        }
    }

    public func startAutomaticPolling() {
        stopAutomaticPolling()
        isPollingActive = true
        pollTickCounter = 0
        slowQueueIndex = 0
        sendNextPollingCommand()
    }

    public func stopAutomaticPolling() {
        isPollingActive = false
        pollingWatchdog?.cancel()
        pollingWatchdog = nil
    }

    // Fast lane (slots 0 and 1 of every 3-tick cycle): current and voltage on every pass.
    // Slow lane (slot 2): one item from this queue per cycle, rotating through all 9.
    // At ~150 ms/round-trip: current & voltage refresh ~450 ms, slow items ~4 s full rotation.
    private var slowPollQueue: [String] {
        [mcuRunTimeReq, mcuSocReq, mcuStatusReq, mcuTempReq, mcuCurKwhReq,
         mcuCellMinReq, mcuCellMaxReq, mcuCellAvgReq, mcuStdDevReq]
    }

    private func sendNextPollingCommand() {
        guard isPollingActive, isConnected, !isBurstTesting, !waitingForResponse else { return }

        let cmd: String
        switch pollTickCounter % 3 {
        case 0:
            cmd = mcuPackCurReq
        case 1:
            cmd = mcuPackVoltReq
        default:
            let slow = slowPollQueue
            cmd = slow[slowQueueIndex % slow.count]
            slowQueueIndex += 1
        }
        if isPollingMetricsRunning {
            pollingMetricsTotalCount += 1
            switch pollTickCounter % 3 {
            case 0: pollingMetricsCurrentCount += 1
            case 1: pollingMetricsVoltageCount += 1
            default: pollingMetricsSlowCount += 1
            }
        }
        pollTickCounter += 1

        sendCommand(cmd)

        // Watchdog: if no response arrives within 2 s, unstick the chain and move on.
        pollingWatchdog?.cancel()
        let watchdog = DispatchWorkItem { [weak self] in
            guard let self, self.isPollingActive else { return }
            self.sendNextPollingCommand()
        }
        pollingWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: watchdog)
    }

    // MARK: - Burst Test

    public func startBurstTest() {
        guard isConnected, !isBurstTesting else { return }
        if isPollingMetricsRunning {
            isPollingMetricsRunning = false
            pollingMetricsDurationWorkItem?.cancel(); pollingMetricsDurationWorkItem = nil
        }
        stopAutomaticPolling()
        isBurstTesting = true; burstStopRequested = false
        burstSentCount = 0; burstReplyCount = 0; burstTimeoutCount = 0
        burstStartDate = Date(); burstStartInstant = ContinuousClock.now
        let stamp = DateFormatter.localizedString(from: burstStartDate!, dateStyle: .none, timeStyle: .medium)
        print("╔══════════════════════════════╗")
        print("║  DD84 BURST TEST START       ║  \(stamp)")
        print("╚══════════════════════════════╝")
        let durationItem = DispatchWorkItem { [weak self] in
            guard let self, self.isBurstTesting else { return }
            self.burstStopRequested = true
        }
        burstDurationWorkItem = durationItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: durationItem)
        sendBurstCommand()
    }

    private func sendBurstCommand() {
        guard isBurstTesting else { return }
        if burstStopRequested { stopBurstTest(); return }
        burstSentCount += 1; sendCommand(mcuPackCurReq); armBurstTimeout()
    }

    private func armBurstTimeout() {
        burstTimeoutWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isBurstTesting else { return }
            self.burstTimeoutCount += 1; self.sendBurstCommand()
        }
        burstTimeoutWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    public func stopBurstTest() {
        isBurstTesting = false; burstStopRequested = false
        burstTimeoutWorkItem?.cancel(); burstTimeoutWorkItem = nil
        burstDurationWorkItem?.cancel(); burstDurationWorkItem = nil
        let stopDate = Date()
        let stopStamp = DateFormatter.localizedString(from: stopDate, dateStyle: .none, timeStyle: .medium)
        let startStamp = burstStartDate.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .medium) } ?? "?"
        let elapsed = burstStartInstant.map { ContinuousClock.now - $0 }
        let secs = elapsed.map { Double($0.components.seconds) + Double($0.components.attoseconds) / 1e18 } ?? 0
        let rps = secs > 0 ? Double(burstReplyCount) / secs : 0
        let pct = burstSentCount > 0 ? Double(burstReplyCount) / Double(burstSentCount) * 100 : 0
        burstRunCount += 1
        burstRunResults.append((rps: rps, successRate: pct, timeouts: burstTimeoutCount))
        print("╔══════════════════════════════╗")
        print("║  DD84 BURST TEST STOP  Run #\(burstRunCount)  ║  \(stopStamp)")
        print("╠══════════════════════════════╣")
        print("  Start:         \(startStamp)")
        print("  Stop:          \(stopStamp)")
        print("  Duration:      \(String(format: "%.3f", secs)) s")
        print("  Sent:          \(burstSentCount)")
        print("  Received:      \(burstReplyCount)")
        print("  Timeouts:      \(burstTimeoutCount)")
        print("  Success Rate:  \(String(format: "%.1f", pct))%")
        print("  Avg Msgs/sec:  \(String(format: "%.2f", rps)) completed round-trips/sec")
        print("╚══════════════════════════════╝")
        if burstRunResults.count >= 2 {
            let rpsList = burstRunResults.map { $0.rps }
            let srList  = burstRunResults.map { $0.successRate }
            let toList  = burstRunResults.map { $0.timeouts }
            let meanRPS = rpsList.reduce(0, +) / Double(rpsList.count)
            let meanSR  = srList.reduce(0, +)  / Double(srList.count)
            let meanTO  = Double(toList.reduce(0, +)) / Double(toList.count)
            print("  ── Cumulative (\(burstRunResults.count) runs) ─────────────────────")
            print("  Avg Msgs/sec:  min=\(String(format: "%.2f", rpsList.min()!))  max=\(String(format: "%.2f", rpsList.max()!))  mean=\(String(format: "%.2f", meanRPS))")
            print("  Success Rate:  min=\(String(format: "%.1f", srList.min()!))%  max=\(String(format: "%.1f", srList.max()!))%  mean=\(String(format: "%.1f", meanSR))%")
            print("  Timeouts/run:  min=\(toList.min()!)  max=\(toList.max()!)  mean=\(String(format: "%.1f", meanTO))")
            print("  ──────────────────────────────────────────────")
        }
        startAutomaticPolling()
    }

    // MARK: - Polling Cadence Metrics Test

    public func startPollingMetricsTest(duration: TimeInterval = 30) {
        guard isConnected, !isPollingMetricsRunning, !isBurstTesting else { return }
        isPollingMetricsRunning = true
        pollingMetricsTotalCount = 0
        pollingMetricsCurrentCount = 0
        pollingMetricsVoltageCount = 0
        pollingMetricsSlowCount = 0
        pollingMetricsStartInstant = ContinuousClock.now
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("╔══════════════════════════════════════╗")
        print("║  POLLING CADENCE TEST START          ║  \(stamp)")
        print("╚══════════════════════════════════════╝")
        let item = DispatchWorkItem { [weak self] in self?.stopPollingMetricsTest() }
        pollingMetricsDurationWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    public func stopPollingMetricsTest() {
        guard isPollingMetricsRunning else { return }
        isPollingMetricsRunning = false
        pollingMetricsDurationWorkItem?.cancel()
        pollingMetricsDurationWorkItem = nil
        let elapsed = pollingMetricsStartInstant.map { ContinuousClock.now - $0 }
        let secs = elapsed.map { Double($0.components.seconds) + Double($0.components.attoseconds) / 1e18 } ?? 0
        guard secs > 0 else { return }
        let totalRate    = Double(pollingMetricsTotalCount)   / secs
        let currentRate  = Double(pollingMetricsCurrentCount) / secs
        let voltageRate  = Double(pollingMetricsVoltageCount) / secs
        let slowRate     = Double(pollingMetricsSlowCount)    / secs
        let curInterval  = pollingMetricsCurrentCount > 0 ? secs / Double(pollingMetricsCurrentCount) * 1000 : 0
        let voltInterval = pollingMetricsVoltageCount > 0 ? secs / Double(pollingMetricsVoltageCount) * 1000 : 0
        let slowRotation = slowRate > 0 ? Double(slowPollQueue.count) / slowRate : 0
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("╔══════════════════════════════════════╗")
        print("║  POLLING CADENCE TEST RESULTS        ║  \(stamp)")
        print("╠══════════════════════════════════════╣")
        print("  Duration:        \(String(format: "%.1f", secs)) s")
        print("  Total commands:  \(pollingMetricsTotalCount)  (\(String(format: "%.1f", totalRate)) cmd/s)")
        print("  ── Fast Lane ──────────────────────────────")
        print("  Pack Current (DD84):  \(pollingMetricsCurrentCount) updates  \(String(format: "%.2f", currentRate)) Hz  avg \(String(format: "%.0f", curInterval)) ms/update")
        print("  Pack Voltage (DD83):  \(pollingMetricsVoltageCount) updates  \(String(format: "%.2f", voltageRate)) Hz  avg \(String(format: "%.0f", voltInterval)) ms/update")
        print("  ── Slow Lane ──────────────────────────────")
        print("  Slow items:  \(pollingMetricsSlowCount) dispatched  \(String(format: "%.2f", slowRate)) Hz  full rotation ~\(String(format: "%.1f", slowRotation)) s")
        print("╚══════════════════════════════════════╝")
    }

    private func printBurstProgress() {
        let elapsed = burstStartInstant.map { ContinuousClock.now - $0 }
        let secs = elapsed.map { Double($0.components.seconds) + Double($0.components.attoseconds) / 1e18 } ?? 0
        let rps = secs > 0 ? Double(burstReplyCount) / secs : 0
        print("  [burst] sent=\(burstSentCount) rcvd=\(burstReplyCount) to=\(burstTimeoutCount) rps=\(String(format: "%.1f", rps))")
    }

    // MARK: - Telemetry Reset

    private func resetTelemetry() {
        mcuRunTime = "--:--:--"
        mcuVersion = "--.--"
        mcuPackVoltage = "--.- V"
        mcuPackCurrent = "--.- A"
        mcuSOC = "--%"
        cellMin = "--.---- V"
        cellMax = "--.---- V"
        cellMean = "--.---- V"
        cellStdDev = "--.---- V"

        rawRunTimeSeconds = 0
        rawVersionData = (0, 0, 0)
        firmwareTooOld = false
        rawPackVoltage = 0.0
        rawPackCurrent = 0.0
        rawSOCPercentage = 0
        rawCellMin = 0.0
        rawCellMax = 0.0
        rawCellMean = 0.0
        rawCellStdDev = 0.0
        rawMcuHighVoltageCutoff = 0.0
        rawMcuLowVoltageCutoff = 0.0
        rawMcuHighTemp = 0.0
        rawMcuLowTemp = 0.0
        rawPackCapacityKwh = 0.0
        rawCurrentKwh = 0.0
        rawVcuMotorRPM = 0.0
        rawVcuHighTemp = 0.0
        rawVcuLowTemp = 0.0

        alertGroundFault = 0
        alertHardware    = 0
        alertCCensus     = 0
        alertTCensus     = 0
        alertHVC         = 0
        alertLVC         = 0
        alertHiTemp      = 0
        alertLoTemp      = 0
        alertNotLocked   = 0
        alertIllegalConf = 0

        isChargingAllowed = false
        isChargePlugConnected = false
        hasReceivedStatus = false
        scanTimedOut = false
    }

    // MARK: - Connection Timeout

    private func armConnectTimeout() {
        connectTimeoutTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            print("[connect timeout] peripheral not responding after 10s — clearing saved UUID so retry scans fresh")
            // Clear the saved UUID so retryScanning() falls through to a full BLE scan
            // rather than looping back to the same unresponsive peripheral.
            // Do NOT cancel the CoreBluetooth connection — cancelling triggers
            // didDisconnectPeripheral → startScanning → armConnectTimeout → loop.
            UserDefaults.standard.removeObject(forKey: self.preferredPeripheralUUIDKey)
            self.obdPeripheral = nil
            DispatchQueue.main.async {
                self.isConnected = false
                self.scanTimedOut = true
                self.connectionStatus = String(localized: "No Adapter Found")
                self.logMessage("Connect timeout — adapter not in range, cleared saved UUID")
            }
        }
        connectTimeoutTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: task)
    }

    // MARK: - CBCentralManagerDelegate

    public func centralManagerDidUpdateState(_ c: CBCentralManager) {
        DispatchQueue.main.async {
            if c.state == .poweredOn {
                self.startScanning()
            } else {
                self.scanTimeoutTask?.cancel()
                self.connectTimeoutTask?.cancel()
                self.connectionStatus = String(localized: "Bluetooth Off")
                self.isConnected = false
                self.isScanning = false
            }
        }
    }

    public func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        // Ignore adapters with a weak signal — in a multi-vehicle environment a distant
        // adapter belonging to someone else would otherwise be grabbed first.
        guard rssi.intValue >= rssiConnectThreshold else { return }
        scanTimeoutTask?.cancel()
        c.stopScan()
        obdPeripheral = p
        p.delegate = self
        DispatchQueue.main.async {
            self.isScanning = false
            self.connectionStatus = String(localized: "Connecting...")
        }
        c.connect(p, options: nil)
        armConnectTimeout()
    }

    public func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        connectTimeoutTask?.cancel()
        DispatchQueue.main.async {
            self.scanTimedOut = false
            // Stay disconnected until characteristics are confirmed — avoid showing
            // "Connected" while the service/characteristic discovery is still in flight.
            self.connectionStatus = String(localized: "Setting up…")
        }
        p.discoverServices([serialServiceUUID])
    }

    public func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        let reason = error?.localizedDescription ?? "unknown"
        print("[connect failed] \(reason) — clearing saved UUID, falling back to scan")
        // Saved UUID is stale — clear it so the next attempt does a full scan.
        UserDefaults.standard.removeObject(forKey: preferredPeripheralUUIDKey)
        obdPeripheral = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.logMessage("Connect failed: \(reason)")
            self.startScanning()
        }
    }

    public func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        stopAutomaticPolling()
        if isBurstTesting {
            isBurstTesting = false; burstStopRequested = false
            burstTimeoutWorkItem?.cancel(); burstTimeoutWorkItem = nil
            burstDurationWorkItem?.cancel(); burstDurationWorkItem = nil
            print("  [burst] interrupted by disconnect")
        }
        if isPollingMetricsRunning {
            isPollingMetricsRunning = false
            pollingMetricsDurationWorkItem?.cancel(); pollingMetricsDurationWorkItem = nil
            print("  [cadence] interrupted by disconnect")
        }
        currentInitStep = 0
        waitingForResponse = false
        pendingResponsePrefix = nil
        responseTimeoutTask?.cancel()
        let reason = error?.localizedDescription ?? "clean disconnect"
        print("[disconnect] \(reason)")
        DispatchQueue.main.async {
            guard !self.isDemoModeActive else { return }
            self.connectionStatus = String(localized: "Disconnected")
            self.isConnected = false
            self.obdPeripheral = nil
            self.txCharacteristic = nil
            self.rxCharacteristic = nil
            self.resetTelemetry()
            self.logMessage("Disconnected: \(reason)")
            self.startScanning()
        }
    }

    // MARK: - CBPeripheralDelegate

    public func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        if let services = p.services {
            for s in services where s.uuid == serialServiceUUID {
                p.discoverCharacteristics([writeCharacteristicUUID, notifyCharacteristicUUID], for: s)
            }
        }
    }

    public func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        guard let characteristics = s.characteristics else { return }
        for ch in characteristics {
            if ch.properties.contains(.write) || ch.properties.contains(.writeWithoutResponse) {
                self.txCharacteristic = ch
            }
            if ch.properties.contains(.notify) || ch.properties.contains(.read) {
                self.rxCharacteristic = ch
                p.setNotifyValue(true, for: ch)
            }
        }
        if txCharacteristic != nil && rxCharacteristic != nil {
            UserDefaults.standard.set(p.identifier.uuidString, forKey: preferredPeripheralUUIDKey)
            DispatchQueue.main.async {
                self.connectionStatus = String(localized: "Connected")
                self.isConnected = true
            }
            currentInitStep = 0
            advanceHandshake()
        }
    }

    public func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard ch.uuid == rxCharacteristic?.uuid,
              let data = ch.value,
              let fragment = String(data: data, encoding: .utf8)
        else { return }

        incomingBuffer += fragment

        // In AT MA monitor mode the ELM327 streams \r-terminated lines with no > prompt.
        // Only switch to line-based parsing after the handshake is complete (step 11).
        if isMonitorModeActive && currentInitStep >= 11 {
            var parts = incomingBuffer.components(separatedBy: "\r")
            incomingBuffer = incomingBuffer.hasSuffix("\r") ? "" : (parts.removeLast())
            for part in parts {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                guard !trimmed.isEmpty else { continue }
                print("[monitor] \(trimmed)")
                logMessage("[monitor] \(trimmed)")
            }
            return
        }

        // The ELM327 always terminates a complete response with ">". Waiting for ">" instead
        // of any "\r" ensures we don't process partial multi-line responses prematurely.
        guard incomingBuffer.contains(">") else { return }

        let res = incomingBuffer.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        incomingBuffer = ""
        guard !res.isEmpty else { return }

        // Response received — clear the gate and cancel the safety timeout.
        waitingForResponse = false
        responseTimeoutTask?.cancel()

        if !isBurstTesting { logMessage("Received: \(res)") }

        // "STOPPED" means the adapter interrupted its CAN bus search because a new command
        // arrived before it finished. The adapter is now idle and ready for the next command.
        if res.contains("STOPPED") {
            waitingForResponse = false
            responseTimeoutTask?.cancel()
            pendingResponsePrefix = nil
            if currentInitStep < 8 { advanceHandshake() }
            else { pollingWatchdog?.cancel(); sendNextPollingCommand() }
            return
        }

        if currentInitStep < 8 && (res.contains("OK") || res.contains("ELM327")) {
            waitingForResponse = false
            responseTimeoutTask?.cancel()
            pendingResponsePrefix = nil
            advanceHandshake()
            return
        }

        // ELM327 adapter/bus error responses — advance the chain immediately
        // rather than stalling until the 2s watchdog fires.
        // During handshake (steps 7-10 are PID requests) NO DATA is especially
        // dangerous: the polling watchdog isn't running yet, so a stall is permanent.
        let isELMError = res.hasPrefix("?") ||
            res.contains("NO DATA") ||
            res.contains("UNABLE TO CONNECT") ||
            res.contains("CAN ERROR") ||
            res.contains("DATA ERROR") ||
            res.contains("BUFFER FULL") ||
            res.contains("FB ERROR") ||
            res.contains("BUS INIT")
        if isELMError {
            let trimmed = res.trimmingCharacters(in: .whitespacesAndNewlines)
            print("[elm error] step=\(currentInitStep) '\(trimmed)'")
            logMessage("[elm] \(trimmed)")
            pendingResponsePrefix = nil
            if currentInitStep < 11 {
                advanceHandshake()
            } else {
                pollingWatchdog?.cancel()
                sendNextPollingCommand()
            }
            return
        }

        let clean = res
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: ">", with: "")
        parseCANResponse(clean)

        // Only clear the response gate and advance the poll chain if this message answers
        // the command we sent. Autonomous messages match a known PID but pendingResponsePrefix
        // won't match — they get parsed above but must not disturb the pending request state.
        let isSolicited: Bool
        if let expected = pendingResponsePrefix {
            isSolicited = clean.contains(expected)
        } else {
            isSolicited = true  // AT commands or no pending prefix — treat as solicited
        }

        if isSolicited {
            waitingForResponse = false
            responseTimeoutTask?.cancel()
            pendingResponsePrefix = nil
            if !isBurstTesting {
                pollingWatchdog?.cancel()
                sendNextPollingCommand()
            }
        } else {
            logMessage("Autonomous: \(res)")
            print("[autonomous] \(res)")
        }
    }

    // MARK: - CAN Response Parsing

    private func parseCANResponse(_ clean: String) {
        let getVal = { (sub: String) -> Int? in
            guard let r = clean.range(of: sub),
                  clean.count >= r.upperBound.utf16Offset(in: clean) + 4
            else { return nil }
            let a = String(clean[r.upperBound..<clean.index(r.upperBound, offsetBy: 2)])
            let b = String(clean[clean.index(r.upperBound, offsetBy: 2)..<clean.index(r.upperBound, offsetBy: 4)])
            return (Int(b, radix: 16) ?? 0) * 256 + (Int(a, radix: 16) ?? 0)
        }

        if let v = getVal(mcuRunTimeResp) {
            self.rawRunTimeSeconds = v
            self.mcuRunTime = String(format: "%02d:%02d:%02d", v / 3600, (v % 3600) / 60, v % 60)
        }

        if let r = clean.range(of: mcuVersionResp),
           clean.distance(from: r.upperBound, to: clean.endIndex) >= 4 {
            let idx0 = r.upperBound
            let idx2 = clean.index(idx0, offsetBy: 2)
            let idx4 = clean.index(idx0, offsetBy: 4)
            if let b0 = Int(String(clean[idx0..<idx2]), radix: 16),
               let b1 = Int(String(clean[idx2..<idx4]), radix: 16) {
                let major = (b0 >> 4) & 0xF
                let minor = b0 & 0xF
                let patch = b1
                let tooOld = (major, minor, patch) < (MCUConstants.minimumFirmwareMajor, MCUConstants.minimumFirmwareMinor, MCUConstants.minimumFirmwarePatch)
                self.rawVersionData = (major: major, minor: minor, patch: patch)
                self.firmwareTooOld = tooOld
                self.mcuVersion = "V\(major).\(minor).\(patch)"
                if currentInitStep == 7 { advanceHandshake() }
            }
        }

        if let v = getVal(mcuPackVoltResp) {
            self.rawPackVoltage = Double(v) * 0.1
            self.mcuPackVoltage = String(format: "%.1f V", self.rawPackVoltage)
        }

        if let v = getVal(mcPackCurResp) {
            self.rawPackCurrent = Double(Int(Int16(bitPattern: UInt16(v)))) * 0.1
            self.mcuPackCurrent = String(format: "%.1f A", self.rawPackCurrent)
            if isBurstTesting {
                burstReplyCount += 1
                if burstReplyCount % 100 == 0 { printBurstProgress() }
                burstTimeoutWorkItem?.cancel()
                sendBurstCommand()
            }
        }

        if let r = clean.range(of: mcuSocResp),
           let soc = Int(clean[r.upperBound..<clean.index(r.upperBound, offsetBy: 2)], radix: 16) {
            self.rawSOCPercentage = min(soc, 100)
            self.mcuSOC = "\(self.rawSOCPercentage)%"
        }

        if let r = clean.range(of: self.mcuStatusResp),
           let status16 = Int(String(clean[r.upperBound..<clean.index(r.upperBound, offsetBy: 4)]), radix: 16) {
            self.alertGroundFault  = (status16 & MCUConstants.AlertMask.groundFault)  != 0 ? 1 : 0
            self.alertHardware     = (status16 & MCUConstants.AlertMask.hardware)     != 0 ? 1 : 0
            self.alertCCensus      = (status16 & MCUConstants.AlertMask.cCensus)      != 0 ? 1 : 0
            self.alertTCensus      = (status16 & MCUConstants.AlertMask.tCensus)      != 0 ? 1 : 0
            self.alertHVC          = (status16 & MCUConstants.AlertMask.hvc)          != 0 ? 1 : 0
            self.alertLVC          = (status16 & MCUConstants.AlertMask.lvc)          != 0 ? 1 : 0
            self.alertHiTemp       = (status16 & MCUConstants.AlertMask.hiTemp)       != 0 ? 1 : 0
            self.alertLoTemp       = (status16 & MCUConstants.AlertMask.loTemp)       != 0 ? 1 : 0
            self.alertNotLocked    = (status16 & MCUConstants.AlertMask.notLocked)    != 0 ? 1 : 0
            self.alertIllegalConf  = (status16 & MCUConstants.AlertMask.illegalConf)  != 0 ? 1 : 0
            self.hasReceivedStatus = true
        }

        for did in [mcuCellMinResp, mcuCellMaxResp, mcuCellAvgResp, mcuStdDevResp] {
            if let v = getVal(did) {
                let cellValue = Double(v) * 0.0001
                let strFormat = String(format: "%.4f V", cellValue)
                if      did == mcuCellMinResp { self.rawCellMin    = cellValue; self.cellMin    = strFormat }
                else if did == mcuCellMaxResp { self.rawCellMax    = cellValue; self.cellMax    = strFormat }
                else if did == mcuCellAvgResp { self.rawCellMean   = cellValue; self.cellMean   = strFormat }
                else if did == mcuStdDevResp  { self.rawCellStdDev = cellValue; self.cellStdDev = strFormat }
            }
        }

        for did in [mcuHvcResp, mcuLvcResp] {
            if let v = getVal(did) {
                let vcoValue = Double(v) * 0.0001
                if did == mcuHvcResp {
                    self.rawMcuHighVoltageCutoff = vcoValue
                    if self.currentInitStep == 8 { self.advanceHandshake() }
                } else if did == mcuLvcResp {
                    self.rawMcuLowVoltageCutoff = vcoValue
                    if self.currentInitStep == 9 { self.advanceHandshake() }
                }
            }
        }

        if let r = clean.range(of: mcuTempResp),
           clean.distance(from: r.upperBound, to: clean.endIndex) >= 4,
           let byteA = UInt8(String(clean[r.upperBound..<clean.index(r.upperBound, offsetBy: 2)]), radix: 16),
           let byteB = UInt8(String(clean[clean.index(r.upperBound, offsetBy: 2)..<clean.index(r.upperBound, offsetBy: 4)]), radix: 16) {
            self.rawMcuHighTemp = Double(Int8(bitPattern: byteA))
            self.rawMcuLowTemp  = Double(Int8(bitPattern: byteB))
        }

        if let v = getVal(mcuMaxKwhResp) {
            self.rawPackCapacityKwh = Double(v) * 0.1
            if self.currentInitStep == 10 { self.advanceHandshake() }
        }

        if let v = getVal(mcuCurKwhResp) {
            self.rawCurrentKwh = Double(v) * 0.1
        }
    }
}
