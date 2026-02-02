use bytes::{Buf, BufMut, Bytes, BytesMut};

use crate::error::ProtocolError;

/// Protocol magic number "SWRP" in little-endian
pub const MAGIC: u32 = 0x53575250;

/// Current protocol version
pub const PROTOCOL_VERSION: u8 = 1;

/// Maximum segment size for frame data (64KB)
pub const MAX_SEGMENT_SIZE: usize = 65536;

/// Header size in bytes
pub const HEADER_SIZE: usize = 16;

/// CRC size in bytes
pub const CRC_SIZE: usize = 4;

/// Packet types
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum PacketType {
    Hello = 0x01,
    HelloAck = 0x02,
    Start = 0x03,
    StartAck = 0x04,
    Frame = 0x10,
    FrameAck = 0x11,
    Stop = 0x30,
    StopAck = 0x31,
    Ping = 0x40,
    Pong = 0x41,
}

impl PacketType {
    pub fn from_u8(value: u8) -> Result<Self, ProtocolError> {
        match value {
            0x01 => Ok(PacketType::Hello),
            0x02 => Ok(PacketType::HelloAck),
            0x03 => Ok(PacketType::Start),
            0x04 => Ok(PacketType::StartAck),
            0x10 => Ok(PacketType::Frame),
            0x11 => Ok(PacketType::FrameAck),
            0x30 => Ok(PacketType::Stop),
            0x31 => Ok(PacketType::StopAck),
            0x40 => Ok(PacketType::Ping),
            0x41 => Ok(PacketType::Pong),
            _ => Err(ProtocolError::UnknownPacketType(value)),
        }
    }
}

/// Packet header (16 bytes)
#[derive(Debug, Clone)]
pub struct PacketHeader {
    pub magic: u32,
    pub version: u8,
    pub packet_type: PacketType,
    pub flags: u16,
    pub sequence: u32,
    pub payload_length: u32,
}

impl PacketHeader {
    pub fn new(packet_type: PacketType, flags: u16, sequence: u32, payload_length: u32) -> Self {
        Self {
            magic: MAGIC,
            version: PROTOCOL_VERSION,
            packet_type,
            flags,
            sequence,
            payload_length,
        }
    }

    pub fn to_bytes(&self) -> Bytes {
        let mut buf = BytesMut::with_capacity(HEADER_SIZE);
        buf.put_u32_le(self.magic);
        buf.put_u8(self.version);
        buf.put_u8(self.packet_type as u8);
        buf.put_u16_le(self.flags);
        buf.put_u32_le(self.sequence);
        buf.put_u32_le(self.payload_length);
        buf.freeze()
    }

    pub fn parse(data: &[u8]) -> Result<Self, ProtocolError> {
        if data.len() < HEADER_SIZE {
            return Err(ProtocolError::BufferTooShort {
                needed: HEADER_SIZE,
                available: data.len(),
            });
        }

        let mut buf = &data[..HEADER_SIZE];
        let magic = buf.get_u32_le();
        if magic != MAGIC {
            return Err(ProtocolError::InvalidMagic(magic));
        }

        let version = buf.get_u8();
        if version != PROTOCOL_VERSION {
            return Err(ProtocolError::UnsupportedVersion(version));
        }

        let packet_type = PacketType::from_u8(buf.get_u8())?;
        let flags = buf.get_u16_le();
        let sequence = buf.get_u32_le();
        let payload_length = buf.get_u32_le();

        Ok(Self {
            magic,
            version,
            packet_type,
            flags,
            sequence,
            payload_length,
        })
    }
}

/// Complete packet with header and payload
#[derive(Debug, Clone)]
pub struct Packet {
    pub header: PacketHeader,
    pub payload: Bytes,
}

impl Packet {
    pub fn new(packet_type: PacketType, flags: u16, sequence: u32, payload: Bytes) -> Self {
        let header = PacketHeader::new(packet_type, flags, sequence, payload.len() as u32);
        Self { header, payload }
    }

    /// Parse a packet from raw bytes. Returns the packet and number of bytes consumed.
    pub fn parse(data: &[u8]) -> Result<(Self, usize), ProtocolError> {
        let header = PacketHeader::parse(data)?;
        let total_size = HEADER_SIZE + header.payload_length as usize + CRC_SIZE;

        if data.len() < total_size {
            return Err(ProtocolError::BufferTooShort {
                needed: total_size,
                available: data.len(),
            });
        }

        // Extract payload
        let payload_start = HEADER_SIZE;
        let payload_end = HEADER_SIZE + header.payload_length as usize;
        let payload = Bytes::copy_from_slice(&data[payload_start..payload_end]);

        // Verify CRC
        let crc_offset = payload_end;
        let expected_crc = u32::from_le_bytes([
            data[crc_offset],
            data[crc_offset + 1],
            data[crc_offset + 2],
            data[crc_offset + 3],
        ]);
        let actual_crc = crc32c::crc32c(&data[..payload_end]);

        if expected_crc != actual_crc {
            return Err(ProtocolError::ChecksumMismatch {
                expected: expected_crc,
                actual: actual_crc,
            });
        }

        Ok((Self { header, payload }, total_size))
    }

    /// Serialize packet to bytes (header + payload + CRC)
    pub fn to_bytes(&self) -> Bytes {
        let total_size = HEADER_SIZE + self.payload.len() + CRC_SIZE;
        let mut buf = BytesMut::with_capacity(total_size);

        // Write header
        buf.put(self.header.to_bytes());

        // Write payload
        buf.put(self.payload.clone());

        // Compute and write CRC over header + payload
        let crc = crc32c::crc32c(&buf[..]);
        buf.put_u32_le(crc);

        buf.freeze()
    }

    /// Get the packet type
    pub fn packet_type(&self) -> PacketType {
        self.header.packet_type
    }

    /// Get the sequence number
    pub fn sequence(&self) -> u32 {
        self.header.sequence
    }
}

/// HELLO payload (28 bytes)
#[derive(Debug, Clone)]
pub struct HelloPayload {
    pub software_version: u16,
    pub min_protocol_version: u16,
    pub max_protocol_version: u16,
    pub reserved1: u16,
    pub max_width: u32,
    pub max_height: u32,
    pub max_fps_fixed: u32, // Fixed-point 16.16
    pub capabilities: u32,
    pub reserved2: u32,
}

impl HelloPayload {
    pub const SIZE: usize = 28;

    pub fn new(
        software_version: u16,
        max_width: u32,
        max_height: u32,
        max_fps: u32,
        capabilities: u32,
    ) -> Self {
        Self {
            software_version,
            min_protocol_version: PROTOCOL_VERSION as u16,
            max_protocol_version: PROTOCOL_VERSION as u16,
            reserved1: 0,
            max_width,
            max_height,
            max_fps_fixed: max_fps << 16, // Convert to fixed 16.16
            capabilities,
            reserved2: 0,
        }
    }

    pub fn to_bytes(&self) -> Bytes {
        let mut buf = BytesMut::with_capacity(Self::SIZE);
        buf.put_u16_le(self.software_version);
        buf.put_u16_le(self.min_protocol_version);
        buf.put_u16_le(self.max_protocol_version);
        buf.put_u16_le(self.reserved1);
        buf.put_u32_le(self.max_width);
        buf.put_u32_le(self.max_height);
        buf.put_u32_le(self.max_fps_fixed);
        buf.put_u32_le(self.capabilities);
        buf.put_u32_le(self.reserved2);
        buf.freeze()
    }

    pub fn parse(data: &[u8]) -> Result<Self, ProtocolError> {
        if data.len() < Self::SIZE {
            return Err(ProtocolError::InvalidPayloadLength {
                expected: Self::SIZE,
                actual: data.len(),
            });
        }

        let mut buf = data;
        Ok(Self {
            software_version: buf.get_u16_le(),
            min_protocol_version: buf.get_u16_le(),
            max_protocol_version: buf.get_u16_le(),
            reserved1: buf.get_u16_le(),
            max_width: buf.get_u32_le(),
            max_height: buf.get_u32_le(),
            max_fps_fixed: buf.get_u32_le(),
            capabilities: buf.get_u32_le(),
            reserved2: buf.get_u32_le(),
        })
    }

    /// Get max FPS as integer (extracts whole part from fixed 16.16)
    pub fn max_fps(&self) -> u32 {
        self.max_fps_fixed >> 16
    }

    /// Check if HiDPI capability is set
    pub fn supports_hidpi(&self) -> bool {
        self.capabilities & 0x01 != 0
    }

    /// Check if audio capability is set
    pub fn supports_audio(&self) -> bool {
        self.capabilities & 0x02 != 0
    }
}

/// START payload (24 bytes)
#[derive(Debug, Clone)]
pub struct StartPayload {
    pub width: u32,
    pub height: u32,
    pub fps_fixed: u32, // Fixed-point 16.16
    pub bitrate_bps: u32,
    pub pixel_format: u8,
    pub audio_enabled: u8,
    pub audio_sample_rate: u16,
    pub audio_channels: u8,
    pub audio_bits: u8,
    pub reserved: u16,
}

impl StartPayload {
    pub const SIZE: usize = 24;

    pub fn new(width: u32, height: u32, fps: u32, bitrate_bps: u32) -> Self {
        Self {
            width,
            height,
            fps_fixed: fps << 16,
            bitrate_bps,
            pixel_format: 0, // NV12
            audio_enabled: 0,
            audio_sample_rate: 0,
            audio_channels: 0,
            audio_bits: 0,
            reserved: 0,
        }
    }

    pub fn to_bytes(&self) -> Bytes {
        let mut buf = BytesMut::with_capacity(Self::SIZE);
        buf.put_u32_le(self.width);
        buf.put_u32_le(self.height);
        buf.put_u32_le(self.fps_fixed);
        buf.put_u32_le(self.bitrate_bps);
        buf.put_u8(self.pixel_format);
        buf.put_u8(self.audio_enabled);
        buf.put_u16_le(self.audio_sample_rate);
        buf.put_u8(self.audio_channels);
        buf.put_u8(self.audio_bits);
        buf.put_u16_le(self.reserved);
        buf.freeze()
    }

    pub fn parse(data: &[u8]) -> Result<Self, ProtocolError> {
        if data.len() < Self::SIZE {
            return Err(ProtocolError::InvalidPayloadLength {
                expected: Self::SIZE,
                actual: data.len(),
            });
        }

        let mut buf = data;
        let width = buf.get_u32_le();
        let height = buf.get_u32_le();
        let fps_fixed = buf.get_u32_le();
        let bitrate_bps = buf.get_u32_le();
        let pixel_format = buf.get_u8();
        let audio_enabled = buf.get_u8();
        let audio_sample_rate = buf.get_u16_le();
        let audio_channels = buf.get_u8();
        let audio_bits = buf.get_u8();
        let reserved = buf.get_u16_le();

        // Validate dimensions
        if width == 0 || height == 0 {
            return Err(ProtocolError::InvalidPayloadLength {
                expected: 1, // minimum dimension
                actual: 0,
            });
        }

        Ok(Self {
            width,
            height,
            fps_fixed,
            bitrate_bps,
            pixel_format,
            audio_enabled,
            audio_sample_rate,
            audio_channels,
            audio_bits,
            reserved,
        })
    }

    /// Get FPS as integer
    pub fn fps(&self) -> u32 {
        self.fps_fixed >> 16
    }
}

/// START_ACK payload (4 bytes)
#[derive(Debug, Clone)]
pub struct StartAckPayload {
    pub status: u8,
    pub reserved: u8,
    pub initial_credits: u16,
}

impl StartAckPayload {
    pub const SIZE: usize = 4;
    pub const DEFAULT_CREDITS: u16 = 8;

    pub fn new(status: u8, initial_credits: u16) -> Self {
        Self {
            status,
            reserved: 0,
            initial_credits,
        }
    }

    pub fn ok(initial_credits: u16) -> Self {
        Self::new(0, initial_credits)
    }

    pub fn to_bytes(&self) -> Bytes {
        let mut buf = BytesMut::with_capacity(Self::SIZE);
        buf.put_u8(self.status);
        buf.put_u8(self.reserved);
        buf.put_u16_le(self.initial_credits);
        buf.freeze()
    }

    pub fn parse(data: &[u8]) -> Result<Self, ProtocolError> {
        if data.len() < Self::SIZE {
            return Err(ProtocolError::InvalidPayloadLength {
                expected: Self::SIZE,
                actual: data.len(),
            });
        }

        let mut buf = data;
        Ok(Self {
            status: buf.get_u8(),
            reserved: buf.get_u8(),
            initial_credits: buf.get_u16_le(),
        })
    }

    pub fn is_ok(&self) -> bool {
        self.status == 0
    }
}

/// FRAME header (32 bytes, precedes encoded data)
#[derive(Debug, Clone)]
pub struct FrameHeader {
    pub frame_number: u64,
    pub pts_us: u64,
    pub capture_ts_us: u64,
    pub frame_size: u32,
    pub segment_index: u16,
    pub segment_count: u16,
}

impl FrameHeader {
    pub const SIZE: usize = 32;

    pub fn new(
        frame_number: u64,
        pts_us: u64,
        capture_ts_us: u64,
        frame_size: u32,
        segment_index: u16,
        segment_count: u16,
    ) -> Self {
        Self {
            frame_number,
            pts_us,
            capture_ts_us,
            frame_size,
            segment_index,
            segment_count,
        }
    }

    pub fn to_bytes(&self) -> Bytes {
        let mut buf = BytesMut::with_capacity(Self::SIZE);
        buf.put_u64_le(self.frame_number);
        buf.put_u64_le(self.pts_us);
        buf.put_u64_le(self.capture_ts_us);
        buf.put_u32_le(self.frame_size);
        buf.put_u16_le(self.segment_index);
        buf.put_u16_le(self.segment_count);
        buf.freeze()
    }

    pub fn parse(data: &[u8]) -> Result<Self, ProtocolError> {
        if data.len() < Self::SIZE {
            return Err(ProtocolError::InvalidPayloadLength {
                expected: Self::SIZE,
                actual: data.len(),
            });
        }

        let mut buf = data;
        let frame_number = buf.get_u64_le();
        let pts_us = buf.get_u64_le();
        let capture_ts_us = buf.get_u64_le();
        let frame_size = buf.get_u32_le();
        let segment_index = buf.get_u16_le();
        let segment_count = buf.get_u16_le();

        // Validate segment_index < segment_count
        if segment_count == 0 {
            return Err(ProtocolError::FrameReassemblyError(
                "segment_count cannot be zero".to_string(),
            ));
        }
        if segment_index >= segment_count {
            return Err(ProtocolError::FrameReassemblyError(format!(
                "segment_index ({}) must be less than segment_count ({})",
                segment_index, segment_count
            )));
        }

        Ok(Self {
            frame_number,
            pts_us,
            capture_ts_us,
            frame_size,
            segment_index,
            segment_count,
        })
    }
}

/// FRAME_ACK payload (16 bytes)
#[derive(Debug, Clone)]
pub struct FrameAckPayload {
    pub frame_number: u64,
    pub decode_time_us: u32,
    pub credits_returned: u16,
    pub reserved: u16,
}

impl FrameAckPayload {
    pub const SIZE: usize = 16;

    pub fn new(frame_number: u64, decode_time_us: u32, credits_returned: u16) -> Self {
        Self {
            frame_number,
            decode_time_us,
            credits_returned,
            reserved: 0,
        }
    }

    pub fn to_bytes(&self) -> Bytes {
        let mut buf = BytesMut::with_capacity(Self::SIZE);
        buf.put_u64_le(self.frame_number);
        buf.put_u32_le(self.decode_time_us);
        buf.put_u16_le(self.credits_returned);
        buf.put_u16_le(self.reserved);
        buf.freeze()
    }

    pub fn parse(data: &[u8]) -> Result<Self, ProtocolError> {
        if data.len() < Self::SIZE {
            return Err(ProtocolError::InvalidPayloadLength {
                expected: Self::SIZE,
                actual: data.len(),
            });
        }

        let mut buf = data;
        Ok(Self {
            frame_number: buf.get_u64_le(),
            decode_time_us: buf.get_u32_le(),
            credits_returned: buf.get_u16_le(),
            reserved: buf.get_u16_le(),
        })
    }
}

/// PING payload (8 bytes)
#[derive(Debug, Clone)]
pub struct PingPayload {
    pub timestamp_us: u64,
}

impl PingPayload {
    pub const SIZE: usize = 8;

    pub fn new(timestamp_us: u64) -> Self {
        Self { timestamp_us }
    }

    pub fn to_bytes(&self) -> Bytes {
        let mut buf = BytesMut::with_capacity(Self::SIZE);
        buf.put_u64_le(self.timestamp_us);
        buf.freeze()
    }

    pub fn parse(data: &[u8]) -> Result<Self, ProtocolError> {
        if data.len() < Self::SIZE {
            return Err(ProtocolError::InvalidPayloadLength {
                expected: Self::SIZE,
                actual: data.len(),
            });
        }

        let mut buf = data;
        Ok(Self {
            timestamp_us: buf.get_u64_le(),
        })
    }
}

/// PONG payload (16 bytes)
#[derive(Debug, Clone)]
pub struct PongPayload {
    pub ping_timestamp_us: u64,
    pub pong_timestamp_us: u64,
}

impl PongPayload {
    pub const SIZE: usize = 16;

    pub fn new(ping_timestamp_us: u64, pong_timestamp_us: u64) -> Self {
        Self {
            ping_timestamp_us,
            pong_timestamp_us,
        }
    }

    pub fn to_bytes(&self) -> Bytes {
        let mut buf = BytesMut::with_capacity(Self::SIZE);
        buf.put_u64_le(self.ping_timestamp_us);
        buf.put_u64_le(self.pong_timestamp_us);
        buf.freeze()
    }

    pub fn parse(data: &[u8]) -> Result<Self, ProtocolError> {
        if data.len() < Self::SIZE {
            return Err(ProtocolError::InvalidPayloadLength {
                expected: Self::SIZE,
                actual: data.len(),
            });
        }

        let mut buf = data;
        Ok(Self {
            ping_timestamp_us: buf.get_u64_le(),
            pong_timestamp_us: buf.get_u64_le(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_packet_roundtrip() {
        let payload = HelloPayload::new(1, 3840, 2160, 60, 0x03);
        let packet = Packet::new(PacketType::Hello, 0, 1, payload.to_bytes());
        let bytes = packet.to_bytes();

        let (parsed, consumed) = Packet::parse(&bytes).unwrap();
        assert_eq!(consumed, bytes.len());
        assert_eq!(parsed.header.packet_type, PacketType::Hello);
        assert_eq!(parsed.header.sequence, 1);
        assert_eq!(parsed.payload, payload.to_bytes());
    }

    #[test]
    fn test_invalid_magic() {
        let mut bytes = BytesMut::new();
        bytes.put_u32_le(0x12345678); // Wrong magic
        bytes.put_u8(1);
        bytes.put_u8(0x01);
        bytes.put_u16_le(0);
        bytes.put_u32_le(0);
        bytes.put_u32_le(0);
        bytes.put_u32_le(0); // CRC (will be wrong anyway)

        let result = Packet::parse(&bytes);
        assert!(matches!(result, Err(ProtocolError::InvalidMagic(0x12345678))));
    }

    #[test]
    fn test_checksum_mismatch() {
        let payload = Bytes::from_static(b"test");
        let packet = Packet::new(PacketType::Ping, 0, 1, payload);
        let mut bytes = packet.to_bytes().to_vec();

        // Corrupt a byte
        bytes[HEADER_SIZE] ^= 0xFF;

        let result = Packet::parse(&bytes);
        assert!(matches!(
            result,
            Err(ProtocolError::ChecksumMismatch { .. })
        ));
    }

    #[test]
    fn test_hello_payload() {
        let payload = HelloPayload::new(1, 3840, 2160, 60, 0x03);
        assert_eq!(payload.max_fps(), 60);
        assert!(payload.supports_hidpi());
        assert!(payload.supports_audio());

        let bytes = payload.to_bytes();
        let parsed = HelloPayload::parse(&bytes).unwrap();
        assert_eq!(parsed.software_version, 1);
        assert_eq!(parsed.max_width, 3840);
        assert_eq!(parsed.max_height, 2160);
        assert_eq!(parsed.max_fps(), 60);
    }

    #[test]
    fn test_start_payload() {
        let payload = StartPayload::new(1920, 1080, 60, 20_000_000);
        assert_eq!(payload.fps(), 60);

        let bytes = payload.to_bytes();
        let parsed = StartPayload::parse(&bytes).unwrap();
        assert_eq!(parsed.width, 1920);
        assert_eq!(parsed.height, 1080);
        assert_eq!(parsed.fps(), 60);
        assert_eq!(parsed.bitrate_bps, 20_000_000);
    }

    #[test]
    fn test_frame_header() {
        let header = FrameHeader::new(42, 1000000, 1000100, 65536, 0, 2);
        let bytes = header.to_bytes();
        let parsed = FrameHeader::parse(&bytes).unwrap();
        assert_eq!(parsed.frame_number, 42);
        assert_eq!(parsed.pts_us, 1000000);
        assert_eq!(parsed.segment_count, 2);
    }

    #[test]
    fn test_frame_ack_payload() {
        let payload = FrameAckPayload::new(42, 500, 2);
        let bytes = payload.to_bytes();
        let parsed = FrameAckPayload::parse(&bytes).unwrap();
        assert_eq!(parsed.frame_number, 42);
        assert_eq!(parsed.decode_time_us, 500);
        assert_eq!(parsed.credits_returned, 2);
    }
}
