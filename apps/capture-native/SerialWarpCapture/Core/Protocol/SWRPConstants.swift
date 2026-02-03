import Foundation

/// SWRP Protocol Constants
/// These values must match the Rust implementation exactly for wire compatibility
enum SWRPConstants {
    /// Protocol magic number "SWRP" in little-endian (0x50525753 in big-endian)
    static let magic: UInt32 = 0x53575250

    /// Current protocol version
    static let protocolVersion: UInt8 = 1

    /// Maximum segment size for frame data (64KB)
    static let maxSegmentSize: Int = 65536

    /// Packet header size in bytes
    static let headerSize: Int = 16

    /// CRC32C checksum size in bytes
    static let crcSize: Int = 4

    /// Default initial credits for flow control
    static let defaultInitialCredits: UInt16 = 8

    /// Capability flags
    enum Capabilities {
        static let hidpi: UInt32 = 0x01
        static let audio: UInt32 = 0x02
    }

    /// Payload sizes for each packet type
    enum PayloadSize {
        static let hello: Int = 28
        static let start: Int = 24
        static let startAck: Int = 4
        static let frameHeader: Int = 32
        static let frameAck: Int = 16
        static let ping: Int = 8
        static let pong: Int = 16
    }
}
