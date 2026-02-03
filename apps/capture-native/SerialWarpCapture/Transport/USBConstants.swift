import Foundation

/// USB constants for SerialWarp transport
enum USBConstants {
    /// Supported USB devices (VID, PID, name)
    static let supportedDevices: [(vendorId: UInt16, productId: UInt16, name: String)] = [
        (0x067B, 0x27A1, "Prolific PL27A1"),
        (0x05E3, 0x0751, "Genesys GL3523"),
        (0x2109, 0x0822, "VIA VL822"),
    ]

    /// USB OUT endpoint address (host to device)
    static let endpointOut: UInt8 = 0x01

    /// USB IN endpoint address (device to host)
    static let endpointIn: UInt8 = 0x81

    /// USB transfer buffer size
    static let bufferSize: Int = 65536

    /// USB transfer timeout in milliseconds
    static let timeoutMs: UInt32 = 5000

    /// Maximum number of pending async transfers
    static let maxPendingTransfers: Int = 4

    /// Check if a device with the given VID/PID is supported
    static func isSupported(vendorId: UInt16, productId: UInt16) -> Bool {
        supportedDevices.contains { $0.vendorId == vendorId && $0.productId == productId }
    }

    /// Find device info for a VID/PID pair
    static func findDevice(vendorId: UInt16, productId: UInt16) -> (vendorId: UInt16, productId: UInt16, name: String)? {
        supportedDevices.first { $0.vendorId == vendorId && $0.productId == productId }
    }
}

/// USB device information
struct USBDeviceInfo: Identifiable, Sendable {
    let id: String
    let name: String
    let vendorId: UInt16
    let productId: UInt16

    init(vendorId: UInt16, productId: UInt16, name: String) {
        self.id = String(format: "%04X:%04X", vendorId, productId)
        self.name = name
        self.vendorId = vendorId
        self.productId = productId
    }
}
