import Foundation
import IOKit
import IOKit.usb

/// USB device manager for discovering and monitoring USB devices
@MainActor
final class USBDeviceManager: ObservableObject {

    /// Shared instance
    static let shared = USBDeviceManager()

    /// Currently connected supported devices
    @Published private(set) var connectedDevices: [USBDeviceInfo] = []

    /// Notification port for device notifications
    private var notificationPort: IONotificationPortRef?

    /// Iterator for device added notifications
    private var addedIterator: io_iterator_t = 0

    /// Iterator for device removed notifications
    private var removedIterator: io_iterator_t = 0

    /// Run loop source for notifications
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    /// Start monitoring for USB devices
    func startMonitoring() {
        // Create notification port
        notificationPort = IONotificationPortCreate(kIOMainPortDefault)

        guard let port = notificationPort else {
            print("[USB] Failed to create notification port")
            return
        }

        // Get run loop source
        runLoopSource = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }

        // Register for device added notifications for each supported device
        for device in USBConstants.supportedDevices {
            registerForDeviceNotifications(vendorId: device.vendorId, productId: device.productId)
        }

        // Initial scan
        scanForDevices()
    }

    /// Stop monitoring for USB devices
    func stopMonitoring() {
        if addedIterator != 0 {
            IOObjectRelease(addedIterator)
            addedIterator = 0
        }

        if removedIterator != 0 {
            IOObjectRelease(removedIterator)
            removedIterator = 0
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = nil
        }

        if let port = notificationPort {
            IONotificationPortDestroy(port)
            notificationPort = nil
        }
    }

    /// Register for device notifications
    private func registerForDeviceNotifications(vendorId: UInt16, productId: UInt16) {
        guard let port = notificationPort else { return }

        var matchingDict = IOServiceMatching(kIOUSBDeviceClassName) as NSMutableDictionary?
        matchingDict?[kUSBVendorID] = vendorId
        matchingDict?[kUSBProductID] = productId

        guard let matching = matchingDict else { return }

        // We need to retain the dictionary for both calls
        let matchingAdded = matching.mutableCopy() as! CFMutableDictionary
        let matchingRemoved = matching.mutableCopy() as! CFMutableDictionary

        // Register for device added
        var addIterator: io_iterator_t = 0
        let addResult = IOServiceAddMatchingNotification(
            port,
            kIOFirstMatchNotification,
            matchingAdded,
            { (refcon, iterator) in
                guard let refcon = refcon else { return }
                let manager = Unmanaged<USBDeviceManager>.fromOpaque(refcon).takeUnretainedValue()
                Task { @MainActor in
                    manager.handleDevicesAdded(iterator: iterator)
                }
            },
            Unmanaged.passUnretained(self).toOpaque(),
            &addIterator
        )

        if addResult == KERN_SUCCESS {
            // Arm the notification by iterating
            handleDevicesAdded(iterator: addIterator)
        }

        // Register for device removed
        var removeIterator: io_iterator_t = 0
        let removeResult = IOServiceAddMatchingNotification(
            port,
            kIOTerminatedNotification,
            matchingRemoved,
            { (refcon, iterator) in
                guard let refcon = refcon else { return }
                let manager = Unmanaged<USBDeviceManager>.fromOpaque(refcon).takeUnretainedValue()
                Task { @MainActor in
                    manager.handleDevicesRemoved(iterator: iterator)
                }
            },
            Unmanaged.passUnretained(self).toOpaque(),
            &removeIterator
        )

        if removeResult == KERN_SUCCESS {
            // Arm the notification by iterating
            handleDevicesRemoved(iterator: removeIterator)
        }
    }

    /// Handle devices being added
    private func handleDevicesAdded(iterator: io_iterator_t) {
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }

            if let deviceInfo = getDeviceInfo(service: service) {
                if !connectedDevices.contains(where: { $0.id == deviceInfo.id }) {
                    connectedDevices.append(deviceInfo)
                    print("[USB] Device connected: \(deviceInfo.name)")
                }
            }

            service = IOIteratorNext(iterator)
        }
    }

    /// Handle devices being removed
    private func handleDevicesRemoved(iterator: io_iterator_t) {
        // Just consume the iterator to arm the notification
        var service = IOIteratorNext(iterator)
        while service != 0 {
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        // Rescan to update the list
        scanForDevices()
    }

    /// Scan for currently connected devices
    func scanForDevices() {
        var foundDevices: [USBDeviceInfo] = []

        for device in USBConstants.supportedDevices {
            var matchingDict = IOServiceMatching(kIOUSBDeviceClassName) as NSMutableDictionary?
            matchingDict?[kUSBVendorID] = device.vendorId
            matchingDict?[kUSBProductID] = device.productId

            guard let matching = matchingDict else { continue }

            var iterator: io_iterator_t = 0
            let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)

            guard result == KERN_SUCCESS else { continue }

            defer { IOObjectRelease(iterator) }

            var service = IOIteratorNext(iterator)
            while service != 0 {
                defer { IOObjectRelease(service) }

                let deviceInfo = USBDeviceInfo(
                    vendorId: device.vendorId,
                    productId: device.productId,
                    name: device.name
                )
                foundDevices.append(deviceInfo)

                service = IOIteratorNext(iterator)
            }
        }

        connectedDevices = foundDevices
    }

    /// Get device info from a service
    private func getDeviceInfo(service: io_service_t) -> USBDeviceInfo? {
        var properties: Unmanaged<CFMutableDictionary>?
        let kr = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)

        guard kr == KERN_SUCCESS,
              let props = properties?.takeRetainedValue() as? [String: Any],
              let vendorId = props[kUSBVendorID] as? UInt16,
              let productId = props[kUSBProductID] as? UInt16,
              let deviceData = USBConstants.findDevice(vendorId: vendorId, productId: productId) else {
            return nil
        }

        return USBDeviceInfo(
            vendorId: deviceData.vendorId,
            productId: deviceData.productId,
            name: deviceData.name
        )
    }
}

// MARK: - Private Constants

private let kUSBVendorID = "idVendor"
private let kUSBProductID = "idProduct"
