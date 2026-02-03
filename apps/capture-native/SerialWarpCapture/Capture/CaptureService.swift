import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreImage

/// Delegate protocol for capture events
protocol CaptureServiceDelegate: AnyObject {
    func captureService(_ service: CaptureService, didCaptureFrame frame: CapturedFrame)
    func captureService(_ service: CaptureService, didEncounterError error: Error)
}

/// Screen capture service using ScreenCaptureKit
@available(macOS 12.3, *)
actor CaptureService: NSObject {

    /// Delegate for capture callbacks
    weak var delegate: CaptureServiceDelegate?

    /// The capture stream
    private var stream: SCStream?

    /// Content filter
    private var filter: SCContentFilter?

    /// Whether capture is active
    private(set) var isCapturing: Bool = false

    /// Current configuration
    private(set) var configuration: CaptureConfiguration?

    /// Frame handler for async stream
    private var frameContinuation: AsyncThrowingStream<CapturedFrame, Error>.Continuation?

    /// CIContext for converting frames to CGImage for preview
    private let ciContext = CIContext()

    override init() {
        super.init()
    }

    /// Start capturing the specified display
    /// - Parameters:
    ///   - displayId: The display to capture
    ///   - config: Capture configuration
    /// - Returns: An async stream of captured frames
    func startCapture(
        displayId: CGDirectDisplayID,
        config: CaptureConfiguration
    ) async throws -> AsyncThrowingStream<CapturedFrame, Error> {
        guard !isCapturing else {
            throw SerialWarpError.captureFailed("Already capturing")
        }

        // Get shareable content
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        // Find the target display
        guard let display = content.displays.first(where: { $0.displayID == displayId }) else {
            throw SerialWarpError.displayNotFound(displayId)
        }

        // Create content filter
        filter = SCContentFilter(display: display, excludingWindows: [])

        // Create stream configuration
        let streamConfig = SCStreamConfiguration()
        streamConfig.width = Int(config.width)
        streamConfig.height = Int(config.height)
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.fps))
        streamConfig.pixelFormat = config.pixelFormat
        streamConfig.showsCursor = config.showCursor
        streamConfig.queueDepth = config.queueDepth

        // Create the async stream
        let frameStream = AsyncThrowingStream<CapturedFrame, Error> { continuation in
            self.frameContinuation = continuation

            continuation.onTermination = { @Sendable _ in
                Task { await self.handleStreamTermination() }
            }
        }

        // Create and configure stream
        stream = SCStream(filter: filter!, configuration: streamConfig, delegate: self)
        try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))

        // Start capture
        try await stream?.startCapture()

        isCapturing = true
        configuration = config

        print("[Capture] Started capturing display \(displayId) at \(config.description)")

        return frameStream
    }

    /// Stop capturing
    func stopCapture() async {
        guard isCapturing else { return }

        do {
            try await stream?.stopCapture()
        } catch {
            print("[Capture] Error stopping capture: \(error)")
        }

        stream = nil
        filter = nil
        isCapturing = false
        configuration = nil

        frameContinuation?.finish()
        frameContinuation = nil

        print("[Capture] Stopped capturing")
    }

    /// Handle stream termination
    private func handleStreamTermination() {
        Task {
            await stopCapture()
        }
    }

    /// Convert a captured frame to CGImage for preview
    nonisolated func createPreviewImage(from frame: CapturedFrame) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: frame.pixelBuffer)
        return ciContext.createCGImage(ciImage, from: ciImage.extent)
    }
}

// MARK: - SCStreamDelegate

@available(macOS 12.3, *)
extension CaptureService: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[Capture] Stream stopped with error: \(error)")

        Task { @MainActor in
            self.delegate?.captureService(self, didEncounterError: error)
        }

        Task {
            await self.stopCapture()
        }
    }
}

// MARK: - SCStreamOutput

@available(macOS 12.3, *)
extension CaptureService: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }

        // Create captured frame
        guard let frame = CapturedFrame(sampleBuffer: sampleBuffer) else {
            return
        }

        // Yield to async stream
        Task {
            await self.yieldFrame(frame)
        }

        // Notify delegate
        Task { @MainActor in
            self.delegate?.captureService(self, didCaptureFrame: frame)
        }
    }

    /// Yield a frame to the async stream
    private func yieldFrame(_ frame: CapturedFrame) {
        frameContinuation?.yield(frame)
    }
}

// MARK: - Permission Check

@available(macOS 12.3, *)
extension CaptureService {
    /// Check if screen recording permission is granted
    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Request screen recording permission
    static func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}
