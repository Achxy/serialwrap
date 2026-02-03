import Foundation

/// SerialWarp error types
enum SerialWarpError: LocalizedError {

    // MARK: - Protocol Errors

    /// Invalid magic number in packet header
    case invalidMagic(_ actual: UInt32)

    /// CRC32C checksum mismatch
    case checksumMismatch(expected: UInt32, actual: UInt32)

    /// Unsupported protocol version
    case unsupportedVersion(_ version: UInt8)

    /// Unknown packet type
    case unknownPacketType(_ type: UInt8)

    /// Invalid payload length
    case invalidPayloadLength(expected: Int, actual: Int)

    /// Buffer too short for parsing
    case bufferTooShort(needed: Int, available: Int)

    /// Invalid sequence number
    case invalidSequence(expected: UInt32, actual: UInt32)

    /// Unexpected packet type received
    case unexpectedPacketType(expected: String, actual: UInt8)

    /// Handshake failed
    case handshakeFailed(_ reason: String)

    /// Frame reassembly error
    case frameReassemblyError(_ reason: String)

    /// Generic parse error
    case parseError(_ reason: String)

    // MARK: - Transport Errors

    /// USB device not found
    case deviceNotFound

    /// Device disconnected
    case disconnected

    /// Operation timed out
    case timeout(durationMs: UInt64)

    /// USB error
    case usbError(_ reason: String)

    /// I/O error
    case ioError(_ reason: String)

    /// Connection refused
    case connectionRefused

    /// Channel closed
    case channelClosed

    // MARK: - Encoding Errors

    /// Encoder session creation failed
    case encoderCreationFailed(status: Int32)

    /// Encoding frame failed
    case encodingFailed(status: Int32)

    /// Flushing encoder failed
    case flushFailed(status: Int32)

    /// Property setting failed
    case propertySetFailed(property: String, status: Int32)

    /// Invalid pixel buffer
    case invalidPixelBuffer

    /// No output available from encoder
    case noEncoderOutput

    /// Encoder not ready
    case encoderNotReady

    /// Invalid encoder input
    case invalidEncoderInput(_ reason: String)

    /// Pixel buffer operation failed
    case pixelBufferFailed(status: Int32)

    // MARK: - Capture Errors

    /// Display not found
    case displayNotFound(_ displayId: UInt32)

    /// Capture stream creation failed
    case captureStreamCreationFailed

    /// Screen recording permission denied
    case permissionDenied

    /// Invalid capture configuration
    case invalidCaptureConfiguration(_ reason: String)

    /// Capture failed
    case captureFailed(_ reason: String)

    // MARK: - Virtual Display Errors

    /// Virtual display creation failed
    case virtualDisplayCreationFailed

    /// Virtual display not supported on this macOS version
    case virtualDisplayNotSupported

    /// Invalid display configuration
    case invalidDisplayConfiguration(_ reason: String)

    /// Virtual display already exists
    case displayAlreadyExists

    /// Display not available
    case displayNotAvailable

    // MARK: - LocalizedError Implementation

    var errorDescription: String? {
        switch self {
        // Protocol
        case .invalidMagic(let actual):
            return "Invalid magic: expected 0x\(String(SWRPConstants.magic, radix: 16)), got 0x\(String(actual, radix: 16))"
        case .checksumMismatch(let expected, let actual):
            return "Checksum mismatch: expected 0x\(String(expected, radix: 16)), got 0x\(String(actual, radix: 16))"
        case .unsupportedVersion(let version):
            return "Unsupported protocol version: \(version)"
        case .unknownPacketType(let type):
            return "Unknown packet type: 0x\(String(type, radix: 16))"
        case .invalidPayloadLength(let expected, let actual):
            return "Invalid payload length: expected \(expected), got \(actual)"
        case .bufferTooShort(let needed, let available):
            return "Buffer too short: need \(needed) bytes, have \(available)"
        case .invalidSequence(let expected, let actual):
            return "Invalid sequence number: expected \(expected), got \(actual)"
        case .unexpectedPacketType(let expected, let actual):
            return "Unexpected packet type: expected \(expected), got 0x\(String(actual, radix: 16))"
        case .handshakeFailed(let reason):
            return "Handshake failed: \(reason)"
        case .frameReassemblyError(let reason):
            return "Frame reassembly error: \(reason)"
        case .parseError(let reason):
            return "Parse error: \(reason)"

        // Transport
        case .deviceNotFound:
            return "USB device not found"
        case .disconnected:
            return "Device disconnected"
        case .timeout(let durationMs):
            return "Operation timed out after \(durationMs)ms"
        case .usbError(let reason):
            return "USB error: \(reason)"
        case .ioError(let reason):
            return "I/O error: \(reason)"
        case .connectionRefused:
            return "Connection refused"
        case .channelClosed:
            return "Channel closed"

        // Encoding
        case .encoderCreationFailed(let status):
            return "Encoder session creation failed with status: \(status)"
        case .encodingFailed(let status):
            return "Encoding frame failed with status: \(status)"
        case .flushFailed(let status):
            return "Flushing encoder failed with status: \(status)"
        case .propertySetFailed(let property, let status):
            return "Property setting failed: \(property) with status \(status)"
        case .invalidPixelBuffer:
            return "Invalid pixel buffer"
        case .noEncoderOutput:
            return "No output available from encoder"
        case .encoderNotReady:
            return "Encoder not ready"
        case .invalidEncoderInput(let reason):
            return "Invalid encoder input: \(reason)"
        case .pixelBufferFailed(let status):
            return "Pixel buffer operation failed with status: \(status)"

        // Capture
        case .displayNotFound(let displayId):
            return "Display not found: \(displayId)"
        case .captureStreamCreationFailed:
            return "Capture stream creation failed"
        case .permissionDenied:
            return "Screen recording permission denied"
        case .invalidCaptureConfiguration(let reason):
            return "Invalid capture configuration: \(reason)"
        case .captureFailed(let reason):
            return "Capture failed: \(reason)"

        // Virtual Display
        case .virtualDisplayCreationFailed:
            return "Failed to create virtual display"
        case .virtualDisplayNotSupported:
            return "Virtual display creation is not supported on this macOS version (requires macOS 14+)"
        case .invalidDisplayConfiguration(let reason):
            return "Invalid display configuration: \(reason)"
        case .displayAlreadyExists:
            return "Virtual display already exists"
        case .displayNotAvailable:
            return "Display not available"
        }
    }
}
