//! serialwarp-encode - macOS H.264 encoding using VideoToolbox
//!
//! This crate provides video encoding functionality for macOS using
//! the VideoToolbox framework for hardware-accelerated H.264 encoding.

#![cfg(target_os = "macos")]

use serialwarp_core::{EncodeError, EncodedFrame, FrameMetadata};
use std::ffi::c_void;
use std::ptr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use tokio::sync::mpsc;

/// Encoder configuration
#[derive(Debug, Clone)]
pub struct EncoderConfig {
    /// Video width in pixels
    pub width: u32,
    /// Video height in pixels
    pub height: u32,
    /// Target frames per second
    pub fps: u32,
    /// Target bitrate in bits per second
    pub bitrate_bps: u32,
    /// Keyframe interval (GOP size)
    pub keyframe_interval: u32,
    /// Enable low-latency mode
    pub low_latency: bool,
}

impl Default for EncoderConfig {
    fn default() -> Self {
        Self {
            width: 1920,
            height: 1080,
            fps: 60,
            bitrate_bps: 20_000_000,
            keyframe_interval: 30,
            low_latency: true,
        }
    }
}

// CoreFoundation types
type CFAllocatorRef = *const c_void;
type CFTypeRef = *const c_void;
type CFStringRef = *const c_void;
type CFNumberRef = *const c_void;
type CFBooleanRef = *const c_void;
type CFDictionaryRef = *const c_void;
type CFMutableDictionaryRef = *mut c_void;
type CFArrayRef = *const c_void;

// CoreMedia types
type CMTime = CMTimeStruct;
type CMSampleBufferRef = *const c_void;
type CMBlockBufferRef = *const c_void;
type CMFormatDescriptionRef = *const c_void;

// CoreVideo types
type CVPixelBufferRef = *const c_void;
type CVPixelBufferPoolRef = *const c_void;

// VideoToolbox types
type VTCompressionSessionRef = *mut c_void;
type VTEncodeInfoFlags = u32;

#[repr(C)]
#[derive(Clone, Copy)]
struct CMTimeStruct {
    value: i64,
    timescale: i32,
    flags: u32,
    epoch: i64,
}

impl CMTimeStruct {
    fn new(value: i64, timescale: i32) -> Self {
        Self {
            value,
            timescale,
            flags: 1, // kCMTimeFlags_Valid
            epoch: 0,
        }
    }

    fn invalid() -> Self {
        Self {
            value: 0,
            timescale: 0,
            flags: 0,
            epoch: 0,
        }
    }
}

// Callback function type
type VTCompressionOutputCallback = extern "C" fn(
    output_callback_ref_con: *mut c_void,
    source_frame_ref_con: *mut c_void,
    status: i32,
    info_flags: VTEncodeInfoFlags,
    sample_buffer: CMSampleBufferRef,
);

// CoreFoundation FFI
#[link(name = "CoreFoundation", kind = "framework")]
extern "C" {
    static kCFAllocatorDefault: CFAllocatorRef;
    static kCFBooleanTrue: CFBooleanRef;
    static kCFBooleanFalse: CFBooleanRef;
    static kCFTypeDictionaryKeyCallBacks: c_void;
    static kCFTypeDictionaryValueCallBacks: c_void;

    #[allow(dead_code)]
    fn CFRetain(cf: CFTypeRef) -> CFTypeRef;
    fn CFRelease(cf: CFTypeRef);
    fn CFDictionaryCreateMutable(
        allocator: CFAllocatorRef,
        capacity: isize,
        key_callbacks: *const c_void,
        value_callbacks: *const c_void,
    ) -> CFMutableDictionaryRef;
    fn CFDictionarySetValue(
        dict: CFMutableDictionaryRef,
        key: *const c_void,
        value: *const c_void,
    );
    fn CFNumberCreate(
        allocator: CFAllocatorRef,
        the_type: i32,
        value_ptr: *const c_void,
    ) -> CFNumberRef;
}

// CoreVideo FFI
#[link(name = "CoreVideo", kind = "framework")]
extern "C" {
    static kCVPixelBufferPixelFormatTypeKey: CFStringRef;
    static kCVPixelBufferWidthKey: CFStringRef;
    static kCVPixelBufferHeightKey: CFStringRef;
    static kCVPixelBufferIOSurfacePropertiesKey: CFStringRef;

    fn CVPixelBufferCreate(
        allocator: CFAllocatorRef,
        width: usize,
        height: usize,
        pixel_format_type: u32,
        pixel_buffer_attributes: CFDictionaryRef,
        pixel_buffer_out: *mut CVPixelBufferRef,
    ) -> i32;
    fn CVPixelBufferRelease(pixel_buffer: CVPixelBufferRef);
    fn CVPixelBufferLockBaseAddress(pixel_buffer: CVPixelBufferRef, lock_flags: u64) -> i32;
    fn CVPixelBufferUnlockBaseAddress(pixel_buffer: CVPixelBufferRef, unlock_flags: u64) -> i32;
    fn CVPixelBufferGetBaseAddress(pixel_buffer: CVPixelBufferRef) -> *mut u8;
    fn CVPixelBufferGetBytesPerRow(pixel_buffer: CVPixelBufferRef) -> usize;
    fn CVPixelBufferPoolCreatePixelBuffer(
        allocator: CFAllocatorRef,
        pool: CVPixelBufferPoolRef,
        pixel_buffer_out: *mut CVPixelBufferRef,
    ) -> i32;
}

// CoreMedia FFI
#[link(name = "CoreMedia", kind = "framework")]
extern "C" {
    fn CMSampleBufferGetDataBuffer(sample_buffer: CMSampleBufferRef) -> CMBlockBufferRef;
    fn CMSampleBufferGetFormatDescription(sample_buffer: CMSampleBufferRef) -> CMFormatDescriptionRef;
    fn CMBlockBufferGetDataLength(block_buffer: CMBlockBufferRef) -> usize;
    fn CMBlockBufferCopyDataBytes(
        block_buffer: CMBlockBufferRef,
        offset_to_data: usize,
        data_length: usize,
        destination: *mut u8,
    ) -> i32;
    fn CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
        format_desc: CMFormatDescriptionRef,
        parameter_set_index: usize,
        parameter_set_ptr_out: *mut *const u8,
        parameter_set_size_out: *mut usize,
        parameter_set_count_out: *mut usize,
        nal_unit_header_length_out: *mut i32,
    ) -> i32;
    fn CMSampleBufferGetPresentationTimeStamp(sample_buffer: CMSampleBufferRef) -> CMTime;
    fn CMSampleBufferGetSampleAttachmentsArray(
        sample_buffer: CMSampleBufferRef,
        create_if_necessary: u8,
    ) -> CFArrayRef;
}

// VideoToolbox FFI
#[link(name = "VideoToolbox", kind = "framework")]
extern "C" {
    static kVTCompressionPropertyKey_RealTime: CFStringRef;
    static kVTCompressionPropertyKey_ProfileLevel: CFStringRef;
    static kVTCompressionPropertyKey_AverageBitRate: CFStringRef;
    static kVTCompressionPropertyKey_MaxKeyFrameInterval: CFStringRef;
    static kVTCompressionPropertyKey_AllowFrameReordering: CFStringRef;
    static kVTProfileLevel_H264_High_AutoLevel: CFStringRef;
    #[allow(dead_code)]
    static kVTProfileLevel_H264_Baseline_AutoLevel: CFStringRef;
    static kCMSampleAttachmentKey_NotSync: CFStringRef;

    fn VTCompressionSessionCreate(
        allocator: CFAllocatorRef,
        width: i32,
        height: i32,
        codec_type: u32,
        encoder_specification: CFDictionaryRef,
        source_image_buffer_attributes: CFDictionaryRef,
        compressed_data_allocator: CFAllocatorRef,
        output_callback: VTCompressionOutputCallback,
        output_callback_ref_con: *mut c_void,
        compression_session_out: *mut VTCompressionSessionRef,
    ) -> i32;
    fn VTCompressionSessionInvalidate(session: VTCompressionSessionRef);
    fn VTSessionSetProperty(
        session: VTCompressionSessionRef,
        property_key: CFStringRef,
        property_value: CFTypeRef,
    ) -> i32;
    fn VTCompressionSessionPrepareToEncodeFrames(session: VTCompressionSessionRef) -> i32;
    fn VTCompressionSessionEncodeFrame(
        session: VTCompressionSessionRef,
        image_buffer: CVPixelBufferRef,
        presentation_time_stamp: CMTime,
        duration: CMTime,
        frame_properties: CFDictionaryRef,
        source_frame_ref_con: *mut c_void,
        info_flags_out: *mut VTEncodeInfoFlags,
    ) -> i32;
    fn VTCompressionSessionCompleteFrames(
        session: VTCompressionSessionRef,
        complete_until_presentation_time_stamp: CMTime,
    ) -> i32;
    fn VTCompressionSessionGetPixelBufferPool(
        session: VTCompressionSessionRef,
    ) -> CVPixelBufferPoolRef;
}

// CoreFoundation utilities
#[link(name = "CoreFoundation", kind = "framework")]
extern "C" {
    fn CFArrayGetCount(array: CFArrayRef) -> isize;
    fn CFArrayGetValueAtIndex(array: CFArrayRef, idx: isize) -> CFTypeRef;
    fn CFDictionaryGetValue(dict: CFDictionaryRef, key: *const c_void) -> *const c_void;
}

// H.264 codec type ('avc1')
const K_CM_VIDEO_CODEC_TYPE_H264: u32 = 0x61766331;
// BGRA pixel format
const K_CV_PIXEL_FORMAT_TYPE_32BGRA: u32 = 0x42475241; // 'BGRA'
// CFNumber types
const K_CF_NUMBER_SINT32_TYPE: i32 = 3;

/// Encoder context passed to the callback
struct EncoderContext {
    sender: mpsc::Sender<Result<EncodedFrame, EncodeError>>,
    frame_count: Arc<AtomicU64>,
}

/// H.264 video encoder using VideoToolbox
pub struct Encoder {
    session: VTCompressionSessionRef,
    frame_count: Arc<AtomicU64>,
    receiver: mpsc::Receiver<Result<EncodedFrame, EncodeError>>,
    config: EncoderConfig,
    // Keep context alive for the callback
    _context: Box<Mutex<EncoderContext>>,
}

// The output callback called by VideoToolbox when a frame is encoded
extern "C" fn compression_output_callback(
    output_callback_ref_con: *mut c_void,
    _source_frame_ref_con: *mut c_void,
    status: i32,
    _info_flags: VTEncodeInfoFlags,
    sample_buffer: CMSampleBufferRef,
) {
    if status != 0 {
        return;
    }

    if sample_buffer.is_null() {
        return;
    }

    let context = unsafe { &*(output_callback_ref_con as *const Mutex<EncoderContext>) };
    let guard = match context.lock() {
        Ok(g) => g,
        Err(_) => return,
    };

    let frame_number = guard.frame_count.load(Ordering::SeqCst);

    // Get presentation timestamp
    let pts = unsafe { CMSampleBufferGetPresentationTimeStamp(sample_buffer) };
    let pts_us = if pts.timescale > 0 {
        ((pts.value as f64 / pts.timescale as f64) * 1_000_000.0) as u64
    } else {
        0
    };

    // Check if this is a keyframe
    let is_keyframe = unsafe {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample_buffer, 0);
        if attachments.is_null() || CFArrayGetCount(attachments) == 0 {
            true // Assume keyframe if no attachments
        } else {
            let dict = CFArrayGetValueAtIndex(attachments, 0) as CFDictionaryRef;
            if dict.is_null() {
                true
            } else {
                let not_sync = CFDictionaryGetValue(dict, kCMSampleAttachmentKey_NotSync);
                not_sync.is_null() || !std::ptr::eq(not_sync, kCFBooleanTrue)
            }
        }
    };

    // Extract encoded data
    let data = match extract_h264_data(sample_buffer, is_keyframe) {
        Some(d) => d,
        None => return,
    };

    let metadata = FrameMetadata::new(frame_number, pts_us, pts_us, is_keyframe);
    let encoded = EncodedFrame::new(metadata, data);

    let _ = guard.sender.try_send(Ok(encoded));
}

/// Extract H.264 NAL units from the sample buffer
fn extract_h264_data(sample_buffer: CMSampleBufferRef, is_keyframe: bool) -> Option<Vec<u8>> {
    let mut data = Vec::new();

    // For keyframes, prepend SPS and PPS
    if is_keyframe {
        let format_desc = unsafe { CMSampleBufferGetFormatDescription(sample_buffer) };
        if !format_desc.is_null() {
            // Get SPS
            let mut sps_ptr: *const u8 = ptr::null();
            let mut sps_size: usize = 0;
            let mut param_count: usize = 0;
            let mut nal_header_len: i32 = 0;

            let status = unsafe {
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                    format_desc,
                    0, // SPS is at index 0
                    &mut sps_ptr,
                    &mut sps_size,
                    &mut param_count,
                    &mut nal_header_len,
                )
            };

            if status == 0 && !sps_ptr.is_null() && sps_size > 0 {
                // Write Annex B start code + SPS
                data.extend_from_slice(&[0x00, 0x00, 0x00, 0x01]);
                let sps = unsafe { std::slice::from_raw_parts(sps_ptr, sps_size) };
                data.extend_from_slice(sps);
            }

            // Get PPS
            let mut pps_ptr: *const u8 = ptr::null();
            let mut pps_size: usize = 0;

            let status = unsafe {
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                    format_desc,
                    1, // PPS is at index 1
                    &mut pps_ptr,
                    &mut pps_size,
                    &mut param_count,
                    &mut nal_header_len,
                )
            };

            if status == 0 && !pps_ptr.is_null() && pps_size > 0 {
                // Write Annex B start code + PPS
                data.extend_from_slice(&[0x00, 0x00, 0x00, 0x01]);
                let pps = unsafe { std::slice::from_raw_parts(pps_ptr, pps_size) };
                data.extend_from_slice(pps);
            }
        }
    }

    // Get the video data
    let block_buffer = unsafe { CMSampleBufferGetDataBuffer(sample_buffer) };
    if block_buffer.is_null() {
        return if data.is_empty() { None } else { Some(data) };
    }

    let data_length = unsafe { CMBlockBufferGetDataLength(block_buffer) };
    if data_length == 0 {
        return if data.is_empty() { None } else { Some(data) };
    }

    // Read the AVCC formatted data
    let mut avcc_data = vec![0u8; data_length];
    let status = unsafe {
        CMBlockBufferCopyDataBytes(block_buffer, 0, data_length, avcc_data.as_mut_ptr())
    };

    if status != 0 {
        return if data.is_empty() { None } else { Some(data) };
    }

    // Convert AVCC format to Annex B format
    // AVCC uses 4-byte length prefix, Annex B uses start codes
    let mut offset = 0;
    while offset + 4 <= avcc_data.len() {
        let nal_length = u32::from_be_bytes([
            avcc_data[offset],
            avcc_data[offset + 1],
            avcc_data[offset + 2],
            avcc_data[offset + 3],
        ]) as usize;

        offset += 4;

        if offset + nal_length > avcc_data.len() {
            break;
        }

        // Write Annex B start code + NAL unit
        data.extend_from_slice(&[0x00, 0x00, 0x00, 0x01]);
        data.extend_from_slice(&avcc_data[offset..offset + nal_length]);

        offset += nal_length;
    }

    if data.is_empty() {
        None
    } else {
        Some(data)
    }
}

impl Encoder {
    /// Create a new encoder with the given configuration
    pub fn new(config: EncoderConfig) -> Result<Self, EncodeError> {
        let (sender, receiver) = mpsc::channel(16);
        let frame_count = Arc::new(AtomicU64::new(0));

        // Create context for callback
        let context = Box::new(Mutex::new(EncoderContext {
            sender,
            frame_count: Arc::clone(&frame_count),
        }));
        let context_ptr = context.as_ref() as *const Mutex<EncoderContext> as *mut c_void;

        // Create pixel buffer attributes
        let pixel_buffer_attrs = unsafe {
            let attrs = CFDictionaryCreateMutable(
                kCFAllocatorDefault,
                4,
                &kCFTypeDictionaryKeyCallBacks,
                &kCFTypeDictionaryValueCallBacks,
            );

            // Pixel format
            let format_value = K_CV_PIXEL_FORMAT_TYPE_32BGRA as i32;
            let format_num = CFNumberCreate(
                kCFAllocatorDefault,
                K_CF_NUMBER_SINT32_TYPE,
                &format_value as *const i32 as *const c_void,
            );
            CFDictionarySetValue(attrs, kCVPixelBufferPixelFormatTypeKey, format_num);
            CFRelease(format_num as CFTypeRef);

            // Width
            let width_value = config.width as i32;
            let width_num = CFNumberCreate(
                kCFAllocatorDefault,
                K_CF_NUMBER_SINT32_TYPE,
                &width_value as *const i32 as *const c_void,
            );
            CFDictionarySetValue(attrs, kCVPixelBufferWidthKey, width_num);
            CFRelease(width_num as CFTypeRef);

            // Height
            let height_value = config.height as i32;
            let height_num = CFNumberCreate(
                kCFAllocatorDefault,
                K_CF_NUMBER_SINT32_TYPE,
                &height_value as *const i32 as *const c_void,
            );
            CFDictionarySetValue(attrs, kCVPixelBufferHeightKey, height_num);
            CFRelease(height_num as CFTypeRef);

            // IOSurface properties (empty dict for GPU access)
            let io_surface_props = CFDictionaryCreateMutable(
                kCFAllocatorDefault,
                0,
                &kCFTypeDictionaryKeyCallBacks,
                &kCFTypeDictionaryValueCallBacks,
            );
            CFDictionarySetValue(attrs, kCVPixelBufferIOSurfacePropertiesKey, io_surface_props);
            CFRelease(io_surface_props as CFTypeRef);

            attrs
        };

        // Create compression session
        let mut session: VTCompressionSessionRef = ptr::null_mut();

        let status = unsafe {
            VTCompressionSessionCreate(
                kCFAllocatorDefault,
                config.width as i32,
                config.height as i32,
                K_CM_VIDEO_CODEC_TYPE_H264,
                ptr::null(), // encoder_specification
                pixel_buffer_attrs as CFDictionaryRef,
                kCFAllocatorDefault,
                compression_output_callback,
                context_ptr,
                &mut session,
            )
        };

        // Release pixel buffer attrs
        unsafe { CFRelease(pixel_buffer_attrs as CFTypeRef) };

        if status != 0 {
            return Err(EncodeError::SessionCreationFailed(status));
        }

        // Configure session properties
        unsafe {
            // Real-time encoding
            if config.low_latency {
                VTSessionSetProperty(session, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue as CFTypeRef);
            }

            // Profile level - use High for better quality
            VTSessionSetProperty(
                session,
                kVTCompressionPropertyKey_ProfileLevel,
                kVTProfileLevel_H264_High_AutoLevel as CFTypeRef,
            );

            // Average bitrate
            let bitrate_value = config.bitrate_bps as i32;
            let bitrate_num = CFNumberCreate(
                kCFAllocatorDefault,
                K_CF_NUMBER_SINT32_TYPE,
                &bitrate_value as *const i32 as *const c_void,
            );
            VTSessionSetProperty(session, kVTCompressionPropertyKey_AverageBitRate, bitrate_num as CFTypeRef);
            CFRelease(bitrate_num as CFTypeRef);

            // Max keyframe interval
            let keyframe_value = config.keyframe_interval as i32;
            let keyframe_num = CFNumberCreate(
                kCFAllocatorDefault,
                K_CF_NUMBER_SINT32_TYPE,
                &keyframe_value as *const i32 as *const c_void,
            );
            VTSessionSetProperty(session, kVTCompressionPropertyKey_MaxKeyFrameInterval, keyframe_num as CFTypeRef);
            CFRelease(keyframe_num as CFTypeRef);

            // Disable frame reordering for low latency
            if config.low_latency {
                VTSessionSetProperty(session, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse as CFTypeRef);
            }

            // Prepare to encode
            let status = VTCompressionSessionPrepareToEncodeFrames(session);
            if status != 0 {
                VTCompressionSessionInvalidate(session);
                return Err(EncodeError::SessionCreationFailed(status));
            }
        }

        Ok(Self {
            session,
            frame_count,
            receiver,
            config,
            _context: context,
        })
    }

    /// Encode a frame from raw BGRA pixel data
    pub fn encode_raw(
        &self,
        pixel_data: &[u8],
        pts_us: u64,
        force_keyframe: bool,
    ) -> Result<(), EncodeError> {
        let expected_size = (self.config.width * self.config.height * 4) as usize;
        if pixel_data.len() < expected_size {
            return Err(EncodeError::InvalidInput(format!(
                "Pixel data too small: {} < {}",
                pixel_data.len(),
                expected_size
            )));
        }

        // Get pixel buffer from pool or create new one
        let pixel_buffer = unsafe {
            let pool = VTCompressionSessionGetPixelBufferPool(self.session);
            let mut buffer: CVPixelBufferRef = ptr::null();

            let status = if !pool.is_null() {
                CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &mut buffer)
            } else {
                CVPixelBufferCreate(
                    kCFAllocatorDefault,
                    self.config.width as usize,
                    self.config.height as usize,
                    K_CV_PIXEL_FORMAT_TYPE_32BGRA,
                    ptr::null(),
                    &mut buffer,
                )
            };

            if status != 0 || buffer.is_null() {
                return Err(EncodeError::PixelBufferFailed(status));
            }

            buffer
        };

        // Copy pixel data to buffer
        unsafe {
            let status = CVPixelBufferLockBaseAddress(pixel_buffer, 0);
            if status != 0 {
                CVPixelBufferRelease(pixel_buffer);
                return Err(EncodeError::PixelBufferFailed(status));
            }

            let base_address = CVPixelBufferGetBaseAddress(pixel_buffer);
            let bytes_per_row = CVPixelBufferGetBytesPerRow(pixel_buffer);

            // Copy row by row to handle stride differences
            let src_stride = (self.config.width * 4) as usize;
            for y in 0..self.config.height as usize {
                let src_offset = y * src_stride;
                let dst_offset = y * bytes_per_row;
                ptr::copy_nonoverlapping(
                    pixel_data.as_ptr().add(src_offset),
                    base_address.add(dst_offset),
                    src_stride,
                );
            }

            CVPixelBufferUnlockBaseAddress(pixel_buffer, 0);
        }

        // Create presentation timestamp
        let pts = CMTimeStruct::new(pts_us as i64, 1_000_000);
        let duration = CMTimeStruct::invalid();

        // Create frame properties for forced keyframe
        let frame_properties = if force_keyframe {
            unsafe {
                let props = CFDictionaryCreateMutable(
                    kCFAllocatorDefault,
                    1,
                    &kCFTypeDictionaryKeyCallBacks,
                    &kCFTypeDictionaryValueCallBacks,
                );
                // Note: Would need kVTEncodeFrameOptionKey_ForceKeyFrame here
                // For now, keyframes are controlled by MaxKeyFrameInterval
                props as CFDictionaryRef
            }
        } else {
            ptr::null()
        };

        // Encode the frame
        let frame_number = self.frame_count.fetch_add(1, Ordering::SeqCst);
        let mut info_flags: VTEncodeInfoFlags = 0;

        let status = unsafe {
            VTCompressionSessionEncodeFrame(
                self.session,
                pixel_buffer,
                pts,
                duration,
                frame_properties,
                frame_number as *mut c_void,
                &mut info_flags,
            )
        };

        // Release pixel buffer
        unsafe {
            CVPixelBufferRelease(pixel_buffer);
            if !frame_properties.is_null() {
                CFRelease(frame_properties as CFTypeRef);
            }
        }

        if status != 0 {
            return Err(EncodeError::EncodingFailed(status));
        }

        Ok(())
    }

    /// Get the next encoded frame
    pub async fn next_frame(&mut self) -> Option<Result<EncodedFrame, EncodeError>> {
        self.receiver.recv().await
    }

    /// Flush the encoder, forcing all pending frames to be output
    pub fn flush(&self) -> Result<(), EncodeError> {
        let status = unsafe {
            VTCompressionSessionCompleteFrames(
                self.session,
                CMTimeStruct::invalid(), // Complete all frames
            )
        };

        if status != 0 {
            return Err(EncodeError::FlushFailed(status));
        }

        Ok(())
    }

    /// Get the encoder configuration
    pub fn config(&self) -> &EncoderConfig {
        &self.config
    }
}

impl Drop for Encoder {
    fn drop(&mut self) {
        if !self.session.is_null() {
            // Flush remaining frames
            let _ = self.flush();
            unsafe {
                VTCompressionSessionInvalidate(self.session);
            }
        }
    }
}

// Safety: The encoder uses proper synchronization for the callback context
unsafe impl Send for Encoder {}
unsafe impl Sync for Encoder {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_default() {
        let config = EncoderConfig::default();
        assert_eq!(config.width, 1920);
        assert_eq!(config.height, 1080);
        assert_eq!(config.fps, 60);
        assert_eq!(config.bitrate_bps, 20_000_000);
    }

    #[test]
    fn test_cmtime_creation() {
        let time = CMTimeStruct::new(1000, 1_000_000);
        assert_eq!(time.value, 1000);
        assert_eq!(time.timescale, 1_000_000);
    }
}
