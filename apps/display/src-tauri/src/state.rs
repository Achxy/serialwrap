use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::Instant;
use tokio::sync::Mutex;

use serialwarp_decode::Decoder;
use serialwarp_transport::UsbTransport;

/// USB device information for the UI
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UsbDeviceInfo {
    pub name: String,
    pub vendor_id: u16,
    pub product_id: u16,
}

/// Connection status
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum ConnectionStatus {
    Disconnected,
    Waiting,
    Connecting,
    Connected,
    Receiving,
    Error,
}

/// Negotiated stream parameters from handshake
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct NegotiatedParams {
    pub width: u32,
    pub height: u32,
    pub fps: u32,
    pub bitrate_bps: u32,
}

/// Display statistics
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct DisplayStats {
    pub fps: f64,
    pub frames_received: u64,
    pub frames_decoded: u64,
    pub frames_displayed: u64,
    pub frames_dropped: u64,
    pub decode_time_ms: f64,
    pub latency_ms: f64,
    pub elapsed_seconds: f64,
}

/// Application settings (persisted)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppSettings {
    pub auto_fullscreen: bool,
    pub vsync: bool,
    pub max_width: u32,
    pub max_height: u32,
    pub max_credits: u16,
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            auto_fullscreen: false,
            vsync: true,
            max_width: 1920,
            max_height: 1080,
            max_credits: 4,
        }
    }
}

/// Internal receiving state - stored separately to avoid Send/Sync issues
pub struct ReceivingState {
    pub decoder: Option<Decoder>,
    pub start_time: Option<Instant>,
    pub last_decode_time_us: u64,
    pub params: Option<NegotiatedParams>,
}

impl Default for ReceivingState {
    fn default() -> Self {
        Self {
            decoder: None,
            start_time: None,
            last_decode_time_us: 0,
            params: None,
        }
    }
}

// Unsafe impl because we manage thread safety ourselves via Mutex
unsafe impl Send for ReceivingState {}
unsafe impl Sync for ReceivingState {}

/// Transport wrapper for thread safety
pub struct TransportWrapper(pub Option<UsbTransport>);

unsafe impl Send for TransportWrapper {}
unsafe impl Sync for TransportWrapper {}

/// Main application state
pub struct AppState {
    pub transport: Mutex<TransportWrapper>,
    pub receiving: Mutex<ReceivingState>,
    pub connection_status: Mutex<ConnectionStatus>,
    pub settings: Mutex<AppSettings>,
    pub is_fullscreen: AtomicBool,
    pub is_receiving: AtomicBool,

    // Atomic counters for stats
    pub frames_received: AtomicU64,
    pub frames_decoded: AtomicU64,
    pub frames_displayed: AtomicU64,
    pub frames_dropped: AtomicU64,
    pub total_decode_time_us: AtomicU64,
    pub total_latency_us: AtomicU64,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            transport: Mutex::new(TransportWrapper(None)),
            receiving: Mutex::new(ReceivingState::default()),
            connection_status: Mutex::new(ConnectionStatus::Disconnected),
            settings: Mutex::new(AppSettings::default()),
            is_fullscreen: AtomicBool::new(false),
            is_receiving: AtomicBool::new(false),
            frames_received: AtomicU64::new(0),
            frames_decoded: AtomicU64::new(0),
            frames_displayed: AtomicU64::new(0),
            frames_dropped: AtomicU64::new(0),
            total_decode_time_us: AtomicU64::new(0),
            total_latency_us: AtomicU64::new(0),
        }
    }
}

impl AppState {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn reset_stats(&self) {
        self.frames_received.store(0, Ordering::SeqCst);
        self.frames_decoded.store(0, Ordering::SeqCst);
        self.frames_displayed.store(0, Ordering::SeqCst);
        self.frames_dropped.store(0, Ordering::SeqCst);
        self.total_decode_time_us.store(0, Ordering::SeqCst);
        self.total_latency_us.store(0, Ordering::SeqCst);
    }

    pub fn add_decode_time(&self, time_us: u64) {
        self.total_decode_time_us.fetch_add(time_us, Ordering::SeqCst);
    }

    pub fn add_latency(&self, latency_us: u64) {
        self.total_latency_us.fetch_add(latency_us, Ordering::SeqCst);
    }

    pub fn get_avg_decode_time_ms(&self) -> f64 {
        let decoded = self.frames_decoded.load(Ordering::SeqCst);
        if decoded > 0 {
            self.total_decode_time_us.load(Ordering::SeqCst) as f64 / decoded as f64 / 1000.0
        } else {
            0.0
        }
    }

    pub fn get_avg_latency_ms(&self) -> f64 {
        let decoded = self.frames_decoded.load(Ordering::SeqCst);
        if decoded > 0 {
            self.total_latency_us.load(Ordering::SeqCst) as f64 / decoded as f64 / 1000.0
        } else {
            0.0
        }
    }
}
