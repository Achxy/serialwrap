use thiserror::Error;

/// Protocol-level errors
#[derive(Debug, Error)]
pub enum ProtocolError {
    #[error("invalid magic: expected 0x53575250, got 0x{0:08X}")]
    InvalidMagic(u32),

    #[error("checksum mismatch: expected 0x{expected:08X}, got 0x{actual:08X}")]
    ChecksumMismatch { expected: u32, actual: u32 },

    #[error("unsupported protocol version: {0}")]
    UnsupportedVersion(u8),

    #[error("unknown packet type: 0x{0:02X}")]
    UnknownPacketType(u8),

    #[error("invalid payload length: expected {expected}, got {actual}")]
    InvalidPayloadLength { expected: usize, actual: usize },

    #[error("buffer too short: need {needed} bytes, have {available}")]
    BufferTooShort { needed: usize, available: usize },

    #[error("invalid sequence number: expected {expected}, got {actual}")]
    InvalidSequence { expected: u32, actual: u32 },

    #[error("unexpected packet type: expected {expected}, got {actual}")]
    UnexpectedPacketType { expected: &'static str, actual: u8 },

    #[error("handshake failed: {0}")]
    HandshakeFailed(String),

    #[error("frame reassembly error: {0}")]
    FrameReassemblyError(String),
}

/// Transport-level errors
#[derive(Debug, Error)]
pub enum TransportError {
    #[error("device not found")]
    DeviceNotFound,

    #[error("device disconnected")]
    Disconnected,

    #[error("operation timed out after {duration_ms}ms")]
    Timeout { duration_ms: u64 },

    #[error("USB error: {0}")]
    UsbError(String),

    #[error("I/O error: {0}")]
    IoError(String),

    #[error("connection refused")]
    ConnectionRefused,

    #[error("channel closed")]
    ChannelClosed,
}

/// Video encoding errors (macOS only)
#[derive(Debug, Error)]
pub enum EncodeError {
    #[error("encoder session creation failed with status: {0}")]
    SessionCreationFailed(i32),

    #[error("encoding frame failed with status: {0}")]
    EncodingFailed(i32),

    #[error("flushing encoder failed with status: {0}")]
    FlushFailed(i32),

    #[error("property setting failed: {property} with status {status}")]
    PropertySetFailed { property: String, status: i32 },

    #[error("invalid pixel buffer")]
    InvalidPixelBuffer,

    #[error("no output available")]
    NoOutput,

    #[error("encoder not ready")]
    NotReady,

    #[error("invalid input: {0}")]
    InvalidInput(String),

    #[error("pixel buffer operation failed with status: {0}")]
    PixelBufferFailed(i32),
}

/// Video decoding errors
#[derive(Debug, Error)]
pub enum DecodeError {
    #[error("H.264 codec not found")]
    CodecNotFound,

    #[error("failed to create decoder context")]
    ContextCreationFailed,

    #[error("failed to open decoder")]
    OpenFailed,

    #[error("decoding failed: {0}")]
    DecodingFailed(String),

    #[error("frame conversion failed")]
    ConversionFailed,

    #[error("invalid frame data")]
    InvalidFrameData,

    #[error("ffmpeg error: {0}")]
    FfmpegError(String),
}

/// Screen capture errors (macOS only)
#[derive(Debug, Error)]
pub enum CaptureError {
    #[error("display not found: {0}")]
    DisplayNotFound(u32),

    #[error("capture stream creation failed")]
    StreamCreationFailed,

    #[error("capture permission denied")]
    PermissionDenied,

    #[error("capture configuration invalid: {0}")]
    InvalidConfiguration(String),

    #[error("capture failed: {0}")]
    CaptureFailed(String),
}

/// Virtual display errors (macOS only)
#[derive(Debug, Error)]
pub enum DisplayError {
    #[error("virtual display creation failed")]
    CreationFailed,

    #[error("display configuration invalid: {0}")]
    InvalidConfiguration(String),

    #[error("display already exists")]
    AlreadyExists,

    #[error("display not available")]
    NotAvailable,
}

/// Rendering errors
#[derive(Debug, Error)]
pub enum RenderError {
    #[error("SDL initialization failed: {0}")]
    SdlInitFailed(String),

    #[error("window creation failed: {0}")]
    WindowCreationFailed(String),

    #[error("renderer creation failed: {0}")]
    RendererCreationFailed(String),

    #[error("texture creation failed: {0}")]
    TextureCreationFailed(String),

    #[error("texture update failed: {0}")]
    TextureUpdateFailed(String),

    #[error("render failed: {0}")]
    RenderFailed(String),
}
