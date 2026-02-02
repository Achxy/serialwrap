//! USB device definitions for supported link cables

/// USB device identification
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct UsbDeviceId {
    pub vendor_id: u16,
    pub product_id: u16,
    pub name: &'static str,
}

impl UsbDeviceId {
    pub const fn new(vendor_id: u16, product_id: u16, name: &'static str) -> Self {
        Self {
            vendor_id,
            product_id,
            name,
        }
    }
}

/// Supported USB link cable devices
pub const SUPPORTED_USB_DEVICES: &[UsbDeviceId] = &[
    UsbDeviceId::new(0x067B, 0x27A1, "Prolific PL27A1"),
    UsbDeviceId::new(0x05E3, 0x0751, "Genesys GL3523"),
    UsbDeviceId::new(0x2109, 0x0822, "VIA VL822"),
];

/// Check if a USB device with the given VID/PID is supported
pub fn is_supported_device(vendor_id: u16, product_id: u16) -> bool {
    SUPPORTED_USB_DEVICES
        .iter()
        .any(|d| d.vendor_id == vendor_id && d.product_id == product_id)
}

/// Find a supported device by VID/PID
pub fn find_supported_device(vendor_id: u16, product_id: u16) -> Option<&'static UsbDeviceId> {
    SUPPORTED_USB_DEVICES
        .iter()
        .find(|d| d.vendor_id == vendor_id && d.product_id == product_id)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_supported_device() {
        assert!(is_supported_device(0x067B, 0x27A1));
        assert!(is_supported_device(0x05E3, 0x0751));
        assert!(is_supported_device(0x2109, 0x0822));
        assert!(!is_supported_device(0x0000, 0x0000));
    }

    #[test]
    fn test_find_supported_device() {
        let device = find_supported_device(0x067B, 0x27A1).unwrap();
        assert_eq!(device.name, "Prolific PL27A1");
    }
}
