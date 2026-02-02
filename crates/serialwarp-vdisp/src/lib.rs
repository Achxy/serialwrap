//! serialwarp-vdisp - macOS virtual display using CGVirtualDisplay API
//!
//! This crate provides virtual display functionality for macOS using
//! the private CGVirtualDisplay API.

#![cfg(target_os = "macos")]

use core_foundation::base::TCFType;
use core_foundation::string::CFString;
use dispatch::Queue;
use serialwarp_core::DisplayError;
use std::ffi::c_void;
use std::ptr;

// Raw Objective-C runtime types
#[repr(C)]
struct ObjcClass(c_void);
#[repr(C)]
struct ObjcSelector(c_void);
type Class = *const ObjcClass;
type Sel = *const ObjcSelector;
type Id = *mut c_void;

// Objective-C runtime functions
#[link(name = "objc", kind = "dylib")]
extern "C" {
    fn objc_getClass(name: *const i8) -> Class;
    fn sel_registerName(name: *const i8) -> Sel;
    fn objc_msgSend();
    fn objc_alloc(cls: Class) -> Id;
}

/// Virtual display configuration
#[derive(Debug, Clone)]
pub struct VirtualDisplayConfig {
    /// Display name
    pub name: String,
    /// Maximum width in pixels
    pub max_width: u32,
    /// Maximum height in pixels
    pub max_height: u32,
    /// Refresh rate in Hz
    pub refresh_rate: u32,
    /// Enable HiDPI mode (retina)
    pub hidpi: bool,
}

impl Default for VirtualDisplayConfig {
    fn default() -> Self {
        Self {
            name: "serialwarp".to_string(),
            max_width: 1920,
            max_height: 1080,
            refresh_rate: 60,
            hidpi: false,
        }
    }
}

/// Helper to get a class by name
unsafe fn get_class(name: &str) -> Class {
    let cname = std::ffi::CString::new(name).unwrap();
    objc_getClass(cname.as_ptr())
}

/// Helper to get a selector
unsafe fn sel(name: &str) -> Sel {
    let cname = std::ffi::CString::new(name).unwrap();
    sel_registerName(cname.as_ptr())
}

// Define the function pointer type for objc_msgSend with specific signatures
macro_rules! msg_send {
    ($obj:expr, $sel:expr => Id) => {{
        let f: extern "C" fn(Id, Sel) -> Id = std::mem::transmute(objc_msgSend as *const c_void);
        f($obj, $sel)
    }};
    ($obj:expr, $sel:expr) => {{
        let f: extern "C" fn(Id, Sel) = std::mem::transmute(objc_msgSend as *const c_void);
        f($obj, $sel)
    }};
    ($obj:expr, $sel:expr, $arg1:expr => Id) => {{
        let f: extern "C" fn(Id, Sel, Id) -> Id = std::mem::transmute(objc_msgSend as *const c_void);
        f($obj, $sel, $arg1)
    }};
    ($obj:expr, $sel:expr, $arg1:expr) => {{
        let f: extern "C" fn(Id, Sel, Id) = std::mem::transmute(objc_msgSend as *const c_void);
        f($obj, $sel, $arg1)
    }};
    ($obj:expr, $sel:expr, $arg1:expr, $arg2:expr, $arg3:expr => Id) => {{
        let f: extern "C" fn(Id, Sel, Id, Id, *mut c_void) -> Id = std::mem::transmute(objc_msgSend as *const c_void);
        f($obj, $sel, $arg1, $arg2, $arg3)
    }};
}

macro_rules! msg_send_u32 {
    ($obj:expr, $sel:expr) => {{
        let f: extern "C" fn(Id, Sel) -> u32 = std::mem::transmute(objc_msgSend as *const c_void);
        f($obj, $sel)
    }};
    ($obj:expr, $sel:expr, $arg1:expr) => {{
        let f: extern "C" fn(Id, Sel, u32) = std::mem::transmute(objc_msgSend as *const c_void);
        f($obj, $sel, $arg1)
    }};
}

macro_rules! msg_send_f64 {
    ($obj:expr, $sel:expr, $arg1:expr) => {{
        let f: extern "C" fn(Id, Sel, f64) = std::mem::transmute(objc_msgSend as *const c_void);
        f($obj, $sel, $arg1)
    }};
}

macro_rules! msg_send_bool {
    ($obj:expr, $sel:expr, $arg1:expr) => {{
        let f: extern "C" fn(Id, Sel, bool) = std::mem::transmute(objc_msgSend as *const c_void);
        f($obj, $sel, $arg1)
    }};
}

/// A macOS virtual display
pub struct VirtualDisplay {
    display: Id,
    display_id: u32,
    #[allow(dead_code)]
    queue: Queue,
}

impl VirtualDisplay {
    /// Create a new virtual display with the given configuration
    pub fn new(config: VirtualDisplayConfig) -> Result<Self, DisplayError> {
        unsafe {
            // Get classes
            let descriptor_class = get_class("CGVirtualDisplayDescriptor");
            let mode_class = get_class("CGVirtualDisplayMode");
            let settings_class = get_class("CGVirtualDisplaySettings");
            let display_class = get_class("CGVirtualDisplay");
            let nsarray_class = get_class("NSArray");

            if descriptor_class.is_null()
                || mode_class.is_null()
                || settings_class.is_null()
                || display_class.is_null()
            {
                return Err(DisplayError::InvalidConfiguration(
                    "CGVirtualDisplay classes not found (requires macOS 14+)".to_string(),
                ));
            }

            // Get selectors
            let init_sel = sel("init");
            let set_name_sel = sel("setName:");
            let set_serial_sel = sel("setSerialNum:");
            let set_width_sel = sel("setWidth:");
            let set_height_sel = sel("setHeight:");
            let set_refresh_sel = sel("setRefreshRate:");
            let array_with_object_sel = sel("arrayWithObject:");
            let set_modes_sel = sel("setModes:");
            let set_hidpi_sel = sel("setHiDPI:");
            let init_with_desc_sel = sel("initWithDescriptor:settings:queue:");
            let display_id_sel = sel("displayID");

            // Create descriptor using alloc/init
            let descriptor_alloc = objc_alloc(descriptor_class);
            let descriptor: Id = msg_send!(descriptor_alloc, init_sel => Id);

            if descriptor.is_null() {
                return Err(DisplayError::CreationFailed);
            }

            // Set display name
            let name_cf = CFString::new(&config.name);
            let name_ns: Id = name_cf.as_concrete_TypeRef() as Id;
            msg_send!(descriptor, set_name_sel, name_ns);

            // Set serial number
            msg_send_u32!(descriptor, set_serial_sel, 12345u32);

            // Create display mode
            let mode_alloc = objc_alloc(mode_class);
            let mode: Id = msg_send!(mode_alloc, init_sel => Id);

            if mode.is_null() {
                return Err(DisplayError::CreationFailed);
            }

            // Set mode dimensions (halve if HiDPI)
            let mode_width = if config.hidpi {
                config.max_width / 2
            } else {
                config.max_width
            };
            let mode_height = if config.hidpi {
                config.max_height / 2
            } else {
                config.max_height
            };

            msg_send_u32!(mode, set_width_sel, mode_width);
            msg_send_u32!(mode, set_height_sel, mode_height);
            msg_send_f64!(mode, set_refresh_sel, config.refresh_rate as f64);

            // Create modes array
            let modes_array: Id = msg_send!(nsarray_class as Id, array_with_object_sel, mode => Id);

            // Set modes on descriptor
            msg_send!(descriptor, set_modes_sel, modes_array);

            // Create settings
            let settings_alloc = objc_alloc(settings_class);
            let settings: Id = msg_send!(settings_alloc, init_sel => Id);

            if settings.is_null() {
                return Err(DisplayError::CreationFailed);
            }

            // Set HiDPI if enabled
            if config.hidpi {
                msg_send_bool!(settings, set_hidpi_sel, true);
            }

            // Create dispatch queue for callbacks
            let queue = Queue::create("com.serialwarp.vdisp", dispatch::QueueAttribute::Serial);

            // Create the virtual display
            let display_alloc = objc_alloc(display_class);
            let display: Id =
                msg_send!(display_alloc, init_with_desc_sel, descriptor, settings, ptr::null_mut() => Id);

            if display.is_null() {
                return Err(DisplayError::CreationFailed);
            }

            // Get display ID
            let display_id: u32 = msg_send_u32!(display, display_id_sel);

            if display_id == 0 {
                return Err(DisplayError::CreationFailed);
            }

            Ok(Self {
                display,
                display_id,
                queue,
            })
        }
    }

    /// Get the CGDirectDisplayID for this virtual display
    pub fn display_id(&self) -> u32 {
        self.display_id
    }
}

impl Drop for VirtualDisplay {
    fn drop(&mut self) {
        // Release the display object
        unsafe {
            if !self.display.is_null() {
                let release_sel = sel("release");
                msg_send!(self.display, release_sel);
            }
        }
    }
}

// Safety: The virtual display is tied to the main thread on macOS,
// but we only use it from a single thread.
unsafe impl Send for VirtualDisplay {}
unsafe impl Sync for VirtualDisplay {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_default() {
        let config = VirtualDisplayConfig::default();
        assert_eq!(config.max_width, 1920);
        assert_eq!(config.max_height, 1080);
        assert_eq!(config.refresh_rate, 60);
        assert!(!config.hidpi);
    }
}
