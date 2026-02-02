//! serialwarp-capture - macOS screen capture using ScreenCaptureKit
//!
//! This crate provides screen capture functionality for macOS using
//! the ScreenCaptureKit framework via screencapturekit-rs bindings.

#![cfg(target_os = "macos")]

use screencapturekit::cv::CVPixelBufferLockFlags;
use screencapturekit::prelude::*;
use screencapturekit::stream::configuration::PixelFormat;
use serialwarp_core::{CaptureError, FrameMetadata};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use tokio::sync::mpsc;
use tracing::{debug, error, info, warn};

/// Capture configuration
#[derive(Debug, Clone)]
pub struct CaptureConfig {
    /// Display ID to capture (CGDirectDisplayID)
    pub display_id: u32,
    /// Capture width in pixels
    pub width: u32,
    /// Capture height in pixels
    pub height: u32,
    /// Target frames per second
    pub fps: u32,
}

impl Default for CaptureConfig {
    fn default() -> Self {
        Self {
            display_id: 0,
            width: 1920,
            height: 1080,
            fps: 60,
        }
    }
}

/// A captured frame with its pixel buffer data
pub struct CapturedFrame {
    /// Frame metadata
    pub metadata: FrameMetadata,
    /// Raw pixel data in BGRA format
    pub pixel_data: Vec<u8>,
    /// Frame width
    pub width: u32,
    /// Frame height
    pub height: u32,
}

/// Internal frame handler that implements SCStreamOutputTrait
struct FrameHandler {
    sender: mpsc::Sender<CapturedFrame>,
    frame_count: Arc<AtomicU64>,
    running: Arc<AtomicBool>,
    width: u32,
    height: u32,
}

impl SCStreamOutputTrait for FrameHandler {
    fn did_output_sample_buffer(&self, sample: CMSampleBuffer, of_type: SCStreamOutputType) {
        if !matches!(of_type, SCStreamOutputType::Screen) {
            return;
        }

        if !self.running.load(Ordering::SeqCst) {
            return;
        }

        let frame_number = self.frame_count.fetch_add(1, Ordering::SeqCst);

        // Get presentation timestamp in microseconds
        let pts = sample.presentation_timestamp();
        let pts_us = ((pts.value as f64 / pts.timescale as f64) * 1_000_000.0) as u64;

        // Extract pixel data from the sample buffer
        let pixel_data = match sample.image_buffer() {
            Some(pixel_buffer) => {
                match pixel_buffer.lock(CVPixelBufferLockFlags::READ_ONLY) {
                    Ok(guard) => {
                        let slice = guard.as_slice();
                        slice.to_vec()
                    }
                    Err(e) => {
                        warn!("Failed to lock pixel buffer: {:?}", e);
                        return;
                    }
                }
            }
            None => {
                warn!("No image buffer in sample");
                return;
            }
        };

        // Determine if this should be a keyframe (every 30 frames for reference)
        let is_keyframe = frame_number % 30 == 0;

        let frame = CapturedFrame {
            metadata: FrameMetadata::new(frame_number, pts_us, pts_us, is_keyframe),
            pixel_data,
            width: self.width,
            height: self.height,
        };

        // Try to send the frame, drop if channel is full (backpressure)
        if self.sender.try_send(frame).is_err() {
            debug!("Frame {} dropped due to backpressure", frame_number);
        }
    }
}

/// Screen capture stream using ScreenCaptureKit
pub struct CaptureStream {
    running: Arc<AtomicBool>,
    frame_count: Arc<AtomicU64>,
    receiver: mpsc::Receiver<CapturedFrame>,
    stream: Option<SCStream>,
    config: CaptureConfig,
}

impl CaptureStream {
    /// Create a new capture stream with the given configuration
    pub async fn new(config: CaptureConfig) -> Result<Self, CaptureError> {
        info!(
            "Creating capture stream for display {} at {}x{} @ {}fps",
            config.display_id, config.width, config.height, config.fps
        );

        // Get shareable content to find available displays
        let content = SCShareableContent::get().map_err(|e| {
            CaptureError::CaptureFailed(format!("Failed to get shareable content: {:?}", e))
        })?;

        let displays = content.displays();
        if displays.is_empty() {
            return Err(CaptureError::DisplayNotFound(config.display_id));
        }

        // Find the target display by ID, or use the first one if display_id is 0
        let target_display = if config.display_id == 0 {
            displays
                .into_iter()
                .next()
                .ok_or(CaptureError::DisplayNotFound(0))?
        } else {
            displays
                .into_iter()
                .find(|d| d.display_id() == config.display_id)
                .ok_or(CaptureError::DisplayNotFound(config.display_id))?
        };

        info!(
            "Found display {}: {}x{}",
            target_display.display_id(),
            target_display.width(),
            target_display.height()
        );

        // Create content filter for the display
        let filter = SCContentFilter::create()
            .with_display(&target_display)
            .with_excluding_windows(&[])
            .build();

        // Create stream configuration
        let frame_interval = CMTime::new(1, config.fps as i32);
        let stream_config = SCStreamConfiguration::new()
            .with_width(config.width)
            .with_height(config.height)
            .with_minimum_frame_interval(&frame_interval)
            .with_pixel_format(PixelFormat::BGRA)
            .with_shows_cursor(true);

        // Create the stream
        let mut stream = SCStream::new(&filter, &stream_config);

        // Set up channel for frames
        let (sender, receiver) = mpsc::channel(8);
        let running = Arc::new(AtomicBool::new(true));
        let frame_count = Arc::new(AtomicU64::new(0));

        // Create and add the output handler
        let handler = FrameHandler {
            sender,
            frame_count: Arc::clone(&frame_count),
            running: Arc::clone(&running),
            width: config.width,
            height: config.height,
        };

        stream.add_output_handler(handler, SCStreamOutputType::Screen);

        // Start capturing
        stream.start_capture().map_err(|e| {
            CaptureError::CaptureFailed(format!("Failed to start capture: {:?}", e))
        })?;

        info!("Capture stream started successfully");

        Ok(Self {
            running,
            frame_count,
            receiver,
            stream: Some(stream),
            config,
        })
    }

    /// Get the next captured frame
    pub async fn next_frame(&mut self) -> Option<CapturedFrame> {
        self.receiver.recv().await
    }

    /// Stop the capture stream
    pub fn stop(&mut self) {
        self.running.store(false, Ordering::SeqCst);
        if let Some(ref mut stream) = self.stream {
            if let Err(e) = stream.stop_capture() {
                error!("Error stopping capture: {:?}", e);
            }
        }
        self.stream = None;
        info!("Capture stream stopped");
    }

    /// Get the number of frames captured so far
    pub fn frame_count(&self) -> u64 {
        self.frame_count.load(Ordering::SeqCst)
    }

    /// Get the capture configuration
    pub fn config(&self) -> &CaptureConfig {
        &self.config
    }
}

impl Drop for CaptureStream {
    fn drop(&mut self) {
        self.stop();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_default() {
        let config = CaptureConfig::default();
        assert_eq!(config.width, 1920);
        assert_eq!(config.height, 1080);
        assert_eq!(config.fps, 60);
    }
}
