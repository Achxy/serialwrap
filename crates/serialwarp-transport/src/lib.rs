//! serialwarp-transport - Transport layer for serialwarp
//!
//! This crate provides transport abstractions for sending and receiving
//! data between source and sink applications.

mod mock;
mod usb;

use async_trait::async_trait;
use bytes::Bytes;
use serialwarp_core::TransportError;

pub use mock::MockTransport;
pub use usb::UsbTransport;

/// Transport trait for sending and receiving data
#[async_trait]
pub trait Transport: Send + Sync {
    /// Send data to the remote endpoint
    async fn send(&self, data: Bytes) -> Result<(), TransportError>;

    /// Receive data from the remote endpoint
    async fn recv(&self) -> Result<Bytes, TransportError>;

    /// Check if the transport is still connected
    fn is_connected(&self) -> bool;

    /// Close the transport
    async fn close(&self);
}
