import XCTest
@testable import SerialWarpCapture

final class ProtocolTests: XCTestCase {

    // MARK: - Packet Type Tests

    func testPacketTypeRawValues() {
        XCTAssertEqual(PacketType.hello.rawValue, 0x01)
        XCTAssertEqual(PacketType.helloAck.rawValue, 0x02)
        XCTAssertEqual(PacketType.start.rawValue, 0x03)
        XCTAssertEqual(PacketType.startAck.rawValue, 0x04)
        XCTAssertEqual(PacketType.frame.rawValue, 0x10)
        XCTAssertEqual(PacketType.frameAck.rawValue, 0x11)
        XCTAssertEqual(PacketType.stop.rawValue, 0x30)
        XCTAssertEqual(PacketType.stopAck.rawValue, 0x31)
        XCTAssertEqual(PacketType.ping.rawValue, 0x40)
        XCTAssertEqual(PacketType.pong.rawValue, 0x41)
    }

    func testPacketTypeExpectedResponse() {
        XCTAssertEqual(PacketType.hello.expectedResponse, .helloAck)
        XCTAssertEqual(PacketType.start.expectedResponse, .startAck)
        XCTAssertEqual(PacketType.frame.expectedResponse, .frameAck)
        XCTAssertEqual(PacketType.stop.expectedResponse, .stopAck)
        XCTAssertEqual(PacketType.ping.expectedResponse, .pong)
        XCTAssertNil(PacketType.helloAck.expectedResponse)
    }

    // MARK: - Packet Header Tests

    func testPacketHeaderSerialization() {
        let header = PacketHeader(
            packetType: .hello,
            flags: 0,
            sequence: 42,
            payloadLength: 28
        )

        let bytes = header.toBytes()

        XCTAssertEqual(bytes.count, SWRPConstants.headerSize)
        XCTAssertEqual(bytes.readUInt32LE(at: 0), SWRPConstants.magic)
        XCTAssertEqual(bytes.readUInt8(at: 4), SWRPConstants.protocolVersion)
        XCTAssertEqual(bytes.readUInt8(at: 5), PacketType.hello.rawValue)
        XCTAssertEqual(bytes.readUInt16LE(at: 6), 0)
        XCTAssertEqual(bytes.readUInt32LE(at: 8), 42)
        XCTAssertEqual(bytes.readUInt32LE(at: 12), 28)
    }

    func testPacketHeaderParsing() throws {
        let header = PacketHeader(
            packetType: .start,
            flags: 0x1234,
            sequence: 100,
            payloadLength: 24
        )

        let bytes = header.toBytes()
        let parsed = try PacketHeader.parse(bytes)

        XCTAssertEqual(parsed.magic, SWRPConstants.magic)
        XCTAssertEqual(parsed.version, SWRPConstants.protocolVersion)
        XCTAssertEqual(parsed.packetType, .start)
        XCTAssertEqual(parsed.flags, 0x1234)
        XCTAssertEqual(parsed.sequence, 100)
        XCTAssertEqual(parsed.payloadLength, 24)
    }

    func testPacketHeaderInvalidMagic() {
        var data = Data(repeating: 0, count: 16)
        data.replaceSubrange(0..<4, with: Data([0xFF, 0xFF, 0xFF, 0xFF]))

        XCTAssertThrowsError(try PacketHeader.parse(data)) { error in
            guard case SerialWarpError.invalidMagic = error else {
                XCTFail("Expected invalidMagic error")
                return
            }
        }
    }

    // MARK: - Packet Tests

    func testPacketRoundtrip() throws {
        let payload = HelloPayload(
            softwareVersion: 1,
            maxWidth: 3840,
            maxHeight: 2160,
            maxFps: 60,
            capabilities: 0x03
        )

        let packet = Packet.hello(sequence: 1, payload: payload)
        let bytes = packet.toBytes()

        let (parsed, consumed) = try Packet.parse(bytes)

        XCTAssertEqual(consumed, bytes.count)
        XCTAssertEqual(parsed.packetType, .hello)
        XCTAssertEqual(parsed.sequence, 1)
        XCTAssertEqual(parsed.payload, payload.toBytes())
    }

    func testPacketChecksumMismatch() throws {
        let payload = Data([0x01, 0x02, 0x03, 0x04])
        let packet = Packet(type: .ping, sequence: 1, payload: payload)
        var bytes = packet.toBytes()

        // Corrupt a byte in the payload
        let payloadStart = SWRPConstants.headerSize
        bytes[payloadStart] ^= 0xFF

        XCTAssertThrowsError(try Packet.parse(bytes)) { error in
            guard case SerialWarpError.checksumMismatch = error else {
                XCTFail("Expected checksumMismatch error")
                return
            }
        }
    }

    // MARK: - Hello Payload Tests

    func testHelloPayloadSerialization() {
        let payload = HelloPayload(
            softwareVersion: 1,
            maxWidth: 3840,
            maxHeight: 2160,
            maxFps: 60,
            capabilities: 0x03
        )

        let bytes = payload.toBytes()
        XCTAssertEqual(bytes.count, SWRPConstants.PayloadSize.hello)

        // Verify fields
        XCTAssertEqual(bytes.readUInt16LE(at: 0), 1)  // software_version
        XCTAssertEqual(bytes.readUInt32LE(at: 8), 3840)  // max_width
        XCTAssertEqual(bytes.readUInt32LE(at: 12), 2160)  // max_height
        XCTAssertEqual(bytes.readUInt32LE(at: 16), 60 << 16)  // max_fps_fixed
        XCTAssertEqual(bytes.readUInt32LE(at: 20), 0x03)  // capabilities
    }

    func testHelloPayloadParsing() throws {
        let original = HelloPayload(
            softwareVersion: 1,
            maxWidth: 3840,
            maxHeight: 2160,
            maxFps: 60,
            capabilities: 0x03
        )

        let bytes = original.toBytes()
        let parsed = try HelloPayload.parse(bytes)

        XCTAssertEqual(parsed.softwareVersion, 1)
        XCTAssertEqual(parsed.maxWidth, 3840)
        XCTAssertEqual(parsed.maxHeight, 2160)
        XCTAssertEqual(parsed.maxFps, 60)
        XCTAssertEqual(parsed.capabilities, 0x03)
        XCTAssertTrue(parsed.supportsHidpi)
        XCTAssertTrue(parsed.supportsAudio)
    }

    // MARK: - Start Payload Tests

    func testStartPayloadSerialization() {
        let payload = StartPayload(
            width: 1920,
            height: 1080,
            fps: 60,
            bitrateBps: 20_000_000
        )

        let bytes = payload.toBytes()
        XCTAssertEqual(bytes.count, SWRPConstants.PayloadSize.start)

        XCTAssertEqual(bytes.readUInt32LE(at: 0), 1920)
        XCTAssertEqual(bytes.readUInt32LE(at: 4), 1080)
        XCTAssertEqual(bytes.readUInt32LE(at: 8), 60 << 16)
        XCTAssertEqual(bytes.readUInt32LE(at: 12), 20_000_000)
    }

    func testStartPayloadParsing() throws {
        let original = StartPayload(
            width: 1920,
            height: 1080,
            fps: 60,
            bitrateBps: 20_000_000
        )

        let bytes = original.toBytes()
        let parsed = try StartPayload.parse(bytes)

        XCTAssertEqual(parsed.width, 1920)
        XCTAssertEqual(parsed.height, 1080)
        XCTAssertEqual(parsed.fps, 60)
        XCTAssertEqual(parsed.bitrateBps, 20_000_000)
    }

    // MARK: - Frame Header Tests

    func testFrameHeaderSerialization() {
        let header = FrameHeader(
            frameNumber: 42,
            ptsUs: 1_000_000,
            captureTsUs: 1_000_100,
            frameSize: 65536,
            segmentIndex: 0,
            segmentCount: 2
        )

        let bytes = header.toBytes()
        XCTAssertEqual(bytes.count, SWRPConstants.PayloadSize.frameHeader)

        XCTAssertEqual(bytes.readUInt64LE(at: 0), 42)
        XCTAssertEqual(bytes.readUInt64LE(at: 8), 1_000_000)
        XCTAssertEqual(bytes.readUInt64LE(at: 16), 1_000_100)
        XCTAssertEqual(bytes.readUInt32LE(at: 24), 65536)
        XCTAssertEqual(bytes.readUInt16LE(at: 28), 0)
        XCTAssertEqual(bytes.readUInt16LE(at: 30), 2)
    }

    func testFrameHeaderParsing() throws {
        let original = FrameHeader(
            frameNumber: 42,
            ptsUs: 1_000_000,
            captureTsUs: 1_000_100,
            frameSize: 65536,
            segmentIndex: 0,
            segmentCount: 2
        )

        let bytes = original.toBytes()
        let parsed = try FrameHeader.parse(bytes)

        XCTAssertEqual(parsed.frameNumber, 42)
        XCTAssertEqual(parsed.ptsUs, 1_000_000)
        XCTAssertEqual(parsed.captureTsUs, 1_000_100)
        XCTAssertEqual(parsed.frameSize, 65536)
        XCTAssertEqual(parsed.segmentIndex, 0)
        XCTAssertEqual(parsed.segmentCount, 2)
    }

    func testFrameHeaderInvalidSegment() {
        // segment_index >= segment_count should throw
        var data = Data(repeating: 0, count: 32)
        data.replaceSubrange(28..<30, with: Data([0x02, 0x00]))  // segment_index = 2
        data.replaceSubrange(30..<32, with: Data([0x02, 0x00]))  // segment_count = 2

        XCTAssertThrowsError(try FrameHeader.parse(data)) { error in
            guard case SerialWarpError.frameReassemblyError = error else {
                XCTFail("Expected frameReassemblyError error")
                return
            }
        }
    }

    // MARK: - Frame Ack Tests

    func testFrameAckPayloadRoundtrip() throws {
        let original = FrameAckPayload(
            frameNumber: 42,
            decodeTimeUs: 500,
            creditsReturned: 2
        )

        let bytes = original.toBytes()
        XCTAssertEqual(bytes.count, SWRPConstants.PayloadSize.frameAck)

        let parsed = try FrameAckPayload.parse(bytes)

        XCTAssertEqual(parsed.frameNumber, 42)
        XCTAssertEqual(parsed.decodeTimeUs, 500)
        XCTAssertEqual(parsed.creditsReturned, 2)
    }

    // MARK: - Ping/Pong Tests

    func testPingPayloadRoundtrip() throws {
        let original = PingPayload(timestampUs: 1_234_567_890)

        let bytes = original.toBytes()
        XCTAssertEqual(bytes.count, SWRPConstants.PayloadSize.ping)

        let parsed = try PingPayload.parse(bytes)
        XCTAssertEqual(parsed.timestampUs, 1_234_567_890)
    }

    func testPongPayloadRoundtrip() throws {
        let original = PongPayload(
            pingTimestampUs: 1_234_567_890,
            pongTimestampUs: 1_234_567_900
        )

        let bytes = original.toBytes()
        XCTAssertEqual(bytes.count, SWRPConstants.PayloadSize.pong)

        let parsed = try PongPayload.parse(bytes)
        XCTAssertEqual(parsed.pingTimestampUs, 1_234_567_890)
        XCTAssertEqual(parsed.pongTimestampUs, 1_234_567_900)
        XCTAssertEqual(parsed.roundTripUs, 10)
    }
}
