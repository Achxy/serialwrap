//! serialwarp-render - SDL2-based video renderer
//!
//! This crate provides video rendering functionality for the sink application.

use sdl2::event::Event;
use sdl2::keyboard::Keycode;
use sdl2::pixels::PixelFormatEnum;
use sdl2::rect::Rect;
use sdl2::render::Canvas;
use sdl2::video::Window;
use sdl2::EventPump;
use sdl2::Sdl;

use serialwarp_core::{DecodedFrame, RenderError};

/// Renderer configuration
#[derive(Debug, Clone)]
pub struct RendererConfig {
    /// Window title
    pub title: String,
    /// Initial window width
    pub width: u32,
    /// Initial window height
    pub height: u32,
    /// Start in fullscreen mode
    pub fullscreen: bool,
    /// Enable VSync
    pub vsync: bool,
}

impl Default for RendererConfig {
    fn default() -> Self {
        Self {
            title: "serialwarp".to_string(),
            width: 1920,
            height: 1080,
            fullscreen: false,
            vsync: true,
        }
    }
}

/// SDL2-based video renderer
pub struct Renderer {
    #[allow(dead_code)]
    sdl_context: Sdl,
    canvas: Canvas<Window>,
    event_pump: EventPump,
    current_width: u32,
    current_height: u32,
    is_fullscreen: bool,
}

impl Renderer {
    /// Create a new renderer with the given configuration
    pub fn new(config: RendererConfig) -> Result<Self, RenderError> {
        let sdl_context =
            sdl2::init().map_err(|e| RenderError::SdlInitFailed(e.to_string()))?;

        let video_subsystem = sdl_context
            .video()
            .map_err(|e| RenderError::SdlInitFailed(e.to_string()))?;

        let mut window_builder = video_subsystem.window(&config.title, config.width, config.height);
        window_builder.position_centered().resizable();

        if config.fullscreen {
            window_builder.fullscreen_desktop();
        }

        let window = window_builder
            .build()
            .map_err(|e| RenderError::WindowCreationFailed(e.to_string()))?;

        let mut canvas_builder = window.into_canvas();
        if config.vsync {
            canvas_builder = canvas_builder.present_vsync();
        }

        let canvas = canvas_builder
            .accelerated()
            .build()
            .map_err(|e| RenderError::RendererCreationFailed(e.to_string()))?;

        let event_pump = sdl_context
            .event_pump()
            .map_err(|e| RenderError::SdlInitFailed(e.to_string()))?;

        Ok(Self {
            sdl_context,
            canvas,
            event_pump,
            current_width: 0,
            current_height: 0,
            is_fullscreen: config.fullscreen,
        })
    }

    /// Present a decoded frame to the screen
    pub fn present(&mut self, frame: &DecodedFrame) -> Result<(), RenderError> {
        let texture_creator = self.canvas.texture_creator();

        // Recreate texture if dimensions changed
        let needs_new_texture =
            frame.width != self.current_width || frame.height != self.current_height;

        if needs_new_texture {
            self.current_width = frame.width;
            self.current_height = frame.height;
        }

        // Create texture for this frame
        let mut texture = texture_creator
            .create_texture_streaming(PixelFormatEnum::IYUV, frame.width, frame.height)
            .map_err(|e| RenderError::TextureCreationFailed(e.to_string()))?;

        // Update texture with YUV data
        texture
            .update_yuv(
                None,
                frame.y_plane(),
                frame.y_stride(),
                frame.u_plane(),
                frame.uv_stride(),
                frame.v_plane(),
                frame.uv_stride(),
            )
            .map_err(|e| RenderError::TextureUpdateFailed(e.to_string()))?;

        // Calculate destination rect to maintain aspect ratio
        let (win_width, win_height) = self
            .canvas
            .output_size()
            .map_err(|e| RenderError::RenderFailed(e.to_string()))?;

        let dst_rect = Self::calculate_dest_rect(frame.width, frame.height, win_width, win_height);

        self.canvas.clear();
        self.canvas
            .copy(&texture, None, Some(dst_rect))
            .map_err(|e| RenderError::RenderFailed(e.to_string()))?;
        self.canvas.present();

        Ok(())
    }

    /// Process SDL events. Returns false if quit was requested.
    pub fn process_events(&mut self) -> bool {
        // Collect events first to avoid borrow issues
        let events: Vec<_> = self.event_pump.poll_iter().collect();

        for event in events {
            match event {
                Event::Quit { .. } => return false,
                Event::KeyDown {
                    keycode: Some(key), ..
                } => match key {
                    Keycode::Escape => return false,
                    Keycode::F | Keycode::F11 => {
                        self.toggle_fullscreen();
                    }
                    _ => {}
                },
                _ => {}
            }
        }
        true
    }

    fn toggle_fullscreen(&mut self) {
        let window = self.canvas.window_mut();
        if self.is_fullscreen {
            let _ = window.set_fullscreen(sdl2::video::FullscreenType::Off);
        } else {
            let _ = window.set_fullscreen(sdl2::video::FullscreenType::Desktop);
        }
        self.is_fullscreen = !self.is_fullscreen;
    }

    fn calculate_dest_rect(
        src_width: u32,
        src_height: u32,
        dst_width: u32,
        dst_height: u32,
    ) -> Rect {
        let src_aspect = src_width as f64 / src_height as f64;
        let dst_aspect = dst_width as f64 / dst_height as f64;

        let (render_width, render_height) = if src_aspect > dst_aspect {
            // Source is wider - fit to width
            let width = dst_width;
            let height = (dst_width as f64 / src_aspect) as u32;
            (width, height)
        } else {
            // Source is taller - fit to height
            let height = dst_height;
            let width = (dst_height as f64 * src_aspect) as u32;
            (width, height)
        };

        let x = ((dst_width - render_width) / 2) as i32;
        let y = ((dst_height - render_height) / 2) as i32;

        Rect::new(x, y, render_width, render_height)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_renderer_config_default() {
        let config = RendererConfig::default();
        assert_eq!(config.width, 1920);
        assert_eq!(config.height, 1080);
        assert!(!config.fullscreen);
        assert!(config.vsync);
    }

    #[test]
    fn test_calculate_dest_rect_wider() {
        // 16:9 source in 4:3 window
        let rect = Renderer::calculate_dest_rect(1920, 1080, 800, 600);
        // Should fit to width with letterboxing
        assert_eq!(rect.width(), 800);
        assert!(rect.height() < 600);
        assert!(rect.y() > 0); // Letterboxed
    }

    #[test]
    fn test_calculate_dest_rect_taller() {
        // 4:3 source in 16:9 window
        let rect = Renderer::calculate_dest_rect(800, 600, 1920, 1080);
        // Should fit to height with pillarboxing
        assert!(rect.width() < 1920);
        assert_eq!(rect.height(), 1080);
        assert!(rect.x() > 0); // Pillarboxed
    }

    #[test]
    fn test_calculate_dest_rect_same_aspect() {
        // Same aspect ratio
        let rect = Renderer::calculate_dest_rect(1920, 1080, 960, 540);
        assert_eq!(rect.width(), 960);
        assert_eq!(rect.height(), 540);
        assert_eq!(rect.x(), 0);
        assert_eq!(rect.y(), 0);
    }
}
