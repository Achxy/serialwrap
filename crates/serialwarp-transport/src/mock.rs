//! Mock transport for testing

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use async_trait::async_trait;
use bytes::Bytes;
use serialwarp_core::TransportError;
use tokio::sync::mpsc;

use crate::Transport;

/// A mock transport for testing that connects two endpoints via channels
pub struct MockTransport {
    sender: mpsc::Sender<Bytes>,
    receiver: tokio::sync::Mutex<mpsc::Receiver<Bytes>>,
    connected: Arc<AtomicBool>,
}

impl MockTransport {
    /// Create a connected pair of mock transports
    ///
    /// Data sent on one transport will be received by the other.
    pub fn pair() -> (Self, Self) {
        let (tx1, rx1) = mpsc::channel(64);
        let (tx2, rx2) = mpsc::channel(64);
        let connected = Arc::new(AtomicBool::new(true));

        let transport1 = MockTransport {
            sender: tx1,
            receiver: tokio::sync::Mutex::new(rx2),
            connected: Arc::clone(&connected),
        };

        let transport2 = MockTransport {
            sender: tx2,
            receiver: tokio::sync::Mutex::new(rx1),
            connected,
        };

        (transport1, transport2)
    }
}

#[async_trait]
impl Transport for MockTransport {
    async fn send(&self, data: Bytes) -> Result<(), TransportError> {
        if !self.connected.load(Ordering::SeqCst) {
            return Err(TransportError::Disconnected);
        }

        self.sender
            .send(data)
            .await
            .map_err(|_| TransportError::ChannelClosed)
    }

    async fn recv(&self) -> Result<Bytes, TransportError> {
        if !self.connected.load(Ordering::SeqCst) {
            return Err(TransportError::Disconnected);
        }

        let mut receiver = self.receiver.lock().await;
        receiver.recv().await.ok_or(TransportError::ChannelClosed)
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

    #[tokio::test]
    async fn test_pair_communication() {
        let (transport1, transport2) = MockTransport::pair();

        let data = Bytes::from_static(b"hello world");
        transport1.send(data.clone()).await.unwrap();

        let received = transport2.recv().await.unwrap();
        assert_eq!(received, data);
    }

    #[tokio::test]
    async fn test_bidirectional() {
        let (transport1, transport2) = MockTransport::pair();

        // Send from 1 to 2
        transport1
            .send(Bytes::from_static(b"from 1"))
            .await
            .unwrap();
        let received = transport2.recv().await.unwrap();
        assert_eq!(received, Bytes::from_static(b"from 1"));

        // Send from 2 to 1
        transport2
            .send(Bytes::from_static(b"from 2"))
            .await
            .unwrap();
        let received = transport1.recv().await.unwrap();
        assert_eq!(received, Bytes::from_static(b"from 2"));
    }

    #[tokio::test]
    async fn test_close() {
        let (transport1, transport2) = MockTransport::pair();

        assert!(transport1.is_connected());
        assert!(transport2.is_connected());

        transport1.close().await;

        assert!(!transport1.is_connected());
        assert!(!transport2.is_connected()); // Both share connected flag

        // Sending after close should fail
        let result = transport1.send(Bytes::from_static(b"test")).await;
        assert!(matches!(result, Err(TransportError::Disconnected)));
    }

    #[tokio::test]
    async fn test_multiple_messages() {
        let (transport1, transport2) = MockTransport::pair();

        for i in 0..10 {
            let data = Bytes::from(format!("message {}", i));
            transport1.send(data.clone()).await.unwrap();
        }

        for i in 0..10 {
            let received = transport2.recv().await.unwrap();
            assert_eq!(received, Bytes::from(format!("message {}", i)));
        }
    }
}
