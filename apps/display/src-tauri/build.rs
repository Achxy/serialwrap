// Build script for SerialWarp Display
// Handles platform-specific library bundling for standalone distribution

fn main() {
    // Standard Tauri build
    tauri_build::build();

    // Platform-specific library bundling
    #[cfg(target_os = "windows")]
    windows_bundle();

    #[cfg(target_os = "macos")]
    macos_bundle();

    #[cfg(target_os = "linux")]
    linux_bundle();
}

#[cfg(target_os = "windows")]
fn windows_bundle() {
    // On Windows, we need to ensure FFmpeg and SDL2 DLLs are available
    // The GitHub Actions workflow installs these via chocolatey
    // DLLs are copied to the output directory by the NSIS installer

    // Tell cargo to look for libraries in standard locations
    if let Ok(ffmpeg_dir) = std::env::var("FFMPEG_DIR") {
        println!("cargo:rustc-link-search=native={}/lib", ffmpeg_dir);
        println!("cargo:rustc-link-search=native={}/bin", ffmpeg_dir);
    }

    // Link SDL2
    if let Ok(sdl2_dir) = std::env::var("SDL2_DIR") {
        println!("cargo:rustc-link-search=native={}/lib/x64", sdl2_dir);
    }
}

#[cfg(target_os = "macos")]
fn macos_bundle() {
    // On macOS, libraries are bundled in the .app/Contents/Frameworks directory
    // via tauri.conf.json "frameworks" configuration

    // FFmpeg installed via Homebrew
    if let Ok(homebrew_prefix) = std::env::var("HOMEBREW_PREFIX") {
        println!("cargo:rustc-link-search=native={}/lib", homebrew_prefix);
    } else {
        // Default Homebrew locations
        println!("cargo:rustc-link-search=native=/opt/homebrew/lib");
        println!("cargo:rustc-link-search=native=/usr/local/lib");
    }
}

#[cfg(target_os = "linux")]
fn linux_bundle() {
    // On Linux, AppImage bundles libraries automatically
    // when bundleMediaFramework is enabled

    // Standard library locations
    println!("cargo:rustc-link-search=native=/usr/lib");
    println!("cargo:rustc-link-search=native=/usr/lib/x86_64-linux-gnu");
}
