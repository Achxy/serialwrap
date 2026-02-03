import Foundation

/// State machine for the streaming pipeline
enum PipelineState: String, Sendable {
    /// Initial state, not connected
    case disconnected

    /// Connecting to USB device
    case connecting

    /// Connected, ready to start handshake
    case connected

    /// Performing HELLO handshake
    case handshaking

    /// Handshake complete, ready to start streaming
    case ready

    /// Performing START handshake
    case starting

    /// Actively streaming
    case streaming

    /// Stopping stream
    case stopping

    /// Error state
    case error

    /// Whether streaming is active
    var isStreaming: Bool {
        self == .streaming
    }

    /// Whether connected (any state after connecting)
    var isConnected: Bool {
        switch self {
        case .connected, .handshaking, .ready, .starting, .streaming, .stopping:
            return true
        default:
            return false
        }
    }

    /// Whether in an error state
    var isError: Bool {
        self == .error
    }

    /// Valid next states from the current state
    var validTransitions: Set<PipelineState> {
        switch self {
        case .disconnected:
            return [.connecting]
        case .connecting:
            return [.connected, .disconnected, .error]
        case .connected:
            return [.handshaking, .disconnected, .error]
        case .handshaking:
            return [.ready, .disconnected, .error]
        case .ready:
            return [.starting, .disconnected, .error]
        case .starting:
            return [.streaming, .ready, .disconnected, .error]
        case .streaming:
            return [.stopping, .disconnected, .error]
        case .stopping:
            return [.ready, .disconnected, .error]
        case .error:
            return [.disconnected, .connecting]
        }
    }

    /// Check if transition to new state is valid
    func canTransition(to newState: PipelineState) -> Bool {
        validTransitions.contains(newState)
    }
}

/// Pipeline statistics
struct PipelineStats: Sendable {
    /// Frames captured
    var framesCaptured: UInt64 = 0

    /// Frames encoded
    var framesEncoded: UInt64 = 0

    /// Frames sent
    var framesSent: UInt64 = 0

    /// Frames dropped (encoder or transport backpressure)
    var framesDropped: UInt64 = 0

    /// Total bytes sent
    var bytesSent: UInt64 = 0

    /// Current FPS
    var currentFps: Double = 0

    /// Current bitrate in bps
    var currentBitrateBps: UInt64 = 0

    /// Round-trip latency in microseconds
    var latencyUs: UInt64 = 0

    /// Stream start time
    var startTime: Date?

    /// Elapsed time in seconds
    var elapsedSeconds: Double {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    /// Reset statistics
    mutating func reset() {
        framesCaptured = 0
        framesEncoded = 0
        framesSent = 0
        framesDropped = 0
        bytesSent = 0
        currentFps = 0
        currentBitrateBps = 0
        latencyUs = 0
        startTime = nil
    }
}
