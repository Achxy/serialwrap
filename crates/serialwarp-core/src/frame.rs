use bytes::{BufMut, Bytes, BytesMut};

use crate::protocol::{FrameHeader, MAX_SEGMENT_SIZE};

/// Metadata for a captured/encoded frame
#[derive(Debug, Clone)]
pub struct FrameMetadata {
    pub frame_number: u64,
    pub pts_us: u64,
    pub capture_ts_us: u64,
    pub is_keyframe: bool,
}

impl FrameMetadata {
    pub fn new(frame_number: u64, pts_us: u64, capture_ts_us: u64, is_keyframe: bool) -> Self {
        Self {
            frame_number,
            pts_us,
            capture_ts_us,
            is_keyframe,
        }
    }
}

/// An encoded video frame ready for transmission
#[derive(Debug, Clone)]
pub struct EncodedFrame {
    pub metadata: FrameMetadata,
    pub data: Vec<u8>,
}

impl EncodedFrame {
    pub fn new(metadata: FrameMetadata, data: Vec<u8>) -> Self {
        Self { metadata, data }
    }

    /// Split frame into segments for transmission
    /// Each segment is at most MAX_SEGMENT_SIZE bytes
    ///
    /// # Panics
    /// Panics if frame data exceeds ~4GB (u16::MAX * MAX_SEGMENT_SIZE)
    pub fn into_segments(self) -> Vec<FrameSegment> {
        let total_size = self.data.len();
        let segment_count = (total_size + MAX_SEGMENT_SIZE - 1) / MAX_SEGMENT_SIZE;
        let segment_count = segment_count.max(1);

        // Validate segment count fits in u16
        assert!(
            segment_count <= u16::MAX as usize,
            "Frame too large: requires {} segments (max {})",
            segment_count,
            u16::MAX
        );
        let segment_count = segment_count as u16;

        if segment_count == 1 {
            return vec![FrameSegment {
                metadata: self.metadata,
                frame_size: total_size as u32,
                segment_index: 0,
                segment_count: 1,
                data: self.data,
            }];
        }

        let mut segments = Vec::with_capacity(segment_count as usize);
        let mut offset = 0;

        for i in 0..segment_count {
            let segment_end = (offset + MAX_SEGMENT_SIZE).min(total_size);
            let segment_data = self.data[offset..segment_end].to_vec();

            segments.push(FrameSegment {
                metadata: self.metadata.clone(),
                frame_size: total_size as u32,
                segment_index: i,
                segment_count,
                data: segment_data,
            });

            offset = segment_end;
        }

        segments
    }
}

/// A segment of an encoded frame for transmission
#[derive(Debug, Clone)]
pub struct FrameSegment {
    pub metadata: FrameMetadata,
    pub frame_size: u32,
    pub segment_index: u16,
    pub segment_count: u16,
    pub data: Vec<u8>,
}

impl FrameSegment {
    /// Create the FRAME packet payload (header + data)
    pub fn to_payload(&self) -> Bytes {
        let header = FrameHeader::new(
            self.metadata.frame_number,
            self.metadata.pts_us,
            self.metadata.capture_ts_us,
            self.frame_size,
            self.segment_index,
            self.segment_count,
        );

        let mut buf = BytesMut::with_capacity(FrameHeader::SIZE + self.data.len());
        buf.put(header.to_bytes());
        buf.put_slice(&self.data);
        buf.freeze()
    }
}

/// Reassembles frame segments into complete frames
#[derive(Debug)]
pub struct FrameReassembler {
    pending: Option<PendingFrame>,
}

#[derive(Debug)]
struct PendingFrame {
    frame_number: u64,
    pts_us: u64,
    capture_ts_us: u64,
    frame_size: u32,
    segment_count: u16,
    received_segments: Vec<Option<Vec<u8>>>,
    received_count: u16,
}

impl FrameReassembler {
    pub fn new() -> Self {
        Self { pending: None }
    }

    /// Add a segment. Returns the complete frame if all segments have been received.
    pub fn add_segment(&mut self, header: &FrameHeader, data: Vec<u8>) -> Option<EncodedFrame> {
        // Check if this is a new frame
        if self.pending.is_none()
            || self.pending.as_ref().unwrap().frame_number != header.frame_number
        {
            // Start new frame reassembly
            let mut received_segments = vec![None; header.segment_count as usize];
            received_segments[header.segment_index as usize] = Some(data);

            self.pending = Some(PendingFrame {
                frame_number: header.frame_number,
                pts_us: header.pts_us,
                capture_ts_us: header.capture_ts_us,
                frame_size: header.frame_size,
                segment_count: header.segment_count,
                received_segments,
                received_count: 1,
            });

            if header.segment_count == 1 {
                return self.complete_frame();
            }
            return None;
        }

        // Add to existing frame
        let pending = self.pending.as_mut().unwrap();

        if pending.received_segments[header.segment_index as usize].is_some() {
            // Duplicate segment, ignore
            return None;
        }

        pending.received_segments[header.segment_index as usize] = Some(data);
        pending.received_count += 1;

        if pending.received_count == pending.segment_count {
            return self.complete_frame();
        }

        None
    }

    fn complete_frame(&mut self) -> Option<EncodedFrame> {
        let pending = self.pending.take()?;

        let mut data = Vec::with_capacity(pending.frame_size as usize);
        for segment_data in pending.received_segments.into_iter().flatten() {
            data.extend_from_slice(&segment_data);
        }

        Some(EncodedFrame::new(
            FrameMetadata::new(
                pending.frame_number,
                pending.pts_us,
                pending.capture_ts_us,
                false, // We don't track keyframe status during reassembly
            ),
            data,
        ))
    }

    /// Clear any pending incomplete frame
    pub fn reset(&mut self) {
        self.pending = None;
    }
}

impl Default for FrameReassembler {
    fn default() -> Self {
        Self::new()
    }
}

/// A decoded video frame ready for rendering
#[derive(Debug, Clone)]
pub struct DecodedFrame {
    pub frame_number: u64,
    pub pts_us: u64,
    pub width: u32,
    pub height: u32,
    /// YUV420P data: Y plane followed by U plane followed by V plane
    yuv_data: Vec<u8>,
}

impl DecodedFrame {
    pub fn new(frame_number: u64, pts_us: u64, width: u32, height: u32, yuv_data: Vec<u8>) -> Self {
        Self {
            frame_number,
            pts_us,
            width,
            height,
            yuv_data,
        }
    }

    /// Get the Y (luma) plane
    pub fn y_plane(&self) -> &[u8] {
        let y_size = (self.width * self.height) as usize;
        &self.yuv_data[..y_size]
    }

    /// Get the U (chroma-blue) plane
    pub fn u_plane(&self) -> &[u8] {
        let y_size = (self.width * self.height) as usize;
        let uv_size = y_size / 4;
        &self.yuv_data[y_size..y_size + uv_size]
    }

    /// Get the V (chroma-red) plane
    pub fn v_plane(&self) -> &[u8] {
        let y_size = (self.width * self.height) as usize;
        let uv_size = y_size / 4;
        &self.yuv_data[y_size + uv_size..]
    }

    /// Get stride for Y plane (bytes per row)
    pub fn y_stride(&self) -> usize {
        self.width as usize
    }

    /// Get stride for U/V planes (bytes per row)
    pub fn uv_stride(&self) -> usize {
        (self.width / 2) as usize
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_single_segment() {
        let metadata = FrameMetadata::new(1, 1000, 1000, true);
        let data = vec![0u8; 1024]; // Small frame, single segment
        let frame = EncodedFrame::new(metadata, data);

        let segments = frame.into_segments();
        assert_eq!(segments.len(), 1);
        assert_eq!(segments[0].segment_index, 0);
        assert_eq!(segments[0].segment_count, 1);
    }

    #[test]
    fn test_multiple_segments() {
        let metadata = FrameMetadata::new(1, 1000, 1000, true);
        let data = vec![0u8; 200_000]; // 200KB, should be ~4 segments
        let frame = EncodedFrame::new(metadata, data.clone());

        let segments = frame.into_segments();
        assert_eq!(segments.len(), 4);

        // Verify all segments have correct metadata
        for (i, segment) in segments.iter().enumerate() {
            assert_eq!(segment.segment_index, i as u16);
            assert_eq!(segment.segment_count, 4);
            assert_eq!(segment.frame_size, 200_000);
        }

        // Verify total data
        let mut reassembled = Vec::new();
        for segment in segments {
            reassembled.extend_from_slice(&segment.data);
        }
        assert_eq!(reassembled, data);
    }

    #[test]
    fn test_frame_reassembly() {
        let metadata = FrameMetadata::new(1, 1000, 1000, true);
        let original_data = vec![42u8; 200_000];
        let frame = EncodedFrame::new(metadata, original_data.clone());
        let segments = frame.into_segments();

        let mut reassembler = FrameReassembler::new();

        // Add segments in order
        for segment in &segments[..segments.len() - 1] {
            let header = FrameHeader::new(
                segment.metadata.frame_number,
                segment.metadata.pts_us,
                segment.metadata.capture_ts_us,
                segment.frame_size,
                segment.segment_index,
                segment.segment_count,
            );
            let result = reassembler.add_segment(&header, segment.data.clone());
            assert!(result.is_none());
        }

        // Add last segment - should complete
        let last = segments.last().unwrap();
        let header = FrameHeader::new(
            last.metadata.frame_number,
            last.metadata.pts_us,
            last.metadata.capture_ts_us,
            last.frame_size,
            last.segment_index,
            last.segment_count,
        );
        let result = reassembler.add_segment(&header, last.data.clone());
        assert!(result.is_some());

        let reassembled = result.unwrap();
        assert_eq!(reassembled.data, original_data);
    }

    #[test]
    fn test_decoded_frame_planes() {
        // 4x4 YUV420P frame
        let width = 4u32;
        let height = 4u32;
        let y_size = (width * height) as usize; // 16
        let uv_size = y_size / 4; // 4

        let mut yuv_data = Vec::with_capacity(y_size + uv_size * 2);
        yuv_data.extend(vec![1u8; y_size]); // Y plane
        yuv_data.extend(vec![2u8; uv_size]); // U plane
        yuv_data.extend(vec![3u8; uv_size]); // V plane

        let frame = DecodedFrame::new(1, 1000, width, height, yuv_data);

        assert_eq!(frame.y_plane().len(), 16);
        assert_eq!(frame.u_plane().len(), 4);
        assert_eq!(frame.v_plane().len(), 4);
        assert!(frame.y_plane().iter().all(|&b| b == 1));
        assert!(frame.u_plane().iter().all(|&b| b == 2));
        assert!(frame.v_plane().iter().all(|&b| b == 3));
    }
}
