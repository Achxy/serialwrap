use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::time::Instant;
use tauri::{AppHandle, State, WebviewWindow};

use serialwarp_core::frame::FrameReassembler;
use serialwarp_decode::{Decoder, DecoderConfig};
use serialwarp_transport::{Transport, UsbTransport};

#[allow(unused_imports)]
use tracing;

use crate::state::{
    AppSettings, AppState, ConnectionStatus, DisplayStats, NegotiatedParams, TransportWrapper,
    UsbDeviceInfo,
};

/// List supported USB devices
#[tauri::command]
pub async fn list_usb_devices() -> Result<Vec<UsbDeviceInfo>, String> {
    let supported = vec![
        UsbDeviceInfo {
            name: "Prolific PL27A1".to_string(),
            vendor_id: 0x067B,
            product_id: 0x27A1,
        },
        UsbDeviceInfo {
            name: "Genesys GL3523".to_string(),
            vendor_id: 0x05E3,
            product_id: 0x0751,
        },
        UsbDeviceInfo {
            name: "VIA VL822".to_string(),
            vendor_id: 0x2109,
            product_id: 0x0822,
        },
    ];
    Ok(supported)
}

/// Wait for connection from Mac and perform handshake
#[tauri::command]
pub async fn wait_for_connection(
    state: State<'_, Arc<AppState>>,
) -> Result<NegotiatedParams, String> {
    // Update status to waiting
    {
        let mut status = state.connection_status.lock().await;
        *status = ConnectionStatus::Waiting;
    }

    // Try to open USB transport
    let transport = match UsbTransport::open().await {
        Ok(t) => t,
        Err(e) => {
            let mut status = state.connection_status.lock().await;
            *status = ConnectionStatus::Error;
            return Err(format!("Failed to open USB transport: {:?}", e));
        }
    };

    // Update status to connecting
    {
        let mut status = state.connection_status.lock().await;
        *status = ConnectionStatus::Connecting;
    }

    // Store transport
    {
        let mut t = state.transport.lock().await;
        *t = TransportWrapper(Some(transport));
    }

    // In a full implementation, we'd wait for HELLO packet and send HELLO_ACK
    // For now, return default params
    let params = NegotiatedParams {
        width: 1920,
        height: 1080,
        fps: 60,
        bitrate_bps: 20_000_000,
    };

    // Store receiving state (decoder will be created lazily in receiving_loop)
    {
        let mut receiving = state.receiving.lock().await;
        receiving.decoder = None; // Will be created in receiving_loop
        receiving.params = Some(params.clone());
        receiving.start_time = Some(Instant::now());
    }

    // Update status
    {
        let mut status = state.connection_status.lock().await;
        *status = ConnectionStatus::Connected;
    }

    Ok(params)
}

/// Disconnect from Mac
#[tauri::command]
pub async fn disconnect(state: State<'_, Arc<AppState>>) -> Result<(), String> {
    // Stop receiving
    state.is_receiving.store(false, Ordering::SeqCst);

    // Close transport
    {
        let mut transport = state.transport.lock().await;
        if let Some(t) = transport.0.take() {
            t.close().await;
        }
    }

    // Clear receiving state
    {
        let mut receiving = state.receiving.lock().await;
        receiving.decoder = None;
        receiving.params = None;
        receiving.start_time = None;
    }

    // Update status
    {
        let mut status = state.connection_status.lock().await;
        *status = ConnectionStatus::Disconnected;
    }

    state.reset_stats();

    Ok(())
}

/// Start receiving and displaying frames
#[tauri::command]
pub async fn start_display(
    app: AppHandle,
    state: State<'_, Arc<AppState>>,
) -> Result<(), String> {
    // Check if already receiving
    if state.is_receiving.load(Ordering::SeqCst) {
        return Err("Already receiving".to_string());
    }

    // Verify we're connected
    {
        let status = state.connection_status.lock().await;
        if *status != ConnectionStatus::Connected {
            return Err("Not connected".to_string());
        }
    }

    state.is_receiving.store(true, Ordering::SeqCst);
    state.reset_stats();

    // Update status
    {
        let mut status = state.connection_status.lock().await;
        *status = ConnectionStatus::Receiving;
    }

    // Spawn the receiving task
    let state_clone = Arc::clone(&*state);
    let _app_clone = app.clone();

    tokio::spawn(async move {
        receiving_loop(state_clone).await;
    });

    Ok(())
}

/// Main receiving loop - runs in a separate blocking task
async fn receiving_loop(state: Arc<AppState>) {
    // Use spawn_blocking for non-Send decoder
    let state_clone = Arc::clone(&state);

    let _ = tokio::task::spawn_blocking(move || {
        // Create decoder (not Send-safe)
        let decoder = match Decoder::new(DecoderConfig::default()) {
            Ok(d) => d,
            Err(_e) => {
                // Can't easily set status from blocking task without more complexity
                // In production, use channels to communicate errors
                return;
            }
        };

        let _reassembler = FrameReassembler::default();
        let _decoder = decoder; // Keep decoder alive

        // Synchronous receiving loop
        loop {
            if !state_clone.is_receiving.load(Ordering::SeqCst) {
                break;
            }

            // In production, we'd:
            // 1. Receive FRAME packets from transport (blocking read)
            // 2. Reassemble using FrameReassembler
            // 3. Decode using Decoder
            // 4. Send decoded frame to frontend for display via channel

            // Simulated delay
            std::thread::sleep(std::time::Duration::from_millis(16));
        }
    })
    .await;

    // Update status when loop ends
    let transport = state.transport.lock().await;
    let mut status = state.connection_status.lock().await;
    *status = if transport.0.is_some() {
        ConnectionStatus::Connected
    } else {
        ConnectionStatus::Disconnected
    };
}

/// Stop receiving and displaying
#[tauri::command]
pub async fn stop_display(state: State<'_, Arc<AppState>>) -> Result<(), String> {
    state.is_receiving.store(false, Ordering::SeqCst);

    // Update status
    let transport = state.transport.lock().await;
    let mut status = state.connection_status.lock().await;
    *status = if transport.0.is_some() {
        ConnectionStatus::Connected
    } else {
        ConnectionStatus::Disconnected
    };

    Ok(())
}

/// Toggle fullscreen mode
#[tauri::command]
pub async fn toggle_fullscreen(
    window: WebviewWindow,
    state: State<'_, Arc<AppState>>,
) -> Result<bool, String> {
    let is_fullscreen = state.is_fullscreen.load(Ordering::SeqCst);
    let new_state = !is_fullscreen;

    window
        .set_fullscreen(new_state)
        .map_err(|e| format!("Failed to set fullscreen: {:?}", e))?;

    state.is_fullscreen.store(new_state, Ordering::SeqCst);

    Ok(new_state)
}

/// Get display statistics
#[tauri::command]
pub async fn get_display_stats(state: State<'_, Arc<AppState>>) -> Result<DisplayStats, String> {
    let receiving = state.receiving.lock().await;
    let elapsed = receiving
        .start_time
        .map(|t| t.elapsed().as_secs_f64())
        .unwrap_or(0.0);
    drop(receiving);

    let frames_received = state.frames_received.load(Ordering::SeqCst);
    let frames_decoded = state.frames_decoded.load(Ordering::SeqCst);
    let frames_displayed = state.frames_displayed.load(Ordering::SeqCst);
    let frames_dropped = state.frames_dropped.load(Ordering::SeqCst);

    let fps = if elapsed > 0.0 {
        frames_displayed as f64 / elapsed
    } else {
        0.0
    };

    Ok(DisplayStats {
        fps,
        frames_received,
        frames_decoded,
        frames_displayed,
        frames_dropped,
        decode_time_ms: state.get_avg_decode_time_ms(),
        latency_ms: state.get_avg_latency_ms(),
        elapsed_seconds: elapsed,
    })
}

/// Get current connection status
#[tauri::command]
pub async fn get_connection_status(state: State<'_, Arc<AppState>>) -> Result<ConnectionStatus, String> {
    let status = state.connection_status.lock().await;
    Ok(status.clone())
}

/// Get negotiated parameters
#[tauri::command]
pub async fn get_negotiated_params(
    state: State<'_, Arc<AppState>>,
) -> Result<Option<NegotiatedParams>, String> {
    let receiving = state.receiving.lock().await;
    Ok(receiving.params.clone())
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
