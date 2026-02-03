import Foundation

/// HELLO/HELLO_ACK payload (28 bytes)
/// Layout:
///   - software_version: u16 (2 bytes)
///   - min_protocol_version: u16 (2 bytes)
///   - max_protocol_version: u16 (2 bytes)
///   - reserved1: u16 (2 bytes)
///   - max_width: u32 (4 bytes)
///   - max_height: u32 (4 bytes)
///   - max_fps_fixed: u32 (4 bytes) - Fixed-point 16.16
///   - capabilities: u32 (4 bytes)
///   - reserved2: u32 (4 bytes)
struct HelloPayload: Sendable {
    let softwareVersion: UInt16
    let minProtocolVersion: UInt16
    let maxProtocolVersion: UInt16
    let reserved1: UInt16
    let maxWidth: UInt32
    let maxHeight: UInt32
    let maxFpsFixed: UInt32  // Fixed-point 16.16 format
    let capabilities: UInt32
    let reserved2: UInt32

    /// Create a new HELLO payload
    init(
        softwareVersion: UInt16,
        maxWidth: UInt32,
        maxHeight: UInt32,
        maxFps: UInt32,
        capabilities: UInt32
    ) {
        self.softwareVersion = softwareVersion
        self.minProtocolVersion = UInt16(SWRPConstants.protocolVersion)
        self.maxProtocolVersion = UInt16(SWRPConstants.protocolVersion)
        self.reserved1 = 0
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.maxFpsFixed = maxFps << 16  // Convert to fixed 16.16
        self.capabilities = capabilities
        self.reserved2 = 0
    }

    /// Create from all fields (used during parsing)
    private init(
        softwareVersion: UInt16,
        minProtocolVersion: UInt16,
        maxProtocolVersion: UInt16,
        reserved1: UInt16,
        maxWidth: UInt32,
        maxHeight: UInt32,
        maxFpsFixed: UInt32,
        capabilities: UInt32,
        reserved2: UInt32
    ) {
        self.softwareVersion = softwareVersion
        self.minProtocolVersion = minProtocolVersion
        self.maxProtocolVersion = maxProtocolVersion
        self.reserved1 = reserved1
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.maxFpsFixed = maxFpsFixed
        self.capabilities = capabilities
        self.reserved2 = reserved2
    }

    /// Get max FPS as integer (extracts whole part from fixed 16.16)
    var maxFps: UInt32 {
        maxFpsFixed >> 16
    }

    /// Check if HiDPI capability is set
    var supportsHidpi: Bool {
        capabilities & SWRPConstants.Capabilities.hidpi != 0
    }

    /// Check if audio capability is set
    var supportsAudio: Bool {
        capabilities & SWRPConstants.Capabilities.audio != 0
    }

    /// Serialize payload to bytes (28 bytes)
    func toBytes() -> Data {
        var data = Data.withCapacity(SWRPConstants.PayloadSize.hello)
        data.appendUInt16LE(softwareVersion)
        data.appendUInt16LE(minProtocolVersion)
        data.appendUInt16LE(maxProtocolVersion)
        data.appendUInt16LE(reserved1)
        data.appendUInt32LE(maxWidth)
        data.appendUInt32LE(maxHeight)
        data.appendUInt32LE(maxFpsFixed)
        data.appendUInt32LE(capabilities)
        data.appendUInt32LE(reserved2)
        return data
    }

    /// Parse payload from bytes
    static func parse(_ data: Data) throws -> HelloPayload {
        guard data.count >= SWRPConstants.PayloadSize.hello else {
            throw SerialWarpError.invalidPayloadLength(
                expected: SWRPConstants.PayloadSize.hello,
                actual: data.count
            )
        }

        guard let softwareVersion = data.readUInt16LE(at: 0),
              let minProtocolVersion = data.readUInt16LE(at: 2),
              let maxProtocolVersion = data.readUInt16LE(at: 4),
              let reserved1 = data.readUInt16LE(at: 6),
              let maxWidth = data.readUInt32LE(at: 8),
              let maxHeight = data.readUInt32LE(at: 12),
              let maxFpsFixed = data.readUInt32LE(at: 16),
              let capabilities = data.readUInt32LE(at: 20),
              let reserved2 = data.readUInt32LE(at: 24) else {
            throw SerialWarpError.parseError("Failed to parse HelloPayload fields")
        }

        return HelloPayload(
            softwareVersion: softwareVersion,
            minProtocolVersion: minProtocolVersion,
            maxProtocolVersion: maxProtocolVersion,
            reserved1: reserved1,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            maxFpsFixed: maxFpsFixed,
            capabilities: capabilities,
            reserved2: reserved2
        )
    }
}
