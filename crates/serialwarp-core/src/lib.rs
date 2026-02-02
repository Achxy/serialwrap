//! serialwarp-core - Protocol and types for serialwarp
//!
//! This crate provides the core protocol definitions, packet types,
//! frame handling, and error types used by both the source (Mac) and
//! sink (PC) applications.

pub mod error;
pub mod frame;
pub mod protocol;
pub mod usb;

pub use error::*;
pub use frame::*;
pub use protocol::*;
pub use usb::*;
