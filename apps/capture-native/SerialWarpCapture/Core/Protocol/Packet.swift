import Foundation

/// Complete SWRP Packet with header, payload, and CRC
/// Wire format: [header (16 bytes)][payload (variable)][crc32c (4 bytes)]
struct Packet: Sendable {
    let header: PacketHeader
    let payload: Data

    /// Create a new packet
    init(type: PacketType, flags: UInt16 = 0, sequence: UInt32, payload: Data) {
        self.header = PacketHeader(
            packetType: type,
            flags: flags,
            sequence: sequence,
            payloadLength: UInt32(payload.count)
        )
        self.payload = payload
    }

    /// Create a packet with a pre-built header
    init(header: PacketHeader, payload: Data) {
        self.header = header
        self.payload = payload
    }

    /// Get the packet type
    var packetType: PacketType {
        header.packetType
    }

    /// Get the sequence number
    var sequence: UInt32 {
        header.sequence
    }

    /// Total size of the serialized packet
    var totalSize: Int {
        SWRPConstants.headerSize + payload.count + SWRPConstants.crcSize
    }

    /// Serialize packet to bytes (header + payload + CRC)
    func toBytes() -> Data {
        var data = Data.withCapacity(totalSize)

        // Write header
        data.appendData(header.toBytes())

        // Write payload
        data.appendData(payload)

        // Compute and write CRC over header + payload
        let crc = CRC32C.checksum(data)
        data.appendUInt32LE(crc)

        return data
    }

    /// Parse a packet from raw bytes
    /// - Parameter data: Raw bytes containing the packet
    /// - Returns: Tuple of (parsed packet, bytes consumed)
    /// - Throws: SerialWarpError if parsing fails
    static func parse(_ data: Data) throws -> (Packet, Int) {
        // Parse header first
        let header = try PacketHeader.parse(data)

        let totalSize = SWRPConstants.headerSize + Int(header.payloadLength) + SWRPConstants.crcSize

        guard data.count >= totalSize else {
            throw SerialWarpError.bufferTooShort(needed: totalSize, available: data.count)
        }

        // Extract payload
        let payloadStart = SWRPConstants.headerSize
        let payloadEnd = SWRPConstants.headerSize + Int(header.payloadLength)
        guard let payload = data.subdata(offset: payloadStart, length: Int(header.payloadLength)) else {
            throw SerialWarpError.parseError("Failed to extract payload")
        }

        // Verify CRC
        let crcOffset = payloadEnd
        guard let expectedCRC = data.readUInt32LE(at: crcOffset) else {
            throw SerialWarpError.parseError("Failed to read CRC")
        }

        // Calculate CRC over header + payload
        let dataWithoutCRC = data.prefix(payloadEnd)
        let actualCRC = CRC32C.checksum(dataWithoutCRC)

        guard expectedCRC == actualCRC else {
            throw SerialWarpError.checksumMismatch(expected: expectedCRC, actual: actualCRC)
        }

        return (Packet(header: header, payload: payload), totalSize)
    }
}

// MARK: - Convenience Factory Methods

extension Packet {
    /// Create a HELLO packet
    static func hello(sequence: UInt32, payload: HelloPayload) -> Packet {
        Packet(type: .hello, sequence: sequence, payload: payload.toBytes())
    }

    /// Create a HELLO_ACK packet
    static func helloAck(sequence: UInt32, payload: HelloPayload) -> Packet {
        Packet(type: .helloAck, sequence: sequence, payload: payload.toBytes())
    }

    /// Create a START packet
    static func start(sequence: UInt32, payload: StartPayload) -> Packet {
        Packet(type: .start, sequence: sequence, payload: payload.toBytes())
    }

    /// Create a START_ACK packet
    static func startAck(sequence: UInt32, payload: StartAckPayload) -> Packet {
        Packet(type: .startAck, sequence: sequence, payload: payload.toBytes())
    }

    /// Create a FRAME packet
    static func frame(sequence: UInt32, header: FrameHeader, data: Data) -> Packet {
        var payload = header.toBytes()
        payload.appendData(data)
        return Packet(type: .frame, sequence: sequence, payload: payload)
    }

    /// Create a FRAME_ACK packet
    static func frameAck(sequence: UInt32, payload: FrameAckPayload) -> Packet {
        Packet(type: .frameAck, sequence: sequence, payload: payload.toBytes())
    }

    /// Create a STOP packet
    static func stop(sequence: UInt32) -> Packet {
        Packet(type: .stop, sequence: sequence, payload: Data())
    }

    /// Create a STOP_ACK packet
    static func stopAck(sequence: UInt32) -> Packet {
        Packet(type: .stopAck, sequence: sequence, payload: Data())
    }

    /// Create a PING packet
    static func ping(sequence: UInt32, payload: PingPayload) -> Packet {
        Packet(type: .ping, sequence: sequence, payload: payload.toBytes())
    }

    /// Create a PONG packet
    static func pong(sequence: UInt32, payload: PongPayload) -> Packet {
        Packet(type: .pong, sequence: sequence, payload: payload.toBytes())
    }
}
