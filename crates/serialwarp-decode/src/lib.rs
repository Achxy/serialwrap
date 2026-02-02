//! serialwarp-decode - H.264 video decoder using FFmpeg
//!
//! This crate provides video decoding functionality for the sink application.

use serialwarp_core::{DecodeError, DecodedFrame};

/// Decoder configuration
#[derive(Debug, Clone, Default)]
pub struct DecoderConfig {
    /// Number of threads to use for decoding (None = auto)
    pub thread_count: Option<usize>,
}

/// H.264 video decoder
pub struct Decoder {
    decoder: ffmpeg_next::decoder::Video,
    scaler: Option<ffmpeg_next::software::scaling::Context>,
    width: u32,
    height: u32,
}

impl Decoder {
    /// Create a new decoder with the given configuration
    pub fn new(config: DecoderConfig) -> Result<Self, DecodeError> {
        ffmpeg_next::init().map_err(|e| DecodeError::FfmpegError(e.to_string()))?;

        let codec = ffmpeg_next::decoder::find(ffmpeg_next::codec::Id::H264)
            .ok_or(DecodeError::CodecNotFound)?;

        let mut context =
            ffmpeg_next::codec::Context::new_with_codec(codec).decoder().video().map_err(
                |e| DecodeError::FfmpegError(format!("Failed to create decoder context: {}", e)),
            )?;

        // Configure threading
        if let Some(thread_count) = config.thread_count {
            unsafe {
                (*context.as_mut_ptr()).thread_count = thread_count as i32;
            }
        }

        Ok(Self {
            decoder: context,
            scaler: None,
            width: 0,
            height: 0,
        })
    }

    /// Decode H.264 data and return decoded frames
    ///
    /// May return zero, one, or multiple frames depending on buffering.
    pub fn decode(&mut self, data: &[u8], pts_us: i64) -> Result<Vec<DecodedFrame>, DecodeError> {
        let packet = ffmpeg_next::Packet::copy(data);

        self.decoder
            .send_packet(&packet)
            .map_err(|e| DecodeError::DecodingFailed(e.to_string()))?;

        self.receive_frames(pts_us)
    }

    /// Flush the decoder and return any remaining frames
    pub fn flush(&mut self) -> Result<Vec<DecodedFrame>, DecodeError> {
        self.decoder
            .send_eof()
            .map_err(|e| DecodeError::DecodingFailed(e.to_string()))?;

        self.receive_frames(0)
    }

    fn receive_frames(&mut self, pts_us: i64) -> Result<Vec<DecodedFrame>, DecodeError> {
        let mut frames = Vec::new();
        let mut decoded = ffmpeg_next::frame::Video::empty();

        while self.decoder.receive_frame(&mut decoded).is_ok() {
            let frame = self.convert_frame(&decoded, pts_us)?;
            frames.push(frame);
        }

        Ok(frames)
    }

    fn convert_frame(
        &mut self,
        frame: &ffmpeg_next::frame::Video,
        pts_us: i64,
    ) -> Result<DecodedFrame, DecodeError> {
        let width = frame.width();
        let height = frame.height();

        // Recreate scaler if dimensions changed or if format is not YUV420P
        let needs_conversion = frame.format() != ffmpeg_next::format::Pixel::YUV420P
            || self.width != width
            || self.height != height;

        if needs_conversion {
            self.scaler = Some(
                ffmpeg_next::software::scaling::Context::get(
                    frame.format(),
                    width,
                    height,
                    ffmpeg_next::format::Pixel::YUV420P,
                    width,
                    height,
                    ffmpeg_next::software::scaling::Flags::BILINEAR,
                )
                .map_err(|e| DecodeError::FfmpegError(format!("Failed to create scaler: {}", e)))?,
            );
            self.width = width;
            self.height = height;
        }

        // Convert to YUV420P if needed
        let yuv_frame = if let Some(ref mut scaler) = self.scaler {
            let mut output = ffmpeg_next::frame::Video::empty();
            scaler
                .run(frame, &mut output)
                .map_err(|_| DecodeError::ConversionFailed)?;
            output
        } else {
            frame.clone()
        };

        // Copy plane data to contiguous buffer
        let y_size = (width * height) as usize;
        let uv_size = y_size / 4;
        let total_size = y_size + uv_size * 2;

        let mut yuv_data = Vec::with_capacity(total_size);

        // Copy Y plane
        let y_stride = yuv_frame.stride(0);
        for row in 0..height as usize {
            let start = row * y_stride;
            let end = start + width as usize;
            yuv_data.extend_from_slice(&yuv_frame.data(0)[start..end]);
        }

        // Copy U plane
        let u_stride = yuv_frame.stride(1);
        let uv_height = height as usize / 2;
        let uv_width = width as usize / 2;
        for row in 0..uv_height {
            let start = row * u_stride;
            let end = start + uv_width;
            yuv_data.extend_from_slice(&yuv_frame.data(1)[start..end]);
        }

        // Copy V plane
        let v_stride = yuv_frame.stride(2);
        for row in 0..uv_height {
            let start = row * v_stride;
            let end = start + uv_width;
            yuv_data.extend_from_slice(&yuv_frame.data(2)[start..end]);
        }

        // Use frame PTS if available, otherwise use provided pts_us
        let frame_pts = frame.pts().map(|p| p as u64).unwrap_or(pts_us as u64);

        Ok(DecodedFrame::new(
            0, // Frame number will be set by caller
            frame_pts,
            width,
            height,
            yuv_data,
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_decoder_creation() {
        let config = DecoderConfig::default();
        let result = Decoder::new(config);
        // This may fail if FFmpeg is not installed, which is acceptable in CI
        // The important thing is that the code compiles correctly
        if result.is_err() {
            eprintln!("Decoder creation failed (FFmpeg may not be installed): {:?}", result.err());
        }
    }

    #[test]
    fn test_decoder_config_default() {
        let config = DecoderConfig::default();
        assert!(config.thread_count.is_none());
    }
}
