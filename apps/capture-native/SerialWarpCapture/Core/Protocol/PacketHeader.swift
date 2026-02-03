import Foundation

/// SWRP Packet Header (16 bytes)
/// Layout:
///   - magic: u32 (4 bytes) - Protocol magic number
///   - version: u8 (1 byte) - Protocol version
///   - packet_type: u8 (1 byte) - Type of packet
///   - flags: u16 (2 bytes) - Packet flags
///   - sequence: u32 (4 bytes) - Sequence number
///   - payload_length: u32 (4 bytes) - Length of payload
struct PacketHeader: Sendable {
    let magic: UInt32
    let version: UInt8
    let packetType: PacketType
    let flags: UInt16
    let sequence: UInt32
    let payloadLength: UInt32

    /// Create a new packet header
    init(packetType: PacketType, flags: UInt16 = 0, sequence: UInt32, payloadLength: UInt32) {
        self.magic = SWRPConstants.magic
        self.version = SWRPConstants.protocolVersion
        self.packetType = packetType
        self.flags = flags
        self.sequence = sequence
        self.payloadLength = payloadLength
    }

    /// Create a packet header from all fields (used during parsing)
    private init(
        magic: UInt32,
        version: UInt8,
        packetType: PacketType,
        flags: UInt16,
        sequence: UInt32,
        payloadLength: UInt32
    ) {
        self.magic = magic
        self.version = version
        self.packetType = packetType
        self.flags = flags
        self.sequence = sequence
        self.payloadLength = payloadLength
    }

    /// Serialize header to bytes (16 bytes)
    func toBytes() -> Data {
        var data = Data.withCapacity(SWRPConstants.headerSize)
        data.appendUInt32LE(magic)
        data.appendUInt8(version)
        data.appendUInt8(packetType.rawValue)
        data.appendUInt16LE(flags)
        data.appendUInt32LE(sequence)
        data.appendUInt32LE(payloadLength)
        return data
    }

    /// Parse header from bytes
    /// - Parameter data: Raw bytes (must be at least 16 bytes)
    /// - Returns: Parsed header
    /// - Throws: SerialWarpError if parsing fails
    static func parse(_ data: Data) throws -> PacketHeader {
        guard data.count >= SWRPConstants.headerSize else {
            throw SerialWarpError.bufferTooShort(needed: SWRPConstants.headerSize, available: data.count)
        }

        guard let magic = data.readUInt32LE(at: 0) else {
            throw SerialWarpError.parseError("Failed to read magic")
        }

        guard magic == SWRPConstants.magic else {
            throw SerialWarpError.invalidMagic(magic)
        }

        guard let version = data.readUInt8(at: 4) else {
            throw SerialWarpError.parseError("Failed to read version")
        }

        guard version == SWRPConstants.protocolVersion else {
            throw SerialWarpError.unsupportedVersion(version)
        }

        guard let packetTypeRaw = data.readUInt8(at: 5) else {
            throw SerialWarpError.parseError("Failed to read packet type")
        }

        guard let packetType = PacketType(rawValue: packetTypeRaw) else {
            throw SerialWarpError.unknownPacketType(packetTypeRaw)
        }

        guard let flags = data.readUInt16LE(at: 6) else {
            throw SerialWarpError.parseError("Failed to read flags")
        }

        guard let sequence = data.readUInt32LE(at: 8) else {
            throw SerialWarpError.parseError("Failed to read sequence")
        }

        guard let payloadLength = data.readUInt32LE(at: 12) else {
            throw SerialWarpError.parseError("Failed to read payload length")
        }

        return PacketHeader(
            magic: magic,
            version: version,
            packetType: packetType,
            flags: flags,
            sequence: sequence,
            payloadLength: payloadLength
        )
    }
}
