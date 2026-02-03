#!/bin/bash
# Build Rust FFI library and generate Swift bindings

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$SCRIPT_DIR/../.."
BUILD_TYPE="${1:-release}"

echo "Building SerialWarp FFI library ($BUILD_TYPE)..."

# Build the Rust library
if [ "$BUILD_TYPE" = "debug" ]; then
    cargo build -p serialwarp-ffi
    LIBRARY_PATH="$REPO_ROOT/target/debug/libserialwarp_ffi.a"
else
    cargo build -p serialwarp-ffi --release
    LIBRARY_PATH="$REPO_ROOT/target/release/libserialwarp_ffi.a"
fi

# Generate Swift bindings
echo "Generating Swift bindings..."
mkdir -p "$SCRIPT_DIR/rust-bridge"
cargo run -p serialwarp-ffi --bin uniffi-bindgen generate \
    --library "$LIBRARY_PATH" \
    --language swift \
    --out-dir "$SCRIPT_DIR/rust-bridge"

# Copy the static library to the build directory
echo "Copying static library..."
cp "$LIBRARY_PATH" "$SCRIPT_DIR/rust-bridge/"

echo "Done! Swift bindings generated in $SCRIPT_DIR/rust-bridge/"
echo ""
echo "Files:"
ls -la "$SCRIPT_DIR/rust-bridge/"
