import Foundation

/// Reassembles frame segments into complete frames
final class FrameReassembler: @unchecked Sendable {

    /// Pending frame being reassembled
    private var pending: PendingFrame?

    /// Lock for thread safety
    private let lock = NSLock()

    /// Create a new frame reassembler
    init() {}

    /// Add a segment. Returns the complete frame if all segments have been received.
    /// - Parameters:
    ///   - header: Frame header from the segment
    ///   - data: Segment data
    /// - Returns: Complete EncodedFrame if all segments received, nil otherwise
    func addSegment(header: FrameHeader, data: Data) -> EncodedFrame? {
        lock.lock()
        defer { lock.unlock() }

        // Check if this is a new frame
        if pending == nil || pending!.frameNumber != header.frameNumber {
            // Start new frame reassembly
            var receivedSegments = [Data?](repeating: nil, count: Int(header.segmentCount))
            receivedSegments[Int(header.segmentIndex)] = data

            pending = PendingFrame(
                frameNumber: header.frameNumber,
                ptsUs: header.ptsUs,
                captureTsUs: header.captureTsUs,
                frameSize: header.frameSize,
                segmentCount: header.segmentCount,
                receivedSegments: receivedSegments,
                receivedCount: 1
            )

            // Single-segment frame
            if header.segmentCount == 1 {
                return completeFrame()
            }
            return nil
        }

        // Add to existing frame
        guard var currentPending = pending else { return nil }

        // Check for duplicate segment
        if currentPending.receivedSegments[Int(header.segmentIndex)] != nil {
            return nil
        }

        currentPending.receivedSegments[Int(header.segmentIndex)] = data
        currentPending.receivedCount += 1
        pending = currentPending

        // Check if complete
        if currentPending.receivedCount == currentPending.segmentCount {
            return completeFrame()
        }

        return nil
    }

    /// Complete the pending frame
    private func completeFrame() -> EncodedFrame? {
        guard let currentPending = pending else { return nil }
        pending = nil

        // Concatenate all segment data
        var frameData = Data()
        frameData.reserveCapacity(Int(currentPending.frameSize))

        for segmentData in currentPending.receivedSegments {
            if let data = segmentData {
                frameData.append(data)
            }
        }

        return EncodedFrame(
            metadata: FrameMetadata(
                frameNumber: currentPending.frameNumber,
                ptsUs: currentPending.ptsUs,
                captureTsUs: currentPending.captureTsUs,
                isKeyframe: false  // We don't track keyframe status during reassembly
            ),
            data: frameData
        )
    }

    /// Clear any pending incomplete frame
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        pending = nil
    }
}

/// Internal state for frame being reassembled
private struct PendingFrame {
    let frameNumber: UInt64
    let ptsUs: UInt64
    let captureTsUs: UInt64
    let frameSize: UInt32
    let segmentCount: UInt16
    var receivedSegments: [Data?]
    var receivedCount: UInt16
}
