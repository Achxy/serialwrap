use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::time::Instant;
use tauri::{AppHandle, Emitter, State};

use serialwarp_capture::CaptureStream;
use serialwarp_core::SUPPORTED_USB_DEVICES;
use serialwarp_encode::Encoder;
use serialwarp_transport::{Transport, UsbTransport};
use serialwarp_vdisp::VirtualDisplay;

use base64::Engine as _;

use crate::state::{
    AppSettings, AppState, ConnectionStatus, DebugInfo, DisplayInfo, StreamConfig, StreamStats, UsbDeviceInfo,
};

/// List available displays on the system
#[tauri::command]
pub async fn list_displays() -> Result<Vec<DisplayInfo>, String> {
    #[cfg(target_os = "macos")]
    {
        use core_graphics::display::CGDisplay;

        let displays: Vec<DisplayInfo> = CGDisplay::active_displays()
            .map_err(|e| format!("Failed to get displays: {:?}", e))?
            .into_iter()
            .enumerate()
            .map(|(i, id)| {
                let display = CGDisplay::new(id);
                let bounds = display.bounds();
                DisplayInfo {
                    id,
                    name: format!("Display {}", i + 1),
                    width: bounds.size.width as u32,
                    height: bounds.size.height as u32,
                    is_main: display.is_main(),
                }
            })
            .collect();

        Ok(displays)
    }

    #[cfg(not(target_os = "macos"))]
    {
        Err("Display listing is only available on macOS".to_string())
    }
}

/// List connected USB devices that could be used for transport
#[tauri::command]
pub async fn list_usb_devices() -> Result<Vec<UsbDeviceInfo>, String> {
    let supported = SUPPORTED_USB_DEVICES
        .iter()
        .map(|d| UsbDeviceInfo {
            name: d.name.to_string(),
            vendor_id: d.vendor_id,
            product_id: d.product_id,
        })
        .collect();
    Ok(supported)
}

/// Connect to USB transport
#[tauri::command]
pub async fn connect_transport(state: State<'_, Arc<AppState>>) -> Result<(), String> {
    let mut status = state.connection_status.lock().await;
    *status = ConnectionStatus::Connecting;
    drop(status);

    // Store debug info about the connection attempt
    let debug_info = get_usb_debug_info();
    {
        let mut last_error = state.last_error.lock().await;
        *last_error = None;
    }

    match UsbTransport::open().await {
        Ok(transport) => {
            let mut t = state.transport.lock().await;
            *t = Some(transport);
            let mut status = state.connection_status.lock().await;
            *status = ConnectionStatus::Connected;
            Ok(())
        }
        Err(e) => {
            let error_msg = match &e {
                serialwarp_core::TransportError::DeviceNotFound => {
                    format!(
                        "No supported USB link cable found.\n\nSupported devices:\n  - Prolific PL27A1 (067B:27A1)\n  - Genesys GL3523 (05E3:0751)\n  - VIA VL822 (2109:0822)\n\nConnected USB devices:\n{}",
                        debug_info.connected_devices.iter()
                            .map(|d| format!("  - {} ({:04X}:{:04X})", d.name, d.vendor_id, d.product_id))
                            .collect::<Vec<_>>()
                            .join("\n")
                    )
                }
                _ => format!("Connection failed: {:?}", e),
            };

            {
                let mut last_error = state.last_error.lock().await;
                *last_error = Some(error_msg.clone());
            }

            let mut status = state.connection_status.lock().await;
            *status = ConnectionStatus::Error;
            Err(error_msg)
        }
    }
}

/// Get USB debug information
fn get_usb_debug_info() -> DebugInfo {
    let mut connected_devices = Vec::new();

    if let Ok(devices) = nusb::list_devices() {
        for device_info in devices {
            let vid = device_info.vendor_id();
            let pid = device_info.product_id();
            let name = device_info
                .product_string()
                .or_else(|| device_info.manufacturer_string())
                .unwrap_or("Unknown Device")
                .to_string();

            connected_devices.push(UsbDeviceInfo {
                name,
                vendor_id: vid,
                product_id: pid,
            });
        }
    }

    DebugInfo {
        connected_devices,
        supported_devices: SUPPORTED_USB_DEVICES
            .iter()
            .map(|d| UsbDeviceInfo {
                name: d.name.to_string(),
                vendor_id: d.vendor_id,
                product_id: d.product_id,
            })
            .collect(),
        last_error: None,
    }
}

/// Get debug information about USB devices and connection state
#[tauri::command]
pub async fn get_debug_info(state: State<'_, Arc<AppState>>) -> Result<DebugInfo, String> {
    let mut info = get_usb_debug_info();
    let last_error = state.last_error.lock().await;
    info.last_error = last_error.clone();
    Ok(info)
}

/// Get the last connection error message
#[tauri::command]
pub async fn get_last_error(state: State<'_, Arc<AppState>>) -> Result<Option<String>, String> {
    let last_error = state.last_error.lock().await;
    Ok(last_error.clone())
}

/// Disconnect from USB transport
#[tauri::command]
pub async fn disconnect_transport(state: State<'_, Arc<AppState>>) -> Result<(), String> {
    // First stop streaming if active
    if state.is_streaming.load(Ordering::SeqCst) {
        state.is_streaming.store(false, Ordering::SeqCst);

        let mut streaming = state.streaming.lock().await;
        if let Some(mut capture) = streaming.capture_stream.take() {
            capture.stop();
        }
        streaming.encoder = None;
        streaming.start_time = None;
    }

    let mut transport = state.transport.lock().await;
    if let Some(t) = transport.take() {
        t.close().await;
    }

    let mut status = state.connection_status.lock().await;
    *status = ConnectionStatus::Disconnected;

    Ok(())
}

/// Get current connection status
#[tauri::command]
pub async fn get_connection_status(state: State<'_, Arc<AppState>>) -> Result<ConnectionStatus, String> {
    let status = state.connection_status.lock().await;
    Ok(status.clone())
}

/// Create a virtual display
#[tauri::command]
pub async fn create_virtual_display(
    config: StreamConfig,
    state: State<'_, Arc<AppState>>,
) -> Result<u32, String> {
    let vdisp_config = config.to_virtual_display_config();

    let vdisp =
        VirtualDisplay::new(vdisp_config).map_err(|e| format!("Failed to create display: {:?}", e))?;

    let display_id = vdisp.display_id();

    let mut vd = state.virtual_display.lock().await;
    *vd = Some(vdisp);

    // Store the config
    let mut current_config = state.current_config.lock().await;
    *current_config = config;

    Ok(display_id)
}

/// Destroy the virtual display
#[tauri::command]
pub async fn destroy_virtual_display(state: State<'_, Arc<AppState>>) -> Result<(), String> {
    let mut vd = state.virtual_display.lock().await;
    *vd = None;
    Ok(())
}

/// Start streaming
#[tauri::command]
pub async fn start_streaming(
    config: StreamConfig,
    app: AppHandle,
    state: State<'_, Arc<AppState>>,
) -> Result<(), String> {
    // Check if already streaming
    if state.is_streaming.load(Ordering::SeqCst) {
        return Err("Already streaming".to_string());
    }

    // Get virtual display ID
    let vd = state.virtual_display.lock().await;
    let display_id = vd
        .as_ref()
        .map(|v| v.display_id())
        .ok_or("Virtual display not created")?;
    drop(vd);

    // Create capture stream
    let capture_config = config.to_capture_config(display_id);
    let capture_stream = CaptureStream::new(capture_config)
        .await
        .map_err(|e| format!("Failed to create capture stream: {:?}", e))?;

    // Create encoder
    let encoder_config = config.to_encoder_config();
    let encoder =
        Encoder::new(encoder_config).map_err(|e| format!("Failed to create encoder: {:?}", e))?;

    // Store in state
    {
        let mut streaming = state.streaming.lock().await;
        streaming.capture_stream = Some(capture_stream);
        streaming.encoder = Some(encoder);
        streaming.start_time = Some(Instant::now());
    }

    // Update status
    state.is_streaming.store(true, Ordering::SeqCst);
    state.reset_stats();
    {
        let mut status = state.connection_status.lock().await;
        *status = ConnectionStatus::Streaming;
    }

    // Store config
    {
        let mut current_config = state.current_config.lock().await;
        *current_config = config.clone();
    }

    // Spawn the streaming task
    let state_clone = Arc::clone(&*state);
    let app_clone = app.clone();
    let settings = state.settings.lock().await.clone();

    tokio::spawn(async move {
        streaming_loop(state_clone, app_clone, settings).await;
    });

    Ok(())
}

/// Main streaming loop
async fn streaming_loop(
    state: Arc<AppState>,
    app: AppHandle,
    settings: AppSettings,
) {
    let preview_enabled = settings.preview_enabled;
    let preview_quality = settings.preview_quality;

    loop {
        if !state.is_streaming.load(Ordering::SeqCst) {
            break;
        }

        let mut streaming = state.streaming.lock().await;
        let capture_stream = match streaming.capture_stream.as_mut() {
            Some(s) => s,
            None => break,
        };

        // Get next frame
        let frame = match capture_stream.next_frame().await {
            Some(f) => f,
            None => continue,
        };

        state.increment_captured();

        // Encode frame
        let encoder = match streaming.encoder.as_mut() {
            Some(e) => e,
            None => break,
        };

        if let Err(e) = encoder.encode_raw(&frame.pixel_data, frame.metadata.pts_us, false) {
            tracing::error!("Encode error: {:?}", e);
            state.increment_dropped();
            continue;
        }

        // Get encoded frame
        if let Some(Ok(_encoded)) = encoder.next_frame().await {
            state.increment_encoded();

            // Send to transport if connected
            let transport = state.transport.lock().await;
            if transport.is_some() {
                // In a full implementation, we'd send the frame here
                // For now, just count it
                state.increment_sent();
            }
            drop(transport);

            // Send preview frame to frontend if enabled
            if preview_enabled {
                // Downsample and encode as JPEG for preview
                // This is a simplified version - in production we'd use proper image scaling
                if let Ok(preview_data) = create_preview_frame(&frame.pixel_data, frame.width, frame.height, preview_quality) {
                    let _ = app.emit("preview_frame", preview_data);
                }
            }
        }

        drop(streaming);
    }
}

/// Create a JPEG preview frame from BGRA pixel data
fn create_preview_frame(
    pixel_data: &[u8],
    width: u32,
    height: u32,
    quality: u32,
) -> Result<String, String> {
    use image::{ImageBuffer, Rgba};

    // Create image from BGRA data
    let mut rgba_data = Vec::with_capacity(pixel_data.len());
    for chunk in pixel_data.chunks(4) {
        if chunk.len() == 4 {
            // BGRA to RGBA
            rgba_data.push(chunk[2]); // R
            rgba_data.push(chunk[1]); // G
            rgba_data.push(chunk[0]); // B
            rgba_data.push(chunk[3]); // A
        }
    }

    let img: ImageBuffer<Rgba<u8>, Vec<u8>> =
        ImageBuffer::from_raw(width, height, rgba_data)
            .ok_or("Failed to create image buffer")?;

    // Resize for preview (max 480p)
    let preview_width = 854;
    let preview_height = 480;
    let resized = image::imageops::resize(
        &img,
        preview_width,
        preview_height,
        image::imageops::FilterType::Triangle,
    );

    // Encode as JPEG
    let mut jpeg_data = Vec::new();
    let mut encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut jpeg_data, quality as u8);
    encoder
        .encode_image(&resized)
        .map_err(|e| format!("Failed to encode JPEG: {:?}", e))?;

    // Base64 encode
    Ok(base64::engine::general_purpose::STANDARD.encode(&jpeg_data))
}

/// Stop streaming
#[tauri::command]
pub async fn stop_streaming(state: State<'_, Arc<AppState>>) -> Result<(), String> {
    state.is_streaming.store(false, Ordering::SeqCst);

    let mut streaming = state.streaming.lock().await;
    if let Some(mut capture) = streaming.capture_stream.take() {
        capture.stop();
    }
    streaming.encoder = None;
    streaming.start_time = None;
    drop(streaming);

    // Update status based on transport connection
    let transport = state.transport.lock().await;
    let mut status = state.connection_status.lock().await;
    *status = if transport.is_some() {
        ConnectionStatus::Connected
    } else {
        ConnectionStatus::Disconnected
    };

    Ok(())
}

/// Get streaming statistics
#[tauri::command]
pub async fn get_stream_stats(state: State<'_, Arc<AppState>>) -> Result<StreamStats, String> {
    let streaming = state.streaming.lock().await;
    let elapsed = streaming
        .start_time
        .map(|t| t.elapsed().as_secs_f64())
        .unwrap_or(0.0);
    drop(streaming);

    let frames_captured = state.frames_captured.load(Ordering::SeqCst);
    let frames_encoded = state.frames_encoded.load(Ordering::SeqCst);
    let frames_sent = state.frames_sent.load(Ordering::SeqCst);
    let frames_dropped = state.frames_dropped.load(Ordering::SeqCst);

    let fps = if elapsed > 0.0 {
        frames_captured as f64 / elapsed
    } else {
        0.0
    };

    // Estimate bitrate based on encoded frames (rough estimate)
    let config = state.current_config.lock().await;
    let target_bitrate = config.bitrate_mbps as u64 * 1_000_000;
    let bitrate_bps = if frames_encoded > 0 && frames_captured > 0 {
        (target_bitrate as f64 * (frames_encoded as f64 / frames_captured as f64)) as u64
    } else {
        0
    };

    Ok(StreamStats {
        fps,
        bitrate_bps,
        frames_captured,
        frames_encoded,
        frames_sent,
        frames_dropped,
        elapsed_seconds: elapsed,
    })
}

/// Get application settings
#[tauri::command]
pub async fn get_settings(state: State<'_, Arc<AppState>>) -> Result<AppSettings, String> {
    let settings = state.settings.lock().await;
    Ok(settings.clone())
}

/// Save application settings
#[tauri::command]
pub async fn save_settings(
    settings: AppSettings,
    state: State<'_, Arc<AppState>>,
) -> Result<(), String> {
    let mut s = state.settings.lock().await;
    *s = settings;
    Ok(())
}
