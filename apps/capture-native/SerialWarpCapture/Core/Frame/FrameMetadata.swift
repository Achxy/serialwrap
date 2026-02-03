import Foundation

/// Metadata for a captured/encoded frame
struct FrameMetadata: Sendable {
    /// Frame sequence number
    let frameNumber: UInt64

    /// Presentation timestamp in microseconds
    let ptsUs: UInt64

    /// Capture timestamp in microseconds (when the frame was captured)
    let captureTsUs: UInt64

    /// Whether this frame is a keyframe (I-frame)
    let isKeyframe: Bool

    /// Create frame metadata
    init(frameNumber: UInt64, ptsUs: UInt64, captureTsUs: UInt64, isKeyframe: Bool) {
        self.frameNumber = frameNumber
        self.ptsUs = ptsUs
        self.captureTsUs = captureTsUs
        self.isKeyframe = isKeyframe
    }

    /// Create metadata with the current time as capture timestamp
    static func now(frameNumber: UInt64, isKeyframe: Bool) -> FrameMetadata {
        let now = UInt64(Date().timeIntervalSince1970 * 1_000_000)
        return FrameMetadata(
            frameNumber: frameNumber,
            ptsUs: now,
            captureTsUs: now,
            isKeyframe: isKeyframe
        )
    }
}
