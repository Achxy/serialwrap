import Foundation

/// START payload (24 bytes)
/// Layout:
///   - width: u32 (4 bytes)
///   - height: u32 (4 bytes)
///   - fps_fixed: u32 (4 bytes) - Fixed-point 16.16
///   - bitrate_bps: u32 (4 bytes)
///   - pixel_format: u8 (1 byte)
///   - audio_enabled: u8 (1 byte)
///   - audio_sample_rate: u16 (2 bytes)
///   - audio_channels: u8 (1 byte)
///   - audio_bits: u8 (1 byte)
///   - reserved: u16 (2 bytes)
struct StartPayload: Sendable {
    let width: UInt32
    let height: UInt32
    let fpsFixed: UInt32  // Fixed-point 16.16 format
    let bitrateBps: UInt32
    let pixelFormat: UInt8
    let audioEnabled: UInt8
    let audioSampleRate: UInt16
    let audioChannels: UInt8
    let audioBits: UInt8
    let reserved: UInt16

    /// Create a new START payload
    init(width: UInt32, height: UInt32, fps: UInt32, bitrateBps: UInt32) {
        self.width = width
        self.height = height
        self.fpsFixed = fps << 16  // Convert to fixed 16.16
        self.bitrateBps = bitrateBps
        self.pixelFormat = 0  // NV12
        self.audioEnabled = 0
        self.audioSampleRate = 0
        self.audioChannels = 0
        self.audioBits = 0
        self.reserved = 0
    }

    /// Create from all fields (used during parsing)
    private init(
        width: UInt32,
        height: UInt32,
        fpsFixed: UInt32,
        bitrateBps: UInt32,
        pixelFormat: UInt8,
        audioEnabled: UInt8,
        audioSampleRate: UInt16,
        audioChannels: UInt8,
        audioBits: UInt8,
        reserved: UInt16
    ) {
        self.width = width
        self.height = height
        self.fpsFixed = fpsFixed
        self.bitrateBps = bitrateBps
        self.pixelFormat = pixelFormat
        self.audioEnabled = audioEnabled
        self.audioSampleRate = audioSampleRate
        self.audioChannels = audioChannels
        self.audioBits = audioBits
        self.reserved = reserved
    }

    /// Get FPS as integer (extracts whole part from fixed 16.16)
    var fps: UInt32 {
        fpsFixed >> 16
    }

    /// Serialize payload to bytes (24 bytes)
    func toBytes() -> Data {
        var data = Data.withCapacity(SWRPConstants.PayloadSize.start)
        data.appendUInt32LE(width)
        data.appendUInt32LE(height)
        data.appendUInt32LE(fpsFixed)
        data.appendUInt32LE(bitrateBps)
        data.appendUInt8(pixelFormat)
        data.appendUInt8(audioEnabled)
        data.appendUInt16LE(audioSampleRate)
        data.appendUInt8(audioChannels)
        data.appendUInt8(audioBits)
        data.appendUInt16LE(reserved)
        return data
    }

    /// Parse payload from bytes
    static func parse(_ data: Data) throws -> StartPayload {
        guard data.count >= SWRPConstants.PayloadSize.start else {
            throw SerialWarpError.invalidPayloadLength(
                expected: SWRPConstants.PayloadSize.start,
                actual: data.count
            )
        }

        guard let width = data.readUInt32LE(at: 0),
              let height = data.readUInt32LE(at: 4),
              let fpsFixed = data.readUInt32LE(at: 8),
              let bitrateBps = data.readUInt32LE(at: 12),
              let pixelFormat = data.readUInt8(at: 16),
              let audioEnabled = data.readUInt8(at: 17),
              let audioSampleRate = data.readUInt16LE(at: 18),
              let audioChannels = data.readUInt8(at: 20),
              let audioBits = data.readUInt8(at: 21),
              let reserved = data.readUInt16LE(at: 22) else {
            throw SerialWarpError.parseError("Failed to parse StartPayload fields")
        }

        // Validate dimensions
        guard width > 0 && height > 0 else {
            throw SerialWarpError.invalidPayloadLength(expected: 1, actual: 0)
        }

        return StartPayload(
            width: width,
            height: height,
            fpsFixed: fpsFixed,
            bitrateBps: bitrateBps,
            pixelFormat: pixelFormat,
            audioEnabled: audioEnabled,
            audioSampleRate: audioSampleRate,
            audioChannels: audioChannels,
            audioBits: audioBits,
            reserved: reserved
        )
    }
}

/// START_ACK payload (4 bytes)
/// Layout:
///   - status: u8 (1 byte)
///   - reserved: u8 (1 byte)
///   - initial_credits: u16 (2 bytes)
struct StartAckPayload: Sendable {
    let status: UInt8
    let reserved: UInt8
    let initialCredits: UInt16

    /// Create a new START_ACK payload
    init(status: UInt8, initialCredits: UInt16) {
        self.status = status
        self.reserved = 0
        self.initialCredits = initialCredits
    }

    /// Create a successful START_ACK
    static func ok(initialCredits: UInt16 = SWRPConstants.defaultInitialCredits) -> StartAckPayload {
        StartAckPayload(status: 0, initialCredits: initialCredits)
    }

    /// Check if the status indicates success
    var isOk: Bool {
        status == 0
    }

    /// Serialize payload to bytes (4 bytes)
    func toBytes() -> Data {
        var data = Data.withCapacity(SWRPConstants.PayloadSize.startAck)
        data.appendUInt8(status)
        data.appendUInt8(reserved)
        data.appendUInt16LE(initialCredits)
        return data
    }

    /// Parse payload from bytes
    static func parse(_ data: Data) throws -> StartAckPayload {
        guard data.count >= SWRPConstants.PayloadSize.startAck else {
            throw SerialWarpError.invalidPayloadLength(
                expected: SWRPConstants.PayloadSize.startAck,
                actual: data.count
            )
        }

        guard let status = data.readUInt8(at: 0),
              let reserved = data.readUInt8(at: 1),
              let initialCredits = data.readUInt16LE(at: 2) else {
            throw SerialWarpError.parseError("Failed to parse StartAckPayload fields")
        }

        return StartAckPayload(status: status, initialCredits: initialCredits)
    }
}
