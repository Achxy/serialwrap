import Foundation
import IOKit
import IOKit.usb

/// USB transport implementation using IOKit
actor USBTransport: Transport {

    /// USB device reference
    private var deviceInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>?>?

    /// USB interface reference
    private var interfaceInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBInterfaceInterface>?>?

    /// Whether the transport is connected
    private(set) var isConnected: Bool = false

    /// Device information
    let deviceInfo: USBDeviceInfo

    /// Create a USB transport with a connected device
    private init(
        deviceInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>?>?,
        interfaceInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBInterfaceInterface>?>?,
        deviceInfo: USBDeviceInfo
    ) {
        self.deviceInterface = deviceInterface
        self.interfaceInterface = interfaceInterface
        self.deviceInfo = deviceInfo
        self.isConnected = true
    }

    deinit {
        // Note: cleanup is async so we can't call close() here
        // Caller should call close() before releasing
    }

    // MARK: - Static Factory

    /// Open a connection to a supported USB device
    static func open() async throws -> USBTransport {
        // Create matching dictionary for USB devices
        var matchingDict: NSMutableDictionary?
        matchingDict = IOServiceMatching(kIOUSBDeviceClassName) as NSMutableDictionary?

        guard let matching = matchingDict else {
            throw SerialWarpError.deviceNotFound
        }

        // Get iterator for all USB devices
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)

        guard result == KERN_SUCCESS else {
            throw SerialWarpError.usbError("Failed to get USB device list: \(result)")
        }

        defer { IOObjectRelease(iterator) }

        // Find a supported device
        var service: io_service_t = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }

            // Get device properties
            var properties: Unmanaged<CFMutableDictionary>?
            let kr = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)

            if kr == KERN_SUCCESS, let props = properties?.takeRetainedValue() as? [String: Any] {
                if let vendorId = props[kUSBVendorID] as? UInt16,
                   let productId = props[kUSBProductID] as? UInt16,
                   let deviceData = USBConstants.findDevice(vendorId: vendorId, productId: productId) {

                    print("[USB] Found \(deviceData.name) (VID: 0x\(String(vendorId, radix: 16)), PID: 0x\(String(productId, radix: 16)))")

                    // Try to open this device
                    if let transport = try? await openDevice(service: service, deviceData: deviceData) {
                        return transport
                    }
                }
            }

            service = IOIteratorNext(iterator)
        }

        throw SerialWarpError.deviceNotFound
    }

    /// Open a specific USB device
    private static func openDevice(
        service: io_service_t,
        deviceData: (vendorId: UInt16, productId: UInt16, name: String)
    ) async throws -> USBTransport {
        // Get plugin interface
        var pluginInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0

        let kr = IOCreatePlugInInterfaceForService(
            service,
            kIOUSBDeviceUserClientTypeID,
            kIOCFPlugInInterfaceID,
            &pluginInterface,
            &score
        )

        guard kr == KERN_SUCCESS, let plugin = pluginInterface else {
            throw SerialWarpError.usbError("Failed to create plugin interface: \(kr)")
        }

        defer {
            _ = plugin.pointee?.pointee.Release(plugin)
        }

        // Get device interface
        var deviceInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>?>?

        let queryResult = withUnsafeMutablePointer(to: &deviceInterface) { devicePtr in
            plugin.pointee?.pointee.QueryInterface(
                plugin,
                CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID),
                UnsafeMutableRawPointer(devicePtr).assumingMemoryBound(to: LPVOID?.self)
            )
        }

        guard queryResult == S_OK, let device = deviceInterface else {
            throw SerialWarpError.usbError("Failed to get device interface")
        }

        // Open device
        let openResult = device.pointee?.pointee.USBDeviceOpen(device)
        guard openResult == KERN_SUCCESS else {
            _ = device.pointee?.pointee.Release(device)
            throw SerialWarpError.usbError("Failed to open device: \(openResult ?? -1)")
        }

        // Configure device
        let configResult = device.pointee?.pointee.SetConfiguration(device, 1)
        guard configResult == KERN_SUCCESS else {
            _ = device.pointee?.pointee.USBDeviceClose(device)
            _ = device.pointee?.pointee.Release(device)
            throw SerialWarpError.usbError("Failed to configure device: \(configResult ?? -1)")
        }

        // Find and claim interface with bulk endpoints
        guard let interfaceInterface = try findAndClaimInterface(device: device) else {
            _ = device.pointee?.pointee.USBDeviceClose(device)
            _ = device.pointee?.pointee.Release(device)
            throw SerialWarpError.usbError("Failed to find interface with bulk endpoints")
        }

        let deviceInfo = USBDeviceInfo(
            vendorId: deviceData.vendorId,
            productId: deviceData.productId,
            name: deviceData.name
        )

        return USBTransport(
            deviceInterface: device,
            interfaceInterface: interfaceInterface,
            deviceInfo: deviceInfo
        )
    }

    /// Find and claim the USB interface with bulk endpoints
    private static func findAndClaimInterface(
        device: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>?>
    ) throws -> UnsafeMutablePointer<UnsafeMutablePointer<IOUSBInterfaceInterface>?>? {
        // Create interface request
        var request = IOUSBFindInterfaceRequest(
            bInterfaceClass: UInt16(kIOUSBFindInterfaceDontCare),
            bInterfaceSubClass: UInt16(kIOUSBFindInterfaceDontCare),
            bInterfaceProtocol: UInt16(kIOUSBFindInterfaceDontCare),
            bAlternateSetting: UInt16(kIOUSBFindInterfaceDontCare)
        )

        var iterator: io_iterator_t = 0
        let kr = device.pointee?.pointee.CreateInterfaceIterator(device, &request, &iterator)

        guard kr == KERN_SUCCESS else {
            throw SerialWarpError.usbError("Failed to create interface iterator: \(kr ?? -1)")
        }

        defer { IOObjectRelease(iterator) }

        // Iterate through interfaces
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }

            // Get plugin interface for this interface
            var pluginInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
            var score: Int32 = 0

            let kr = IOCreatePlugInInterfaceForService(
                service,
                kIOUSBInterfaceUserClientTypeID,
                kIOCFPlugInInterfaceID,
                &pluginInterface,
                &score
            )

            guard kr == KERN_SUCCESS, let plugin = pluginInterface else {
                service = IOIteratorNext(iterator)
                continue
            }

            defer { _ = plugin.pointee?.pointee.Release(plugin) }

            // Get interface interface
            var interfaceInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBInterfaceInterface>?>?

            let queryResult = withUnsafeMutablePointer(to: &interfaceInterface) { interfacePtr in
                plugin.pointee?.pointee.QueryInterface(
                    plugin,
                    CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID),
                    UnsafeMutableRawPointer(interfacePtr).assumingMemoryBound(to: LPVOID?.self)
                )
            }

            guard queryResult == S_OK, let interface = interfaceInterface else {
                service = IOIteratorNext(iterator)
                continue
            }

            // Open interface
            let openResult = interface.pointee?.pointee.USBInterfaceOpen(interface)
            guard openResult == KERN_SUCCESS else {
                _ = interface.pointee?.pointee.Release(interface)
                service = IOIteratorNext(iterator)
                continue
            }

            // Check for bulk endpoints
            var numEndpoints: UInt8 = 0
            _ = interface.pointee?.pointee.GetNumEndpoints(interface, &numEndpoints)

            var hasIn = false
            var hasOut = false

            for i in 1...numEndpoints {
                var direction: UInt8 = 0
                var number: UInt8 = 0
                var transferType: UInt8 = 0
                var maxPacketSize: UInt16 = 0
                var interval: UInt8 = 0

                let epResult = interface.pointee?.pointee.GetPipeProperties(
                    interface,
                    i,
                    &direction,
                    &number,
                    &transferType,
                    &maxPacketSize,
                    &interval
                )

                if epResult == KERN_SUCCESS && transferType == kUSBBulk {
                    if direction == kUSBIn {
                        hasIn = true
                    } else if direction == kUSBOut {
                        hasOut = true
                    }
                }
            }

            if hasIn && hasOut {
                return interface
            }

            // Not the right interface, close and release
            _ = interface.pointee?.pointee.USBInterfaceClose(interface)
            _ = interface.pointee?.pointee.Release(interface)

            service = IOIteratorNext(iterator)
        }

        return nil
    }

    // MARK: - Transport Protocol

    /// Send data to the USB device
    func send(_ data: Data) async throws {
        guard isConnected, let interface = interfaceInterface else {
            throw SerialWarpError.disconnected
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            data.withUnsafeBytes { ptr in
                let buffer = UnsafeMutableRawPointer(mutating: ptr.baseAddress!)
                let result = interface.pointee?.pointee.WritePipe(
                    interface,
                    1,  // Pipe index for OUT endpoint
                    buffer,
                    UInt32(data.count)
                )

                if result == KERN_SUCCESS {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SerialWarpError.usbError("Write failed: \(result ?? -1)"))
                }
            }
        }
    }

    /// Receive data from the USB device
    func receive() async throws -> Data {
        guard isConnected, let interface = interfaceInterface else {
            throw SerialWarpError.disconnected
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            var buffer = [UInt8](repeating: 0, count: USBConstants.bufferSize)
            var size = UInt32(buffer.count)

            let result = interface.pointee?.pointee.ReadPipe(
                interface,
                2,  // Pipe index for IN endpoint
                &buffer,
                &size
            )

            if result == KERN_SUCCESS {
                continuation.resume(returning: Data(buffer[0..<Int(size)]))
            } else {
                continuation.resume(throwing: SerialWarpError.usbError("Read failed: \(result ?? -1)"))
            }
        }
    }

    /// Close the USB transport
    func close() async {
        guard isConnected else { return }

        isConnected = false

        // Close interface
        if let interface = interfaceInterface {
            _ = interface.pointee?.pointee.USBInterfaceClose(interface)
            _ = interface.pointee?.pointee.Release(interface)
            interfaceInterface = nil
        }

        // Close device
        if let device = deviceInterface {
            _ = device.pointee?.pointee.USBDeviceClose(device)
            _ = device.pointee?.pointee.Release(device)
            deviceInterface = nil
        }
    }
}

// MARK: - IOKit Constants

private let kIOUSBDeviceUserClientTypeID = CFUUIDGetConstantUUIDWithBytes(nil,
    0x9d, 0xc7, 0xb7, 0x80, 0x9e, 0xc0, 0x11, 0xD4,
    0xa5, 0x4f, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)

private let kIOUSBInterfaceUserClientTypeID = CFUUIDGetConstantUUIDWithBytes(nil,
    0x2d, 0x97, 0x86, 0xc6, 0x9e, 0xf3, 0x11, 0xD4,
    0xad, 0x51, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)

private let kIOCFPlugInInterfaceID = CFUUIDGetConstantUUIDWithBytes(nil,
    0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4,
    0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F)

private let kIOUSBDeviceInterfaceID = CFUUIDGetConstantUUIDWithBytes(nil,
    0x5c, 0x81, 0x87, 0xd0, 0x9e, 0xf3, 0x11, 0xD4,
    0x8b, 0x45, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)

private let kIOUSBInterfaceInterfaceID = CFUUIDGetConstantUUIDWithBytes(nil,
    0x73, 0xc9, 0x7a, 0xe8, 0x9e, 0xf3, 0x11, 0xD4,
    0xb1, 0xd0, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)

private let kUSBVendorID = "idVendor"
private let kUSBProductID = "idProduct"
private let kUSBBulk: UInt8 = 2
private let kUSBIn: UInt8 = 1
private let kUSBOut: UInt8 = 0
