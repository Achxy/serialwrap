//! serialwarp-source - Mac binary for capturing and sending video
//!
//! This binary runs on the Mac side and captures the virtual display,
//! encodes it as H.264, and sends it to the PC sink.

#![cfg(target_os = "macos")]

use anyhow::{Context, Result};
use bytes::Bytes;
use clap::Parser;
use std::sync::atomic::{AtomicU16, Ordering};
use std::sync::Arc;
use tracing::{error, info, warn};
use tracing_subscriber::EnvFilter;

use serialwarp_capture::{CaptureConfig, CaptureStream};
use serialwarp_core::{
    EncodedFrame, FrameAckPayload, HelloPayload, Packet, PacketType, StartAckPayload, StartPayload,
};
use serialwarp_encode::{Encoder, EncoderConfig};
use serialwarp_transport::{Transport, UsbTransport};
use serialwarp_vdisp::{VirtualDisplay, VirtualDisplayConfig};

/// serialwarp source - capture and send video from Mac
#[derive(Parser, Debug)]
#[command(name = "serialwarp-source")]
#[command(about = "Capture and send video to a PC sink")]
struct Args {
    /// Display width
    #[arg(long, default_value_t = 1920)]
    width: u32,

    /// Display height
    #[arg(long, default_value_t = 1080)]
    height: u32,

    /// Frames per second
    #[arg(long, default_value_t = 60)]
    fps: u32,

    /// Bitrate in Mbps
    #[arg(long, default_value_t = 20)]
    bitrate_mbps: u32,

    /// Enable HiDPI mode
    #[arg(long)]
    hidpi: bool,
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env().add_directive("serialwarp=info".parse()?))
        .init();

    let args = Args::parse();

    info!("serialwarp-source starting");
    info!(
        "Resolution: {}x{} @ {}fps, {} Mbps",
        args.width, args.height, args.fps, args.bitrate_mbps
    );

    // Step 1: Create virtual display
    info!("Creating virtual display...");
    let vdisp_config = VirtualDisplayConfig {
        name: "serialwarp".to_string(),
        max_width: args.width,
        max_height: args.height,
        refresh_rate: args.fps,
        hidpi: args.hidpi,
    };
    let vdisp = VirtualDisplay::new(vdisp_config).context("Failed to create virtual display")?;
    let display_id = vdisp.display_id();
    info!("Virtual display created with ID: {}", display_id);

    // Step 2: Wait for system to recognize display
    info!("Waiting for display to initialize...");
    tokio::time::sleep(std::time::Duration::from_millis(500)).await;

    // Step 3: Open USB transport
    info!("Opening USB transport...");
    let transport = UsbTransport::open()
        .await
        .context("Failed to open USB transport")?;
    info!("USB transport connected");

    // Run main loop
    if let Err(e) = run_source(transport, &args, display_id).await {
        error!("Source error: {:?}", e);
        return Err(e);
    }

    Ok(())
}

async fn run_source<T: Transport + 'static>(transport: T, args: &Args, display_id: u32) -> Result<()> {
    let mut sequence = 0u32;

    // Step 1: Send HELLO
    info!("Sending HELLO...");
    let hello_payload = HelloPayload::new(
        1, // software version
        args.width,
        args.height,
        args.fps,
        if args.hidpi { 0x01 } else { 0x00 }, // capabilities
    );
    let hello = Packet::new(PacketType::Hello, 0, sequence, hello_payload.to_bytes());
    sequence += 1;
    transport.send(hello.to_bytes()).await?;

    // Step 2: Receive HELLO_ACK
    info!("Waiting for HELLO_ACK...");
    let ack = receive_packet(&transport).await?;
    if ack.packet_type() != PacketType::HelloAck {
        anyhow::bail!("Expected HELLO_ACK, got {:?}", ack.packet_type());
    }
    let ack_payload = HelloPayload::parse(&ack.payload)?;
    info!(
        "Received HELLO_ACK: max {}x{} @ {}fps",
        ack_payload.max_width,
        ack_payload.max_height,
        ack_payload.max_fps()
    );

    // Negotiate resolution
    let width = args.width.min(ack_payload.max_width);
    let height = args.height.min(ack_payload.max_height);
    let fps = args.fps.min(ack_payload.max_fps());

    // Step 3: Send START
    info!("Sending START: {}x{} @ {}fps...", width, height, fps);
    let start_payload = StartPayload::new(width, height, fps, args.bitrate_mbps * 1_000_000);
    let start = Packet::new(PacketType::Start, 0, sequence, start_payload.to_bytes());
    sequence += 1;
    transport.send(start.to_bytes()).await?;

    // Step 4: Receive START_ACK
    info!("Waiting for START_ACK...");
    let start_ack = receive_packet(&transport).await?;
    if start_ack.packet_type() != PacketType::StartAck {
        anyhow::bail!("Expected START_ACK, got {:?}", start_ack.packet_type());
    }
    let start_ack_payload = StartAckPayload::parse(&start_ack.payload)?;
    if !start_ack_payload.is_ok() {
        anyhow::bail!("START_ACK status: {}", start_ack_payload.status);
    }
    let initial_credits = start_ack_payload.initial_credits;
    info!("Received START_ACK with {} credits", initial_credits);

    // Step 5: Create capture stream
    info!("Creating capture stream...");
    let capture_config = CaptureConfig {
        display_id,
        width,
        height,
        fps,
    };
    let mut capture = CaptureStream::new(capture_config)
        .await
        .context("Failed to create capture stream")?;
    info!("Capture stream created");

    // Step 6: Create encoder
    info!("Creating encoder...");
    let encoder_config = EncoderConfig {
        width,
        height,
        fps,
        bitrate_bps: args.bitrate_mbps * 1_000_000,
        keyframe_interval: fps,
        low_latency: true,
    };
    let encoder = Encoder::new(encoder_config).context("Failed to create encoder")?;
    info!("Encoder created");

    // Step 7: Start frame ACK receiver task
    let credits = Arc::new(AtomicU16::new(initial_credits));
    let credits_clone = Arc::clone(&credits);
    let transport_clone = Arc::new(transport);
    let transport_for_ack = Arc::clone(&transport_clone);

    tokio::spawn(async move {
        loop {
            match receive_packet(transport_for_ack.as_ref()).await {
                Ok(packet) => match packet.packet_type() {
                    PacketType::FrameAck => {
                        if let Ok(payload) = FrameAckPayload::parse(&packet.payload) {
                            let old = credits_clone.fetch_add(payload.credits_returned, Ordering::SeqCst);
                            tracing::debug!(
                                "FRAME_ACK for frame {}: credits {} -> {}",
                                payload.frame_number,
                                old,
                                old + payload.credits_returned
                            );
                        }
                    }
                    PacketType::Stop => {
                        info!("Received STOP from sink");
                        break;
                    }
                    _ => {
                        warn!("Unexpected packet type: {:?}", packet.packet_type());
                    }
                },
                Err(e) => {
                    if !transport_for_ack.is_connected() {
                        break;
                    }
                    warn!("ACK receive error: {:?}", e);
                }
            }
        }
    });

    // Step 8: Main capture/encode/send loop
    info!("Starting main loop");

    while transport_clone.is_connected() {
        // Wait for credits
        while credits.load(Ordering::SeqCst) == 0 {
            tokio::time::sleep(std::time::Duration::from_micros(100)).await;
            if !transport_clone.is_connected() {
                break;
            }
        }

        if !transport_clone.is_connected() {
            break;
        }

        // Capture frame
        let captured = match capture.next_frame().await {
            Some(frame) => frame,
            None => {
                warn!("Capture stream ended");
                break;
            }
        };

        // Encode frame
        let pts_us = captured.metadata.pts_us;
        if let Err(e) = encoder.encode_raw(&captured.pixel_data, pts_us, false) {
            warn!("Encode error: {:?}", e);
            continue;
        }

        // Create encoded frame (placeholder - in real impl would come from encoder callback)
        let encoded = EncodedFrame::new(
            captured.metadata,
            vec![0u8; 1024], // Placeholder data
        );

        // Segment and send
        let segments = encoded.into_segments();
        for segment in segments {
            let payload = segment.to_payload();
            let packet = Packet::new(PacketType::Frame, 0, sequence, payload);
            sequence += 1;

            if let Err(e) = transport_clone.send(packet.to_bytes()).await {
                warn!("Send error: {:?}", e);
                break;
            }
        }

        // Decrement credits
        credits.fetch_sub(1, Ordering::SeqCst);
    }

    // Shutdown
    info!("Sending STOP...");
    let stop = Packet::new(PacketType::Stop, 0, sequence, Bytes::new());
    let _ = transport_clone.send(stop.to_bytes()).await;

    // Wait for STOP_ACK
    match tokio::time::timeout(
        std::time::Duration::from_secs(1),
        receive_packet(transport_clone.as_ref()),
    )
    .await
    {
        Ok(Ok(packet)) if packet.packet_type() == PacketType::StopAck => {
            info!("Received STOP_ACK");
        }
        _ => {
            warn!("Did not receive STOP_ACK");
        }
    }

    info!("Shutting down");
    transport_clone.close().await;

    Ok(())
}

async fn receive_packet<T: Transport>(transport: &T) -> Result<Packet> {
    let data = transport.recv().await?;
    let (packet, _consumed) = Packet::parse(&data)?;
    Ok(packet)
}
