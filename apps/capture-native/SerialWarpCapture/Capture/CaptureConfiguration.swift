import Foundation

/// Configuration for screen capture
struct CaptureConfiguration: Sendable {
    /// Capture width in pixels
    let width: UInt32

    /// Capture height in pixels
    let height: UInt32

    /// Target frames per second
    let fps: UInt32

    /// Pixel format (BGRA, NV12, etc.)
    let pixelFormat: UInt32

    /// Whether to show cursor in capture
    let showCursor: Bool

    /// Queue depth for buffering frames
    let queueDepth: Int

    /// Create a capture configuration
    init(
        width: UInt32,
        height: UInt32,
        fps: UInt32,
        pixelFormat: UInt32 = 0x42475241,  // 'BGRA' = kCVPixelFormatType_32BGRA
        showCursor: Bool = true,
        queueDepth: Int = 8
    ) {
        self.width = width
        self.height = height
        self.fps = fps
        self.pixelFormat = pixelFormat
        self.showCursor = showCursor
        self.queueDepth = queueDepth
    }

    /// Configuration string for debugging
    var description: String {
        "\(width)x\(height)@\(fps)fps"
    }
}

// MARK: - Pixel Format Constants

extension CaptureConfiguration {
    /// BGRA pixel format (32-bit, 8 bits per component)
    static let pixelFormatBGRA: UInt32 = 0x42475241  // kCVPixelFormatType_32BGRA

    /// NV12 pixel format (YUV 4:2:0 bi-planar)
    static let pixelFormatNV12: UInt32 = 0x34323076  // kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
}
