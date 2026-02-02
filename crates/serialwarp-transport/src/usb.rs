//! USB transport implementation using nusb

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use async_trait::async_trait;
use bytes::Bytes;
use nusb::transfer::RequestBuffer;
use nusb::Device;
use serialwarp_core::TransportError;
use tokio::sync::Mutex;

use crate::Transport;

/// Supported USB link cable chips
const SUPPORTED_DEVICES: &[(u16, u16, &str)] = &[
    (0x067B, 0x27A1, "Prolific PL27A1"),
    (0x05E3, 0x0751, "Genesys GL3523"),
    (0x2109, 0x0822, "VIA VL822"),
];

/// USB OUT endpoint address
const ENDPOINT_OUT: u8 = 0x01;

/// USB IN endpoint address
const ENDPOINT_IN: u8 = 0x81;

/// Transfer buffer size (64KB)
const TRANSFER_SIZE: usize = 65536;

/// USB timeout in milliseconds
const TIMEOUT_MS: u64 = 5000;

/// USB transport for link cable communication
pub struct UsbTransport {
    interface: Arc<nusb::Interface>,
    connected: Arc<AtomicBool>,
    #[allow(dead_code)]
    recv_buffer: Mutex<Vec<u8>>,
}

impl UsbTransport {
    /// Open a USB transport, auto-detecting the first supported link cable
    pub async fn open() -> Result<Self, TransportError> {
        let device = Self::find_device()?;
        Self::from_device(device).await
    }

    /// Find the first supported USB device
    fn find_device() -> Result<Device, TransportError> {
        for device_info in
            nusb::list_devices().map_err(|e| TransportError::UsbError(e.to_string()))?
        {
            let vid = device_info.vendor_id();
            let pid = device_info.product_id();

            for &(supported_vid, supported_pid, name) in SUPPORTED_DEVICES {
                if vid == supported_vid && pid == supported_pid {
                    tracing::info!("Found {} (VID: 0x{:04X}, PID: 0x{:04X})", name, vid, pid);
                    return device_info
                        .open()
                        .map_err(|e| TransportError::UsbError(e.to_string()));
                }
            }
        }

        Err(TransportError::DeviceNotFound)
    }

    /// Create transport from an opened USB device
    async fn from_device(device: Device) -> Result<Self, TransportError> {
        // Find the right interface with bulk endpoints
        // Link cables typically use interface 0
        let interface_num = 0;

        let interface = device
            .claim_interface(interface_num)
            .map_err(|e| TransportError::UsbError(e.to_string()))?;

        Ok(Self {
            interface: Arc::new(interface),
            connected: Arc::new(AtomicBool::new(true)),
            recv_buffer: Mutex::new(Vec::with_capacity(TRANSFER_SIZE)),
        })
    }
}

#[async_trait]
impl Transport for UsbTransport {
    async fn send(&self, data: Bytes) -> Result<(), TransportError> {
        if !self.connected.load(Ordering::SeqCst) {
            return Err(TransportError::Disconnected);
        }

        let completion = self.interface.bulk_out(ENDPOINT_OUT, data.to_vec()).await;

        match completion.status {
            Ok(_) => Ok(()),
            Err(e) => {
                self.connected.store(false, Ordering::SeqCst);
                Err(TransportError::UsbError(e.to_string()))
            }
        }
    }

    async fn recv(&self) -> Result<Bytes, TransportError> {
        if !self.connected.load(Ordering::SeqCst) {
            return Err(TransportError::Disconnected);
        }

        let request = RequestBuffer::new(TRANSFER_SIZE);

        let result = tokio::time::timeout(
            Duration::from_millis(TIMEOUT_MS),
            self.interface.bulk_in(ENDPOINT_IN, request),
        )
        .await;

        match result {
            Ok(completion) => match completion.status {
                Ok(_) => Ok(Bytes::copy_from_slice(&completion.data)),
                Err(e) => {
                    self.connected.store(false, Ordering::SeqCst);
                    Err(TransportError::UsbError(e.to_string()))
                }
            },
            Err(_) => Err(TransportError::Timeout {
                duration_ms: TIMEOUT_MS,
            }),
        }
    }

    fn is_connected(&self) -> bool {
        self.connected.load(Ordering::SeqCst)
    }

    async fn close(&self) {
        self.connected.store(false, Ordering::SeqCst);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_supported_devices() {
        assert_eq!(SUPPORTED_DEVICES.len(), 3);
        assert!(SUPPORTED_DEVICES
            .iter()
            .any(|(vid, pid, _)| *vid == 0x067B && *pid == 0x27A1));
    }
}
