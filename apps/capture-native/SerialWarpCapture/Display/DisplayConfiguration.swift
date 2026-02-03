import Foundation

/// Configuration for creating a virtual display
struct DisplayConfiguration: Sendable {
    /// Display width in pixels
    let width: UInt32

    /// Display height in pixels
    let height: UInt32

    /// Refresh rate in Hz
    let refreshRate: UInt32

    /// Whether HiDPI (Retina) mode is enabled
    let hidpiEnabled: Bool

    /// Serial number for the virtual display
    let serialNumber: UInt32

    /// Display name
    let name: String

    /// Create a display configuration
    init(
        width: UInt32,
        height: UInt32,
        refreshRate: UInt32,
        hidpiEnabled: Bool = false,
        serialNumber: UInt32 = 12345,
        name: String = "SerialWarp"
    ) {
        self.width = width
        self.height = height
        self.refreshRate = refreshRate
        self.hidpiEnabled = hidpiEnabled
        self.serialNumber = serialNumber
        self.name = name
    }

    /// The actual mode dimensions (for HiDPI this is half the display resolution)
    var modeWidth: UInt32 {
        hidpiEnabled ? width / 2 : width
    }

    var modeHeight: UInt32 {
        hidpiEnabled ? height / 2 : height
    }

    /// Resolution string
    var resolutionString: String {
        "\(width)x\(height)@\(refreshRate)Hz\(hidpiEnabled ? " (HiDPI)" : "")"
    }
}

// MARK: - Standard Configurations

extension DisplayConfiguration {
    /// 1080p at 60Hz
    static let fhd60 = DisplayConfiguration(width: 1920, height: 1080, refreshRate: 60)

    /// 1080p at 60Hz with HiDPI
    static let fhd60HiDPI = DisplayConfiguration(width: 1920, height: 1080, refreshRate: 60, hidpiEnabled: true)

    /// 1440p at 60Hz
    static let qhd60 = DisplayConfiguration(width: 2560, height: 1440, refreshRate: 60)

    /// 4K at 60Hz
    static let uhd60 = DisplayConfiguration(width: 3840, height: 2160, refreshRate: 60)

    /// 1080p at 120Hz
    static let fhd120 = DisplayConfiguration(width: 1920, height: 1080, refreshRate: 120)
}
