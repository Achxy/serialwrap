# SerialWarp GUI Applications

This directory contains the Tauri-based GUI applications for SerialWarp.

## Applications

### SerialWarp Capture (macOS)

Located in `capture/`. A macOS application for capturing screen content and streaming it over USB.

**Features:**
- Virtual display creation
- Live preview with WebGL canvas
- Resolution, FPS, and bitrate controls
- Real-time streaming statistics
- Settings persistence

**Requirements:**
- macOS 12.3 (Monterey) or later
- Screen recording permission

### SerialWarp Display (Windows)

Located in `display/`. A Windows application for receiving and displaying video streams from a Mac.

**Features:**
- USB connection waiting and auto-detection
- Full-screen video display (F11 toggle)
- Real-time decode and latency statistics
- Settings persistence

**Requirements:**
- Windows 10/11
- WebView2 runtime (auto-installed if missing)

## Development

### Prerequisites

- [Node.js](https://nodejs.org/) 18+
- [Rust](https://rustup.rs/) 1.70+
- Platform-specific requirements:
  - **macOS:** Xcode Command Line Tools
  - **Windows:** Visual Studio Build Tools with C++ workload

### Setup

```bash
# Install frontend dependencies
cd capture && npm install
cd ../display && npm install
```

### Development Mode

```bash
# Capture app (macOS only)
cd capture && npm run tauri dev

# Display app
cd display && npm run tauri dev
```

### Building

Use the provided build script from the repository root:

```bash
# Build both apps
./scripts/build-release.sh all

# Build specific app
./scripts/build-release.sh capture  # macOS only
./scripts/build-release.sh display
```

Or manually:

```bash
cd capture && npm run tauri build
cd display && npm run tauri build
```

Build outputs are located in `src-tauri/target/release/bundle/`.

## Code Signing

For distribution, you'll need to sign the applications:

### macOS

1. Generate a self-signed certificate (for testing):
   ```bash
   ./scripts/generate-certs.sh
   ```

2. For App Store or notarization, use an Apple Developer certificate.

3. Update `src-tauri/tauri.conf.json` with your signing identity.

### Windows

1. Generate a self-signed certificate (for testing):
   ```powershell
   # Run the generated PowerShell script
   .\.certs\generate-certs.ps1
   ```

2. For distribution, use a trusted code signing certificate.

3. Update `src-tauri/tauri.conf.json` with your certificate thumbprint.

## Architecture

```
[Capture App - Mac]              [Display App - Windows]
       │                                   │
       ├─ Virtual Display                  ├─ USB Transport
       │  (CGVirtualDisplay)               │  (nusb)
       │                                   │
       ├─ Screen Capture                   ├─ H.264 Decoder
       │  (ScreenCaptureKit)               │  (FFmpeg)
       │                                   │
       ├─ H.264 Encoder                    ├─ Video Display
       │  (VideoToolbox)                   │  (WebGL Canvas)
       │                                   │
       ├─ USB Transport ──────────────────>│
       │  (nusb)                           │
       │                                   │
       └─ React Frontend                   └─ React Frontend
          (Tauri WebView)                     (Tauri WebView)
```

## Troubleshooting

### macOS: "Screen Recording" permission denied

Go to System Settings > Privacy & Security > Screen Recording and enable the app.

### Windows: WebView2 installation fails

Download and install WebView2 manually from Microsoft:
https://developer.microsoft.com/en-us/microsoft-edge/webview2/

### Build fails with icon errors

Ensure all icon files exist and are valid RGBA PNG format. Run the icon generation script:
```bash
cd src-tauri/icons && ./generate-icons.sh
```
