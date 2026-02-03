import XCTest
@testable import SerialWarpCapture

final class FrameSegmenterTests: XCTestCase {

    // MARK: - Single Segment Tests

    func testSingleSegmentSmallFrame() {
        let metadata = FrameMetadata(frameNumber: 1, ptsUs: 1000, captureTsUs: 1000, isKeyframe: true)
        let data = Data(repeating: 0xAB, count: 1024)  // 1KB - fits in single segment
        let frame = EncodedFrame(metadata: metadata, data: data)

        let segments = frame.intoSegments()

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].segmentIndex, 0)
        XCTAssertEqual(segments[0].segmentCount, 1)
        XCTAssertEqual(segments[0].frameSize, 1024)
        XCTAssertEqual(segments[0].data, data)
    }

    func testSingleSegmentMaxSize() {
        let metadata = FrameMetadata(frameNumber: 1, ptsUs: 1000, captureTsUs: 1000, isKeyframe: false)
        let data = Data(repeating: 0xCD, count: SWRPConstants.maxSegmentSize)  // Exactly 64KB
        let frame = EncodedFrame(metadata: metadata, data: data)

        let segments = frame.intoSegments()

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].data.count, SWRPConstants.maxSegmentSize)
    }

    // MARK: - Multiple Segment Tests

    func testMultipleSegments() {
        let metadata = FrameMetadata(frameNumber: 42, ptsUs: 1_000_000, captureTsUs: 1_000_100, isKeyframe: true)
        let data = Data(repeating: 0xEF, count: 200_000)  // 200KB - should be 4 segments
        let frame = EncodedFrame(metadata: metadata, data: data)

        let segments = frame.intoSegments()

        // 200KB / 64KB = 3.125, so 4 segments
        XCTAssertEqual(segments.count, 4)

        // Verify segment metadata
        for (i, segment) in segments.enumerated() {
            XCTAssertEqual(segment.metadata.frameNumber, 42)
            XCTAssertEqual(segment.segmentIndex, UInt16(i))
            XCTAssertEqual(segment.segmentCount, 4)
            XCTAssertEqual(segment.frameSize, 200_000)
        }

        // Verify first 3 segments are full size
        for i in 0..<3 {
            XCTAssertEqual(segments[i].data.count, SWRPConstants.maxSegmentSize)
        }

        // Last segment has remainder
        let lastSegmentSize = 200_000 - (3 * SWRPConstants.maxSegmentSize)
        XCTAssertEqual(segments[3].data.count, lastSegmentSize)

        // Verify all data is preserved
        var reassembled = Data()
        for segment in segments {
            reassembled.append(segment.data)
        }
        XCTAssertEqual(reassembled, data)
    }

    func testExactMultipleOfSegmentSize() {
        let metadata = FrameMetadata(frameNumber: 1, ptsUs: 1000, captureTsUs: 1000, isKeyframe: false)
        let data = Data(repeating: 0x12, count: SWRPConstants.maxSegmentSize * 2)  // Exactly 128KB
        let frame = EncodedFrame(metadata: metadata, data: data)

        let segments = frame.intoSegments()

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].data.count, SWRPConstants.maxSegmentSize)
        XCTAssertEqual(segments[1].data.count, SWRPConstants.maxSegmentSize)
    }

    // MARK: - Payload Generation Tests

    func testSegmentToPayload() {
        let metadata = FrameMetadata(frameNumber: 1, ptsUs: 1000, captureTsUs: 2000, isKeyframe: true)
        let data = Data([0x01, 0x02, 0x03, 0x04])
        let frame = EncodedFrame(metadata: metadata, data: data)

        let segments = frame.intoSegments()
        let payload = segments[0].toPayload()

        // Payload should be frame header + data
        XCTAssertEqual(payload.count, SWRPConstants.PayloadSize.frameHeader + data.count)

        // Verify frame header fields
        XCTAssertEqual(payload.readUInt64LE(at: 0), 1)  // frame_number
        XCTAssertEqual(payload.readUInt64LE(at: 8), 1000)  // pts_us
        XCTAssertEqual(payload.readUInt64LE(at: 16), 2000)  // capture_ts_us
        XCTAssertEqual(payload.readUInt32LE(at: 24), 4)  // frame_size
        XCTAssertEqual(payload.readUInt16LE(at: 28), 0)  // segment_index
        XCTAssertEqual(payload.readUInt16LE(at: 30), 1)  // segment_count

        // Verify data follows header
        let dataStart = SWRPConstants.PayloadSize.frameHeader
        XCTAssertEqual(payload.subdata(in: dataStart..<payload.count), data)
    }

    // MARK: - Frame Reassembly Tests

    func testReassemblySingleSegment() {
        let reassembler = FrameReassembler()

        let header = FrameHeader(
            frameNumber: 1,
            ptsUs: 1000,
            captureTsUs: 2000,
            frameSize: 100,
            segmentIndex: 0,
            segmentCount: 1
        )
        let data = Data(repeating: 0xAB, count: 100)

        let result = reassembler.addSegment(header: header, data: data)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.metadata.frameNumber, 1)
        XCTAssertEqual(result?.data, data)
    }

    func testReassemblyMultipleSegments() {
        let reassembler = FrameReassembler()

        let frameData = Data(repeating: 0xCD, count: 300)

        // Simulate 3 segments
        let header1 = FrameHeader(
            frameNumber: 42,
            ptsUs: 1000,
            captureTsUs: 2000,
            frameSize: 300,
            segmentIndex: 0,
            segmentCount: 3
        )
        let header2 = FrameHeader(
            frameNumber: 42,
            ptsUs: 1000,
            captureTsUs: 2000,
            frameSize: 300,
            segmentIndex: 1,
            segmentCount: 3
        )
        let header3 = FrameHeader(
            frameNumber: 42,
            ptsUs: 1000,
            captureTsUs: 2000,
            frameSize: 300,
            segmentIndex: 2,
            segmentCount: 3
        )

        // Add segments
        var result = reassembler.addSegment(header: header1, data: frameData.subdata(in: 0..<100))
        XCTAssertNil(result)

        result = reassembler.addSegment(header: header2, data: frameData.subdata(in: 100..<200))
        XCTAssertNil(result)

        result = reassembler.addSegment(header: header3, data: frameData.subdata(in: 200..<300))
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.metadata.frameNumber, 42)
        XCTAssertEqual(result?.data, frameData)
    }

    func testReassemblyOutOfOrder() {
        let reassembler = FrameReassembler()

        let frameData = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06])

        let header0 = FrameHeader(frameNumber: 1, ptsUs: 1000, captureTsUs: 2000, frameSize: 6, segmentIndex: 0, segmentCount: 3)
        let header1 = FrameHeader(frameNumber: 1, ptsUs: 1000, captureTsUs: 2000, frameSize: 6, segmentIndex: 1, segmentCount: 3)
        let header2 = FrameHeader(frameNumber: 1, ptsUs: 1000, captureTsUs: 2000, frameSize: 6, segmentIndex: 2, segmentCount: 3)

        // Add in reverse order
        var result = reassembler.addSegment(header: header2, data: frameData.subdata(in: 4..<6))
        XCTAssertNil(result)

        result = reassembler.addSegment(header: header0, data: frameData.subdata(in: 0..<2))
        XCTAssertNil(result)

        result = reassembler.addSegment(header: header1, data: frameData.subdata(in: 2..<4))
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.data, frameData)
    }

    func testReassemblyDuplicateSegment() {
        let reassembler = FrameReassembler()

        let header = FrameHeader(frameNumber: 1, ptsUs: 1000, captureTsUs: 2000, frameSize: 4, segmentIndex: 0, segmentCount: 2)
        let data = Data([0x01, 0x02])

        var result = reassembler.addSegment(header: header, data: data)
        XCTAssertNil(result)

        // Add duplicate
        result = reassembler.addSegment(header: header, data: data)
        XCTAssertNil(result)  // Should ignore duplicate
    }

    func testReassemblyReset() {
        let reassembler = FrameReassembler()

        let header = FrameHeader(frameNumber: 1, ptsUs: 1000, captureTsUs: 2000, frameSize: 100, segmentIndex: 0, segmentCount: 2)
        let data = Data(repeating: 0x00, count: 50)

        _ = reassembler.addSegment(header: header, data: data)
        reassembler.reset()

        // After reset, a new frame should work
        let newHeader = FrameHeader(frameNumber: 2, ptsUs: 2000, captureTsUs: 3000, frameSize: 10, segmentIndex: 0, segmentCount: 1)
        let newData = Data(repeating: 0xFF, count: 10)

        let result = reassembler.addSegment(header: newHeader, data: newData)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.metadata.frameNumber, 2)
    }
}
