import Foundation

/// An encoded video frame ready for transmission
struct EncodedFrame: Sendable {
    /// Frame metadata (timing, keyframe status, etc.)
    let metadata: FrameMetadata

    /// Encoded frame data (H.264 Annex B format)
    let data: Data

    /// Create a new encoded frame
    init(metadata: FrameMetadata, data: Data) {
        self.metadata = metadata
        self.data = data
    }

    /// Total size of the encoded data
    var size: Int {
        data.count
    }

    /// Split frame into segments for transmission
    /// Each segment is at most MAX_SEGMENT_SIZE bytes
    func intoSegments() -> [FrameSegment] {
        let totalSize = data.count
        var segmentCount = (totalSize + SWRPConstants.maxSegmentSize - 1) / SWRPConstants.maxSegmentSize
        segmentCount = max(segmentCount, 1)

        // Validate segment count fits in UInt16
        precondition(
            segmentCount <= Int(UInt16.max),
            "Frame too large: requires \(segmentCount) segments (max \(UInt16.max))"
        )

        // Single segment case
        if segmentCount == 1 {
            return [FrameSegment(
                metadata: metadata,
                frameSize: UInt32(totalSize),
                segmentIndex: 0,
                segmentCount: 1,
                data: data
            )]
        }

        // Multiple segments
        var segments: [FrameSegment] = []
        segments.reserveCapacity(segmentCount)

        var offset = 0
        for i in 0..<segmentCount {
            let segmentEnd = min(offset + SWRPConstants.maxSegmentSize, totalSize)
            let segmentData = data.subdata(in: offset..<segmentEnd)

            segments.append(FrameSegment(
                metadata: metadata,
                frameSize: UInt32(totalSize),
                segmentIndex: UInt16(i),
                segmentCount: UInt16(segmentCount),
                data: segmentData
            ))

            offset = segmentEnd
        }

        return segments
    }
}

/// A segment of an encoded frame for transmission
struct FrameSegment: Sendable {
    /// Frame metadata
    let metadata: FrameMetadata

    /// Total frame size (sum of all segments)
    let frameSize: UInt32

    /// Index of this segment (0-based)
    let segmentIndex: UInt16

    /// Total number of segments
    let segmentCount: UInt16

    /// Segment data
    let data: Data

    /// Create the FRAME packet payload (frame header + segment data)
    func toPayload() -> Data {
        let header = FrameHeader(
            frameNumber: metadata.frameNumber,
            ptsUs: metadata.ptsUs,
            captureTsUs: metadata.captureTsUs,
            frameSize: frameSize,
            segmentIndex: segmentIndex,
            segmentCount: segmentCount
        )

        var payload = header.toBytes()
        payload.appendData(data)
        return payload
    }
}
