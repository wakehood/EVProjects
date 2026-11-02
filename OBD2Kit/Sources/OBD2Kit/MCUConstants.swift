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
    public static let minimumFirmwarePatch: Int = 6

    public static var minimumFirmwareString: String {
        "V\(minimumFirmwareMajor).\(minimumFirmwareMinor).\(minimumFirmwarePatch)"
    }
}
