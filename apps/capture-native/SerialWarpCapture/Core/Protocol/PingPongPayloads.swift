import Foundation

/// PING payload (8 bytes)
/// Layout:
///   - timestamp_us: u64 (8 bytes) - Timestamp in microseconds
struct PingPayload: Sendable {
    let timestampUs: UInt64

    /// Create a new PING payload with the current timestamp
    init() {
        self.timestampUs = UInt64(Date().timeIntervalSince1970 * 1_000_000)
    }

    /// Create a new PING payload with a specific timestamp
    init(timestampUs: UInt64) {
        self.timestampUs = timestampUs
    }

    /// Serialize payload to bytes (8 bytes)
    func toBytes() -> Data {
        var data = Data.withCapacity(SWRPConstants.PayloadSize.ping)
        data.appendUInt64LE(timestampUs)
        return data
    }

    /// Parse payload from bytes
    static func parse(_ data: Data) throws -> PingPayload {
        guard data.count >= SWRPConstants.PayloadSize.ping else {
            throw SerialWarpError.invalidPayloadLength(
                expected: SWRPConstants.PayloadSize.ping,
                actual: data.count
            )
        }

        guard let timestampUs = data.readUInt64LE(at: 0) else {
            throw SerialWarpError.parseError("Failed to parse PingPayload timestamp")
        }

        return PingPayload(timestampUs: timestampUs)
    }
}

/// PONG payload (16 bytes)
/// Layout:
///   - ping_timestamp_us: u64 (8 bytes) - Original ping timestamp
///   - pong_timestamp_us: u64 (8 bytes) - Pong timestamp
struct PongPayload: Sendable {
    let pingTimestampUs: UInt64
    let pongTimestampUs: UInt64

    /// Create a new PONG payload
    init(pingTimestampUs: UInt64, pongTimestampUs: UInt64) {
        self.pingTimestampUs = pingTimestampUs
        self.pongTimestampUs = pongTimestampUs
    }

    /// Create a PONG in response to a PING
    init(respondingTo ping: PingPayload) {
        self.pingTimestampUs = ping.timestampUs
        self.pongTimestampUs = UInt64(Date().timeIntervalSince1970 * 1_000_000)
    }

    /// Calculate round-trip time in microseconds
    var roundTripUs: UInt64 {
        pongTimestampUs - pingTimestampUs
    }

    /// Serialize payload to bytes (16 bytes)
    func toBytes() -> Data {
        var data = Data.withCapacity(SWRPConstants.PayloadSize.pong)
        data.appendUInt64LE(pingTimestampUs)
        data.appendUInt64LE(pongTimestampUs)
        return data
    }

    /// Parse payload from bytes
    static func parse(_ data: Data) throws -> PongPayload {
        guard data.count >= SWRPConstants.PayloadSize.pong else {
            throw SerialWarpError.invalidPayloadLength(
                expected: SWRPConstants.PayloadSize.pong,
                actual: data.count
            )
        }

        guard let pingTimestampUs = data.readUInt64LE(at: 0),
              let pongTimestampUs = data.readUInt64LE(at: 8) else {
            throw SerialWarpError.parseError("Failed to parse PongPayload timestamps")
        }

        return PongPayload(pingTimestampUs: pingTimestampUs, pongTimestampUs: pongTimestampUs)
    }
}
