import Foundation
import CoreMedia
import CoreVideo

/// A captured frame from ScreenCaptureKit
struct CapturedFrame: @unchecked Sendable {
    /// The pixel buffer containing the frame data
    let pixelBuffer: CVPixelBuffer

    /// Presentation timestamp
    let presentationTime: CMTime

    /// Frame width
    var width: Int {
        CVPixelBufferGetWidth(pixelBuffer)
    }

    /// Frame height
    var height: Int {
        CVPixelBufferGetHeight(pixelBuffer)
    }

    /// Pixel format
    var pixelFormat: OSType {
        CVPixelBufferGetPixelFormatType(pixelBuffer)
    }

    /// Presentation time in microseconds
    var ptsUs: UInt64 {
        let seconds = CMTimeGetSeconds(presentationTime)
        return UInt64(seconds * 1_000_000)
    }

    /// Create a captured frame
    init(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        self.pixelBuffer = pixelBuffer
        self.presentationTime = presentationTime
    }

    /// Create a captured frame from a sample buffer
    init?(sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        self.pixelBuffer = imageBuffer
        self.presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    }

    /// Lock the pixel buffer for reading
    func withLockedBaseAddress<T>(_ body: (UnsafeRawPointer, Int) throws -> T) rethrows -> T {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)!
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        return try body(baseAddress, bytesPerRow)
    }

    /// Get the frame data as Data (copies the buffer)
    func getData() -> Data {
        withLockedBaseAddress { baseAddress, bytesPerRow in
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let dataSize = bytesPerRow * height
            return Data(bytes: baseAddress, count: dataSize)
        }
    }
}
