import Foundation
import CoreGraphics

/// Manager for creating and controlling virtual displays using the private CGVirtualDisplay API
/// Requires macOS 14+ (Sonoma)
@MainActor
final class VirtualDisplayManager: ObservableObject {

    /// Shared instance
    static let shared = VirtualDisplayManager()

    /// The virtual display object (CGVirtualDisplay, private API)
    private var virtualDisplay: AnyObject?

    /// The display ID of the created virtual display
    @Published private(set) var displayId: CGDirectDisplayID?

    /// Current configuration
    @Published private(set) var configuration: DisplayConfiguration?

    /// Whether a virtual display is currently active
    var isActive: Bool {
        displayId != nil
    }

    private init() {}

    /// Create a virtual display with the given configuration
    /// - Parameter config: Display configuration
    /// - Returns: The display ID of the created display
    /// - Throws: SerialWarpError if creation fails
    @discardableResult
    func create(config: DisplayConfiguration) throws -> CGDirectDisplayID {
        // Destroy any existing display first
        destroy()

        // Get the private CGVirtualDisplay classes via Objective-C runtime
        guard let descriptorClass = NSClassFromString("CGVirtualDisplayDescriptor"),
              let modeClass = NSClassFromString("CGVirtualDisplayMode"),
              let settingsClass = NSClassFromString("CGVirtualDisplaySettings"),
              let displayClass = NSClassFromString("CGVirtualDisplay") else {
            throw SerialWarpError.virtualDisplayNotSupported
        }

        // Create descriptor
        let descriptor = (descriptorClass as! NSObject.Type).init()
        descriptor.setValue(config.name, forKey: "name")
        descriptor.setValue(NSNumber(value: config.serialNumber), forKey: "serialNum")
        descriptor.setValue(NSNumber(value: 1), forKey: "productID")
        descriptor.setValue(NSNumber(value: 0xA027), forKey: "vendorID") // Apple virtual vendor

        // Set display size in mm (arbitrary, roughly matches a 24" display)
        descriptor.setValue(NSNumber(value: 527), forKey: "sizeInMillimeters.width")
        descriptor.setValue(NSNumber(value: 296), forKey: "sizeInMillimeters.height")

        // Create display mode
        let mode = (modeClass as! NSObject.Type).init()
        mode.setValue(NSNumber(value: config.modeWidth), forKey: "width")
        mode.setValue(NSNumber(value: config.modeHeight), forKey: "height")
        mode.setValue(NSNumber(value: Double(config.refreshRate)), forKey: "refreshRate")

        // Set modes array
        descriptor.setValue([mode], forKey: "modes")

        // Create settings
        let settings = (settingsClass as! NSObject.Type).init()
        if config.hidpiEnabled {
            settings.setValue(true, forKey: "hiDPI")
        }

        // Create the virtual display
        // The proper initializer is initWithDescriptor:, but we need to use perform selector
        let initSelector = NSSelectorFromString("initWithDescriptor:")

        guard let displayInstance = (displayClass as! NSObject.Type).alloc() as? NSObject else {
            throw SerialWarpError.virtualDisplayCreationFailed
        }

        // Use NSInvocation-style call via perform
        let display = displayInstance.perform(initSelector, with: descriptor)?.takeUnretainedValue() as? NSObject

        guard let display = display else {
            throw SerialWarpError.virtualDisplayCreationFailed
        }

        // Apply settings
        let applySettingsSelector = NSSelectorFromString("applySettings:")
        _ = display.perform(applySettingsSelector, with: settings)

        // Get display ID
        guard let displayIdValue = display.value(forKey: "displayID") as? UInt32, displayIdValue != 0 else {
            throw SerialWarpError.virtualDisplayCreationFailed
        }

        virtualDisplay = display
        displayId = displayIdValue
        configuration = config

        print("[VirtualDisplay] Created display \(displayIdValue) with config: \(config.resolutionString)")

        return displayIdValue
    }

    /// Destroy the virtual display
    func destroy() {
        guard virtualDisplay != nil else { return }

        // The display is destroyed when we release the reference
        virtualDisplay = nil
        displayId = nil
        configuration = nil

        print("[VirtualDisplay] Display destroyed")
    }

    /// Get list of all active displays
    static func getActiveDisplays() -> [CGDirectDisplayID] {
        var displayCount: UInt32 = 0

        // Get display count
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success else {
            return []
        }

        guard displayCount > 0 else { return [] }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetActiveDisplayList(displayCount, &displays, &displayCount) == .success else {
            return []
        }

        return displays
    }

    /// Check if a display ID corresponds to the virtual display
    func isVirtualDisplay(_ id: CGDirectDisplayID) -> Bool {
        displayId == id
    }
}

// MARK: - Display Info Helper

/// Information about a display
struct DisplayInfo: Identifiable, Sendable {
    let id: CGDirectDisplayID
    let name: String
    let width: UInt32
    let height: UInt32
    let refreshRate: Double
    let isMain: Bool
    let isVirtual: Bool

    /// Get information for a display
    static func forDisplay(_ displayId: CGDirectDisplayID, isVirtual: Bool = false) -> DisplayInfo {
        let bounds = CGDisplayBounds(displayId)
        let mode = CGDisplayCopyDisplayMode(displayId)
        let refreshRate = mode?.refreshRate ?? 60.0

        return DisplayInfo(
            id: displayId,
            name: displayName(for: displayId) ?? "Display \(displayId)",
            width: UInt32(bounds.width),
            height: UInt32(bounds.height),
            refreshRate: refreshRate,
            isMain: CGDisplayIsMain(displayId) != 0,
            isVirtual: isVirtual
        )
    }

    /// Get display name from IOKit
    private static func displayName(for displayId: CGDirectDisplayID) -> String? {
        // This would need IOKit to get the actual display name
        // For now, return a generic name
        if CGDisplayIsMain(displayId) != 0 {
            return "Main Display"
        }
        return nil
    }
}
