import Foundation
import Combine
import CoreGraphics

/// Connection status enum
enum ConnectionStatus: String, Sendable {
    case disconnected
    case connecting
    case connected
    case handshaking
    case ready
    case streaming
    case stopping
    case error
}

/// Main application state using Combine for reactive updates
@MainActor
class AppState: ObservableObject {

    static let shared = AppState()

    // MARK: - Connection State

    /// Current connection status
    @Published var connectionStatus: ConnectionStatus = .disconnected

    /// Virtual display ID (if created)
    @Published var virtualDisplayId: UInt32?

    /// Whether streaming is active
    @Published var isStreaming: Bool = false

    /// Last error message
    @Published var lastError: String?

    // MARK: - Stream Configuration

    /// Current stream configuration
    @Published var streamConfig: StreamConfig = .default

    // MARK: - Statistics

    /// Current stream statistics
    @Published var streamStats: StreamStats = StreamStats()

    // MARK: - Settings

    /// Application settings
    @Published var settings: AppSettings = .default

    // MARK: - Displays

    /// Available displays
    @Published var displays: [DisplayInfo] = []

    /// Connected USB devices
    @Published var usbDevices: [USBDeviceInfo] = []

    // MARK: - Preview

    /// Current preview frame
    @Published var previewFrame: CGImage?

    // MARK: - Initialization

    private init() {
        refreshDisplays()
        loadSettings()
    }

    // MARK: - Display Management

    func refreshDisplays() {
        var displayInfos: [DisplayInfo] = []

        guard let displayIDs = CGGetActiveDisplayList() else { return }

        for (index, displayID) in displayIDs.enumerated() {
            let bounds = CGDisplayBounds(displayID)
            let isVirtual = displayID == virtualDisplayId

            let display = DisplayInfo(
                id: displayID,
                name: isVirtual ? "SerialWarp Virtual Display" : "Display \(index + 1)",
                width: UInt32(bounds.width),
                height: UInt32(bounds.height),
                refreshRate: 60.0,
                isMain: CGDisplayIsMain(displayID) != 0,
                isVirtual: isVirtual
            )
            displayInfos.append(display)
        }

        displays = displayInfos
    }

    // MARK: - USB Device Management

    func refreshUsbDevices() {
        // USB device list is managed by USBDeviceManager
        // This method triggers a refresh
        USBDeviceManager.shared.scanForDevices()
        usbDevices = USBDeviceManager.shared.connectedDevices
    }

    // MARK: - Settings

    func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: "appSettings"),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        }
    }

    func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "appSettings")
        }
    }

    // MARK: - State Updates from Pipeline

    func updateFromPipelineState(_ state: PipelineState) {
        switch state {
        case .disconnected:
            connectionStatus = .disconnected
            isStreaming = false
        case .connecting:
            connectionStatus = .connecting
        case .connected:
            connectionStatus = .connected
        case .handshaking:
            connectionStatus = .handshaking
        case .ready:
            connectionStatus = .ready
            isStreaming = false
        case .starting:
            connectionStatus = .streaming
        case .streaming:
            connectionStatus = .streaming
            isStreaming = true
        case .stopping:
            connectionStatus = .stopping
        case .error:
            connectionStatus = .error
            isStreaming = false
        }
    }

    func updateStats(from pipelineStats: PipelineStats) {
        streamStats = StreamStats(
            fps: pipelineStats.currentFps,
            bitrateBps: pipelineStats.currentBitrateBps,
            framesCaptured: pipelineStats.framesCaptured,
            framesEncoded: pipelineStats.framesEncoded,
            framesSent: pipelineStats.framesSent,
            framesDropped: pipelineStats.framesDropped,
            elapsedSeconds: pipelineStats.elapsedSeconds
        )
    }
}

// MARK: - Stream Configuration

struct StreamConfig: Codable, Sendable {
    var width: UInt32 = 1920
    var height: UInt32 = 1080
    var fps: UInt32 = 60
    var bitrateMbps: UInt32 = 20
    var hidpi: Bool = false

    static let `default` = StreamConfig()

    var resolution: String {
        "\(width)x\(height)"
    }

    /// Convert to StreamConfiguration for pipeline
    func toStreamConfiguration() -> StreamConfiguration {
        StreamConfiguration(
            width: width,
            height: height,
            fps: fps,
            bitrateMbps: bitrateMbps,
            hidpi: hidpi
        )
    }

    static let resolutions: [(String, UInt32, UInt32)] = [
        ("1920x1080 (1080p)", 1920, 1080),
        ("2560x1440 (1440p)", 2560, 1440),
        ("3840x2160 (4K)", 3840, 2160),
        ("1280x720 (720p)", 1280, 720),
    ]

    static let frameRates: [UInt32] = [30, 60, 120]
    static let bitrates: [UInt32] = [5, 10, 15, 20, 30, 50]
}

// MARK: - Stream Statistics

struct StreamStats: Sendable {
    var fps: Double = 0
    var bitrateBps: UInt64 = 0
    var framesCaptured: UInt64 = 0
    var framesEncoded: UInt64 = 0
    var framesSent: UInt64 = 0
    var framesDropped: UInt64 = 0
    var elapsedSeconds: Double = 0

    var bitrateFormatted: String {
        let mbps = Double(bitrateBps) / 1_000_000
        return String(format: "%.1f Mbps", mbps)
    }

    var fpsFormatted: String {
        String(format: "%.1f fps", fps)
    }

    var elapsedFormatted: String {
        let minutes = Int(elapsedSeconds) / 60
        let seconds = Int(elapsedSeconds) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Application Settings

struct AppSettings: Codable, Sendable {
    var defaultResolution: String = "1920x1080"
    var defaultFps: UInt32 = 60
    var defaultBitrateMbps: UInt32 = 20
    var autoConnect: Bool = false
    var previewEnabled: Bool = true
    var previewQuality: UInt32 = 50

    static let `default` = AppSettings()
}

// MARK: - CoreGraphics Helper

func CGGetActiveDisplayList() -> [CGDirectDisplayID]? {
    var displayCount: UInt32 = 0

    // Get display count
    if CGGetActiveDisplayList(0, nil, &displayCount) != .success {
        return nil
    }

    guard displayCount > 0 else { return [] }

    var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
    if CGGetActiveDisplayList(displayCount, &displays, &displayCount) != .success {
        return nil
    }

    return displays
}
