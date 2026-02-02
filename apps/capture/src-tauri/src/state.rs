use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::Instant;
use tokio::sync::Mutex;

use serialwarp_capture::{CaptureConfig, CaptureStream};
use serialwarp_encode::{Encoder, EncoderConfig};
use serialwarp_transport::UsbTransport;
use serialwarp_vdisp::{VirtualDisplay, VirtualDisplayConfig};

/// Display information for the UI
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DisplayInfo {
    pub id: u32,
    pub name: String,
    pub width: u32,
    pub height: u32,
    pub is_main: bool,
}

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
    Connecting,
    Connected,
    Streaming,
    Error,
}

/// Streaming statistics
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct StreamStats {
    pub fps: f64,
    pub bitrate_bps: u64,
    pub frames_captured: u64,
    pub frames_encoded: u64,
    pub frames_sent: u64,
    pub frames_dropped: u64,
    pub elapsed_seconds: f64,
}

/// Stream configuration from UI
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StreamConfig {
    pub width: u32,
    pub height: u32,
    pub fps: u32,
    pub bitrate_mbps: u32,
    pub hidpi: bool,
}

impl Default for StreamConfig {
    fn default() -> Self {
        Self {
            width: 1920,
            height: 1080,
            fps: 60,
            bitrate_mbps: 20,
            hidpi: false,
        }
    }
}

/// Debug information for troubleshooting
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct DebugInfo {
    pub connected_devices: Vec<UsbDeviceInfo>,
    pub supported_devices: Vec<UsbDeviceInfo>,
    pub last_error: Option<String>,
}

/// Application settings (persisted)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppSettings {
    pub default_resolution: String,
    pub default_fps: u32,
    pub default_bitrate_mbps: u32,
    pub auto_connect: bool,
    pub preview_enabled: bool,
    pub preview_quality: u32,
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            default_resolution: "1920x1080".to_string(),
            default_fps: 60,
            default_bitrate_mbps: 20,
            auto_connect: false,
            preview_enabled: true,
            preview_quality: 50,
        }
    }
}

/// Internal streaming state
#[derive(Default)]
pub struct StreamingState {
    pub capture_stream: Option<CaptureStream>,
    pub encoder: Option<Encoder>,
    pub start_time: Option<Instant>,
}

/// Main application state
pub struct AppState {
    pub virtual_display: Mutex<Option<VirtualDisplay>>,
    pub transport: Mutex<Option<UsbTransport>>,
    pub streaming: Mutex<StreamingState>,
    pub connection_status: Mutex<ConnectionStatus>,
    pub settings: Mutex<AppSettings>,
    pub current_config: Mutex<StreamConfig>,
    pub last_error: Mutex<Option<String>>,

    // Atomic counters for stats
    pub frames_captured: AtomicU64,
    pub frames_encoded: AtomicU64,
    pub frames_sent: AtomicU64,
    pub frames_dropped: AtomicU64,
    pub is_streaming: AtomicBool,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            virtual_display: Mutex::new(None),
            transport: Mutex::new(None),
            streaming: Mutex::new(StreamingState::default()),
            connection_status: Mutex::new(ConnectionStatus::Disconnected),
            settings: Mutex::new(AppSettings::default()),
            current_config: Mutex::new(StreamConfig::default()),
            last_error: Mutex::new(None),
            frames_captured: AtomicU64::new(0),
            frames_encoded: AtomicU64::new(0),
            frames_sent: AtomicU64::new(0),
            frames_dropped: AtomicU64::new(0),
            is_streaming: AtomicBool::new(false),
        }
    }
}

impl AppState {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn reset_stats(&self) {
        self.frames_captured.store(0, Ordering::SeqCst);
        self.frames_encoded.store(0, Ordering::SeqCst);
        self.frames_sent.store(0, Ordering::SeqCst);
        self.frames_dropped.store(0, Ordering::SeqCst);
    }

    pub fn increment_captured(&self) -> u64 {
        self.frames_captured.fetch_add(1, Ordering::SeqCst)
    }

    pub fn increment_encoded(&self) -> u64 {
        self.frames_encoded.fetch_add(1, Ordering::SeqCst)
    }

    pub fn increment_sent(&self) -> u64 {
        self.frames_sent.fetch_add(1, Ordering::SeqCst)
    }

    pub fn increment_dropped(&self) -> u64 {
        self.frames_dropped.fetch_add(1, Ordering::SeqCst)
    }
}

/// Virtual display config helper
impl StreamConfig {
    pub fn to_virtual_display_config(&self) -> VirtualDisplayConfig {
        VirtualDisplayConfig {
            name: "SerialWarp".to_string(),
            max_width: self.width,
            max_height: self.height,
            refresh_rate: self.fps,
            hidpi: self.hidpi,
        }
    }

    pub fn to_capture_config(&self, display_id: u32) -> CaptureConfig {
        CaptureConfig {
            display_id,
            width: self.width,
            height: self.height,
            fps: self.fps,
        }
    }

    pub fn to_encoder_config(&self) -> EncoderConfig {
        EncoderConfig {
            width: self.width,
            height: self.height,
            fps: self.fps,
            bitrate_bps: self.bitrate_mbps * 1_000_000,
            keyframe_interval: self.fps, // 1 second GOP
            low_latency: true,
        }
    }
}
