//
//  MCUConstants.swift
//  OBD2Kit
//
//  Update minimumFirmware here when the MCU firmware requirement advances.
//  Note: the firmware suffix letter (e.g. 'e' in V1.3.6e) is NOT transmitted
//  over the CAN/OBD2 interface, so only major, minor, and patch are compared.
//

public enum MCUConstants {
    public static let minimumFirmwareMajor: Int = 1
    public static let minimumFirmwareMinor: Int = 3
    public static let minimumFirmwarePatch: Int = 7

    public static var minimumFirmwareString: String {
        "V\(minimumFirmwareMajor).\(minimumFirmwareMinor).\(minimumFirmwarePatch)"
    }

    // 16-bit BMS fault word masks — match firmware BMS_FAULT_* defines exactly.
    // To add a new alert: add the mask here and a corresponding property in ODB2ConnectionManager.
    public enum AlertMask {
        public static let groundFault:  Int = 0x8000  // Ground Fault Monitor
        public static let hardware:     Int = 0x4000  // LTC hardware fault
        public static let cCensus:      Int = 0x2000  // Cell Census fault
        public static let tCensus:      Int = 0x1000  // Thermistor Census fault
        public static let hvc:          Int = 0x0800  // at least one cell v is >HVC
        public static let lvc:          Int = 0x0400  // at least one cell v is <LVC
        public static let hiTemp:       Int = 0x0200  // thermistor overtemp
        public static let loTemp:       Int = 0x0100  // thermistor undertemp
        public static let notLocked:    Int = 0x0080  // configuration not locked
        public static let illegalConf:  Int = 0x0040  // illegal device for architecture
    }
}
