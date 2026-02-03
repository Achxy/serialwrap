import Foundation

/// Extension for little-endian binary serialization/deserialization
extension Data {

    // MARK: - Appending (Writing)

    /// Append a UInt8 value
    mutating func appendUInt8(_ value: UInt8) {
        append(value)
    }

    /// Append a UInt16 value in little-endian format
    mutating func appendUInt16LE(_ value: UInt16) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }

    /// Append a UInt32 value in little-endian format
    mutating func appendUInt32LE(_ value: UInt32) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }

    /// Append a UInt64 value in little-endian format
    mutating func appendUInt64LE(_ value: UInt64) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }

    /// Append another Data object
    mutating func appendData(_ data: Data) {
        append(data)
    }

    // MARK: - Reading

    /// Read a UInt8 value at the given offset
    func readUInt8(at offset: Int) -> UInt8? {
        guard offset < count else { return nil }
        return self[offset]
    }

    /// Read a UInt16 value in little-endian format at the given offset
    func readUInt16LE(at offset: Int) -> UInt16? {
        guard offset + 2 <= count else { return nil }
        return self.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: offset, as: UInt16.self).littleEndian
        }
    }

    /// Read a UInt32 value in little-endian format at the given offset
    func readUInt32LE(at offset: Int) -> UInt32? {
        guard offset + 4 <= count else { return nil }
        return self.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: offset, as: UInt32.self).littleEndian
        }
    }

    /// Read a UInt64 value in little-endian format at the given offset
    func readUInt64LE(at offset: Int) -> UInt64? {
        guard offset + 8 <= count else { return nil }
        return self.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: offset, as: UInt64.self).littleEndian
        }
    }

    /// Extract a subrange as Data
    func subdata(offset: Int, length: Int) -> Data? {
        guard offset + length <= count else { return nil }
        return self.subdata(in: offset..<(offset + length))
    }
}

/// Extension for creating Data with a specific capacity
extension Data {
    /// Create an empty Data with reserved capacity
    static func withCapacity(_ capacity: Int) -> Data {
        var data = Data()
        data.reserveCapacity(capacity)
        return data
    }
}
