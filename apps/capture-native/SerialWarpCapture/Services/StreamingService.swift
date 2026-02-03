import Foundation
import CoreGraphics

/// Main streaming service that wraps the StreamingPipeline
/// Provides a simplified interface for the UI
@available(macOS 12.3, *)
@MainActor
final class StreamingService: ObservableObject, StreamingPipelineDelegate {

    /// Shared instance
    static let shared = StreamingService()

    /// The underlying streaming pipeline
    private var pipeline: StreamingPipeline?

    /// Application state
    private let appState = AppState.shared

    /// Whether the service is initialized
    private(set) var isInitialized = false

    private init() {
        Task {
            pipeline = StreamingPipeline()
            await pipeline?.delegate = self
            isInitialized = true
        }
    }

    // MARK: - Public API

    /// Connect to a USB device
    func connect() async throws {
        guard let pipeline = pipeline else {
            throw SerialWarpError.encoderNotReady
        }
        try await pipeline.connect()
    }

    /// Start streaming with current configuration
    func startStreaming() async throws {
        guard let pipeline = pipeline else {
            throw SerialWarpError.encoderNotReady
        }

        let config = appState.streamConfig.toStreamConfiguration()
        try await pipeline.startStreaming(config: config)
    }

    /// Stop streaming
    func stopStreaming() async {
        guard let pipeline = pipeline else { return }
        await pipeline.stopStreaming()
    }

    /// Disconnect from USB device
    func disconnect() async {
        guard let pipeline = pipeline else { return }
        await pipeline.disconnect()
    }

    /// Destroy virtual display
    func destroyVirtualDisplay() {
        VirtualDisplayManager.shared.destroy()
        appState.virtualDisplayId = nil
        appState.refreshDisplays()
    }

    /// Get current pipeline state
    func getCurrentState() async -> PipelineState {
        guard let pipeline = pipeline else { return .disconnected }
        return await pipeline.state
    }

    // MARK: - StreamingPipelineDelegate

    nonisolated func pipeline(_ pipeline: StreamingPipeline, didChangeState state: PipelineState) {
        Task { @MainActor in
            self.appState.updateFromPipelineState(state)

            if state == .streaming {
                self.appState.virtualDisplayId = VirtualDisplayManager.shared.displayId
                self.appState.refreshDisplays()
            } else if state == .disconnected || state == .ready {
                if state == .disconnected {
                    self.appState.virtualDisplayId = nil
                }
                self.appState.refreshDisplays()
            }
        }
    }

    nonisolated func pipeline(_ pipeline: StreamingPipeline, didUpdateStats stats: PipelineStats) {
        Task { @MainActor in
            self.appState.updateStats(from: stats)
        }
    }

    nonisolated func pipeline(_ pipeline: StreamingPipeline, didCapturePreviewFrame frame: CGImage) {
        Task { @MainActor in
            self.appState.previewFrame = frame
        }
    }

    nonisolated func pipeline(_ pipeline: StreamingPipeline, didEncounterError error: Error) {
        Task { @MainActor in
            self.appState.lastError = error.localizedDescription
            self.appState.connectionStatus = .error
        }
    }
}
