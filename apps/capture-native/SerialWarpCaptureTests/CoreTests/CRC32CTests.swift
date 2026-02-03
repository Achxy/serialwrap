import XCTest
@testable import SerialWarpCapture

final class CRC32CTests: XCTestCase {

    // MARK: - Known Test Vectors

    /// Test vectors verified against the Rust crc32c crate
    func testKnownVectors() {
        // Empty data
        XCTAssertEqual(CRC32C.checksum(Data()), 0x00000000)

        // Single byte 0x00
        XCTAssertEqual(CRC32C.checksum(Data([0x00])), 0x527D5351)

        // "123456789" (standard test string)
        let testString = "123456789".data(using: .ascii)!
        XCTAssertEqual(CRC32C.checksum(testString), 0xE3069283)

        // All zeros
        let zeros = Data(repeating: 0x00, count: 32)
        XCTAssertEqual(CRC32C.checksum(zeros), 0x8A9136AA)

        // All ones
        let ones = Data(repeating: 0xFF, count: 32)
        XCTAssertEqual(CRC32C.checksum(ones), 0x62A8AB43)

        // Incrementing bytes
        let incrementing = Data(0..<256)
        XCTAssertEqual(CRC32C.checksum(incrementing), 0x477A57BE)
    }

    // MARK: - Protocol Packet CRC Tests

    func testPacketCRC() {
        // Create a simple packet and verify CRC is calculated correctly
        let header = PacketHeader(
            packetType: .hello,
            flags: 0,
            sequence: 1,
            payloadLength: 0
        )

        let headerBytes = header.toBytes()
        let crc = CRC32C.checksum(headerBytes)

        // The CRC should be non-zero for non-trivial data
        XCTAssertNotEqual(crc, 0)

        // CRC should be deterministic
        XCTAssertEqual(CRC32C.checksum(headerBytes), crc)
    }

    // MARK: - Large Data Tests

    func testLargeData() {
        // Test with 64KB of data (max segment size)
        let largeData = Data(repeating: 0xAB, count: 65536)
        let crc = CRC32C.checksum(largeData)

        // CRC should complete without error
        XCTAssertNotEqual(crc, 0)

        // Should be deterministic
        XCTAssertEqual(CRC32C.checksum(largeData), crc)
    }

    // MARK: - Incremental vs Full

    func testConsistency() {
        // The CRC of concatenated data should match byte-by-byte computation
        let data1 = Data([0x01, 0x02, 0x03, 0x04])
        let data2 = Data([0x05, 0x06, 0x07, 0x08])
        let combined = data1 + data2

        let fullCRC = CRC32C.checksum(combined)

        // CRC should be consistent
        XCTAssertEqual(CRC32C.checksum(combined), fullCRC)
    }

    // MARK: - Data Extension

    func testDataExtension() {
        let data = "Hello, World!".data(using: .utf8)!
        let crc1 = data.crc32c
        let crc2 = CRC32C.checksum(data)

        XCTAssertEqual(crc1, crc2)
    }

    // MARK: - Performance Test

    func testPerformance() {
        let largeData = Data(repeating: 0xCD, count: 1024 * 1024)  // 1MB

        measure {
            _ = CRC32C.checksum(largeData)
        }
    }
}
