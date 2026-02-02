//! serialwarp-sink - PC binary for receiving and displaying video
//!
//! This binary runs on the PC side and receives video from the Mac source,
//! decoding and rendering it to a window.

use anyhow::{Context, Result};
use bytes::Bytes;
use clap::Parser;
use tracing::{error, info, warn};
use tracing_subscriber::EnvFilter;

use serialwarp_core::{
    FrameAckPayload, FrameHeader, FrameReassembler, HelloPayload, Packet, PacketType,
    StartAckPayload, StartPayload,
};
use serialwarp_decode::{Decoder, DecoderConfig};
use serialwarp_render::{Renderer, RendererConfig};
use serialwarp_transport::{Transport, UsbTransport};

/// serialwarp sink - display video from Mac source
#[derive(Parser, Debug)]
#[command(name = "serialwarp-sink")]
#[command(about = "Receive and display video from a Mac source")]
struct Args {
    /// Maximum supported width
    #[arg(long, default_value_t = 3840)]
    max_width: u32,

    /// Maximum supported height
    #[arg(long, default_value_t = 2160)]
    max_height: u32,

    /// Start in fullscreen mode
    #[arg(short, long)]
    fullscreen: bool,

    /// Initial flow control credits
    #[arg(long, default_value_t = 8)]
    credits: u16,
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env().add_directive("serialwarp=info".parse()?))
        .init();

    let args = Args::parse();

    info!("serialwarp-sink starting");
    info!(
        "Max resolution: {}x{}, credits: {}",
        args.max_width, args.max_height, args.credits
    );

    // Open USB transport (wait for connection)
    info!("Waiting for USB connection...");
    let transport = UsbTransport::open().await.context("Failed to open USB transport")?;
    info!("USB transport connected");

    // Run main loop
    if let Err(e) = run_sink(transport, &args).await {
        error!("Sink error: {:?}", e);
        return Err(e);
    }

    Ok(())
}

async fn run_sink<T: Transport>(transport: T, args: &Args) -> Result<()> {
    let mut sequence = 0u32;

    // Step 1: Receive HELLO
    info!("Waiting for HELLO...");
    let hello = receive_packet(&transport).await?;
    if hello.packet_type() != PacketType::Hello {
        anyhow::bail!(
            "Expected HELLO, got {:?}",
            hello.packet_type()
        );
    }

    let hello_payload = HelloPayload::parse(&hello.payload)?;
    info!(
        "Received HELLO: max {}x{} @ {}fps",
        hello_payload.max_width,
        hello_payload.max_height,
        hello_payload.max_fps()
    );

    // Step 2: Send HELLO_ACK
    let ack_payload = HelloPayload::new(
        1, // software version
        args.max_width,
        args.max_height,
        60,
        0x03, // capabilities: hidpi + audio
    );
    let ack = Packet::new(
        PacketType::HelloAck,
        0,
        sequence,
        ack_payload.to_bytes(),
    );
    sequence += 1;
    transport.send(ack.to_bytes()).await?;
    info!("Sent HELLO_ACK");

    // Step 3: Receive START
    info!("Waiting for START...");
    let start = receive_packet(&transport).await?;
    if start.packet_type() != PacketType::Start {
        anyhow::bail!("Expected START, got {:?}", start.packet_type());
    }

    let start_payload = StartPayload::parse(&start.payload)?;
    info!(
        "Received START: {}x{} @ {}fps, {} bps",
        start_payload.width,
        start_payload.height,
        start_payload.fps(),
        start_payload.bitrate_bps
    );

    // Step 4: Send START_ACK
    let start_ack_payload = StartAckPayload::ok(args.credits);
    let start_ack = Packet::new(
        PacketType::StartAck,
        0,
        sequence,
        start_ack_payload.to_bytes(),
    );
    sequence += 1;
    transport.send(start_ack.to_bytes()).await?;
    info!("Sent START_ACK with {} credits", args.credits);

    // Step 5: Create decoder
    let decoder_config = DecoderConfig::default();
    let mut decoder = Decoder::new(decoder_config).context("Failed to create decoder")?;
    info!("Decoder initialized");

    // Step 6: Create renderer
    let renderer_config = RendererConfig {
        title: format!(
            "serialwarp - {}x{}",
            start_payload.width, start_payload.height
        ),
        width: start_payload.width,
        height: start_payload.height,
        fullscreen: args.fullscreen,
        vsync: true,
    };
    let mut renderer = Renderer::new(renderer_config).context("Failed to create renderer")?;
    info!("Renderer initialized");

    // Step 7: Main receive loop
    let mut reassembler = FrameReassembler::new();
    let mut credits = args.credits;
    let mut frame_number = 0u64;

    info!("Starting main loop");

    loop {
        // Process SDL events (quit on escape or window close)
        if !renderer.process_events() {
            info!("Quit requested");
            break;
        }

        // Try to receive a packet (non-blocking would be better, but for now we use timeout)
        match tokio::time::timeout(
            std::time::Duration::from_millis(10),
            receive_packet(&transport),
        )
        .await
        {
            Ok(Ok(packet)) => {
                match packet.packet_type() {
                    PacketType::Frame => {
                        // Parse frame header
                        if packet.payload.len() < FrameHeader::SIZE {
                            warn!("Frame payload too small");
                            continue;
                        }

                        let header = FrameHeader::parse(&packet.payload)?;
                        let data = packet.payload[FrameHeader::SIZE..].to_vec();

                        // Add segment to reassembler
                        if let Some(complete_frame) = reassembler.add_segment(&header, data) {
                            // Decode frame
                            let start_time = std::time::Instant::now();
                            match decoder.decode(&complete_frame.data, complete_frame.metadata.pts_us as i64) {
                                Ok(decoded_frames) => {
                                    let decode_time = start_time.elapsed();

                                    for mut decoded in decoded_frames {
                                        // Set frame number
                                        decoded = serialwarp_core::DecodedFrame::new(
                                            frame_number,
                                            decoded.pts_us,
                                            decoded.width,
                                            decoded.height,
                                            decoded.y_plane().iter()
                                                .chain(decoded.u_plane().iter())
                                                .chain(decoded.v_plane().iter())
                                                .copied()
                                                .collect(),
                                        );

                                        // Render frame
                                        if let Err(e) = renderer.present(&decoded) {
                                            warn!("Render error: {:?}", e);
                                        }
                                    }

                                    // Send FRAME_ACK
                                    credits = credits.saturating_add(1);
                                    let ack_payload = FrameAckPayload::new(
                                        header.frame_number,
                                        decode_time.as_micros() as u32,
                                        1, // Return 1 credit per frame
                                    );
                                    let ack = Packet::new(
                                        PacketType::FrameAck,
                                        0,
                                        sequence,
                                        ack_payload.to_bytes(),
                                    );
                                    sequence += 1;
                                    if let Err(e) = transport.send(ack.to_bytes()).await {
                                        warn!("Failed to send FRAME_ACK: {:?}", e);
                                    }

                                    frame_number += 1;
                                }
                                Err(e) => {
                                    warn!("Decode error: {:?}", e);
                                }
                            }
                        }
                    }
                    PacketType::Stop => {
                        info!("Received STOP");
                        // Send STOP_ACK
                        let stop_ack = Packet::new(PacketType::StopAck, 0, sequence, Bytes::new());
                        let _ = transport.send(stop_ack.to_bytes()).await;
                        break;
                    }
                    PacketType::Ping => {
                        // Respond with PONG
                        let pong_payload = serialwarp_core::PongPayload::new(
                            serialwarp_core::PingPayload::parse(&packet.payload)?.timestamp_us,
                            std::time::SystemTime::now()
                                .duration_since(std::time::UNIX_EPOCH)
                                .unwrap()
                                .as_micros() as u64,
                        );
                        let pong = Packet::new(
                            PacketType::Pong,
                            0,
                            sequence,
                            pong_payload.to_bytes(),
                        );
                        sequence += 1;
                        let _ = transport.send(pong.to_bytes()).await;
                    }
                    _ => {
                        warn!("Unexpected packet type: {:?}", packet.packet_type());
                    }
                }
            }
            Ok(Err(e)) => {
                // Transport error
                if !transport.is_connected() {
                    error!("Transport disconnected");
                    break;
                }
                warn!("Receive error: {:?}", e);
            }
            Err(_) => {
                // Timeout - continue loop to process events
            }
        }
    }

    // Cleanup
    info!("Shutting down");
    transport.close().await;

    Ok(())
}

async fn receive_packet<T: Transport>(transport: &T) -> Result<Packet> {
    let data = transport.recv().await?;
    let (packet, _consumed) = Packet::parse(&data)?;
    Ok(packet)
}
