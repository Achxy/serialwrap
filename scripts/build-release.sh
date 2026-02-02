#!/bin/bash
# Build release versions of SerialWarp apps
# Usage: ./scripts/build-release.sh [capture|display|all]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check required tools
check_requirements() {
    log_info "Checking requirements..."

    # Check for Node.js
    if ! command -v node &> /dev/null; then
        log_error "Node.js is not installed"
        exit 1
    fi

    # Check for npm
    if ! command -v npm &> /dev/null; then
        log_error "npm is not installed"
        exit 1
    fi

    # Check for Rust
    if ! command -v cargo &> /dev/null; then
        log_error "Rust/Cargo is not installed"
        exit 1
    fi

    log_info "All requirements met"
}

# Build capture app (macOS only)
build_capture() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        log_warn "Capture app can only be built on macOS"
        return 1
    fi

    log_info "Building SerialWarp Capture..."

    cd "$PROJECT_ROOT/apps/capture"

    # Install npm dependencies
    log_info "Installing npm dependencies..."
    npm install

    # Build with Tauri
    log_info "Building Tauri app..."
    npm run tauri build

    log_info "Capture app built successfully!"
    log_info "Output: apps/capture/src-tauri/target/release/bundle/"
}

# Build display app (Windows target)
build_display() {
    log_info "Building SerialWarp Display..."

    cd "$PROJECT_ROOT/apps/display"

    # Install npm dependencies
    log_info "Installing npm dependencies..."
    npm install

    # Build with Tauri
    log_info "Building Tauri app..."

    if [[ "$(uname -s)" == "Darwin" ]] || [[ "$(uname -s)" == "Linux" ]]; then
        log_warn "Building Windows app on $(uname -s)"
        log_warn "Cross-compilation may require additional setup"

        # Check if Windows target is installed
        if ! rustup target list | grep -q "x86_64-pc-windows-msvc (installed)"; then
            log_warn "Windows target not installed. Installing..."
            rustup target add x86_64-pc-windows-msvc || {
                log_error "Failed to add Windows target. Cross-compilation may not work."
                log_info "Building for current platform instead..."
                npm run tauri build
                return 0
            }
        fi

        npm run tauri build -- --target x86_64-pc-windows-msvc || {
            log_warn "Cross-compilation failed. Building for current platform..."
            npm run tauri build
        }
    else
        npm run tauri build
    fi

    log_info "Display app built successfully!"
    log_info "Output: apps/display/src-tauri/target/release/bundle/"
}

# Print usage
usage() {
    echo "Usage: $0 [capture|display|all]"
    echo ""
    echo "Options:"
    echo "  capture  - Build SerialWarp Capture (macOS only)"
    echo "  display  - Build SerialWarp Display (Windows target)"
    echo "  all      - Build both apps"
    echo ""
    echo "Examples:"
    echo "  $0 capture    # Build capture app on macOS"
    echo "  $0 display    # Build display app"
    echo "  $0 all        # Build both apps"
}

# Main
main() {
    echo "=== SerialWarp Build Script ==="
    echo ""

    check_requirements

    case "${1:-all}" in
        capture)
            build_capture
            ;;
        display)
            build_display
            ;;
        all)
            if [[ "$(uname -s)" == "Darwin" ]]; then
                build_capture
            else
                log_warn "Skipping capture app (macOS only)"
            fi
            build_display
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac

    echo ""
    echo "=== Build Complete ==="
}

main "$@"
