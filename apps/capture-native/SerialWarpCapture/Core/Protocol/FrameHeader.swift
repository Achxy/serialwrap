import Foundation

/// FRAME header (32 bytes, precedes encoded data in FRAME packet payload)
/// Layout:
///   - frame_number: u64 (8 bytes)
///   - pts_us: u64 (8 bytes) - Presentation timestamp in microseconds
///   - capture_ts_us: u64 (8 bytes) - Capture timestamp in microseconds
///   - frame_size: u32 (4 bytes) - Total frame size (all segments)
///   - segment_index: u16 (2 bytes) - Index of this segment (0-based)
///   - segment_count: u16 (2 bytes) - Total number of segments
struct FrameHeader: Sendable {
    let frameNumber: UInt64
    let ptsUs: UInt64
    let captureTsUs: UInt64
    let frameSize: UInt32
    let segmentIndex: UInt16
    let segmentCount: UInt16

    /// Create a new frame header
    init(
        frameNumber: UInt64,
        ptsUs: UInt64,
        captureTsUs: UInt64,
        frameSize: UInt32,
        segmentIndex: UInt16,
        segmentCount: UInt16
    ) {
        self.frameNumber = frameNumber
        self.ptsUs = ptsUs
        self.captureTsUs = captureTsUs
        self.frameSize = frameSize
        self.segmentIndex = segmentIndex
        self.segmentCount = segmentCount
    }

    /// Serialize header to bytes (32 bytes)
    func toBytes() -> Data {
        var data = Data.withCapacity(SWRPConstants.PayloadSize.frameHeader)
        data.appendUInt64LE(frameNumber)
        data.appendUInt64LE(ptsUs)
        data.appendUInt64LE(captureTsUs)
        data.appendUInt32LE(frameSize)
        data.appendUInt16LE(segmentIndex)
        data.appendUInt16LE(segmentCount)
        return data
    }

    /// Parse header from bytes
    static func parse(_ data: Data) throws -> FrameHeader {
        guard data.count >= SWRPConstants.PayloadSize.frameHeader else {
            throw SerialWarpError.invalidPayloadLength(
                expected: SWRPConstants.PayloadSize.frameHeader,
                actual: data.count
            )
        }

        guard let frameNumber = data.readUInt64LE(at: 0),
              let ptsUs = data.readUInt64LE(at: 8),
              let captureTsUs = data.readUInt64LE(at: 16),
              let frameSize = data.readUInt32LE(at: 24),
              let segmentIndex = data.readUInt16LE(at: 28),
              let segmentCount = data.readUInt16LE(at: 30) else {
            throw SerialWarpError.parseError("Failed to parse FrameHeader fields")
        }

        // Validate segment_count
        guard segmentCount > 0 else {
            throw SerialWarpError.frameReassemblyError("segment_count cannot be zero")
        }

        // Validate segment_index < segment_count
        guard segmentIndex < segmentCount else {
            throw SerialWarpError.frameReassemblyError(
                "segment_index (\(segmentIndex)) must be less than segment_count (\(segmentCount))"
            )
        }

        return FrameHeader(
            frameNumber: frameNumber,
            ptsUs: ptsUs,
            captureTsUs: captureTsUs,
            frameSize: frameSize,
            segmentIndex: segmentIndex,
            segmentCount: segmentCount
        )
    }
}

/// FRAME_ACK payload (16 bytes)
/// Layout:
///   - frame_number: u64 (8 bytes)
///   - decode_time_us: u32 (4 bytes)
///   - credits_returned: u16 (2 bytes)
///   - reserved: u16 (2 bytes)
struct FrameAckPayload: Sendable {
    let frameNumber: UInt64
    let decodeTimeUs: UInt32
    let creditsReturned: UInt16
    let reserved: UInt16

    /// Create a new FRAME_ACK payload
    init(frameNumber: UInt64, decodeTimeUs: UInt32, creditsReturned: UInt16) {
        self.frameNumber = frameNumber
        self.decodeTimeUs = decodeTimeUs
        self.creditsReturned = creditsReturned
        self.reserved = 0
    }

    /// Serialize payload to bytes (16 bytes)
    func toBytes() -> Data {
        var data = Data.withCapacity(SWRPConstants.PayloadSize.frameAck)
        data.appendUInt64LE(frameNumber)
        data.appendUInt32LE(decodeTimeUs)
        data.appendUInt16LE(creditsReturned)
        data.appendUInt16LE(reserved)
        return data
    }

    /// Parse payload from bytes
    static func parse(_ data: Data) throws -> FrameAckPayload {
        guard data.count >= SWRPConstants.PayloadSize.frameAck else {
            throw SerialWarpError.invalidPayloadLength(
                expected: SWRPConstants.PayloadSize.frameAck,
                actual: data.count
            )
        }

        guard let frameNumber = data.readUInt64LE(at: 0),
              let decodeTimeUs = data.readUInt32LE(at: 8),
              let creditsReturned = data.readUInt16LE(at: 12),
              let reserved = data.readUInt16LE(at: 14) else {
            throw SerialWarpError.parseError("Failed to parse FrameAckPayload fields")
        }

        return FrameAckPayload(
            frameNumber: frameNumber,
            decodeTimeUs: decodeTimeUs,
            creditsReturned: creditsReturned
        )
    }
}
