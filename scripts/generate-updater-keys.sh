#!/bin/bash
# Generate Tauri updater signing keys
# Run this once and store the private key securely

set -e

echo "=== Tauri Updater Key Generation ==="
echo ""
echo "This script generates an Ed25519 keypair for signing app updates."
echo "The PRIVATE key should be stored as a GitHub secret."
echo "The PUBLIC key should be placed in tauri.conf.json."
echo ""

# Check if tauri CLI is installed
if ! command -v cargo-tauri &> /dev/null; then
    echo "Installing Tauri CLI..."
    cargo install tauri-cli
fi

# Generate the keypair
echo "Generating keypair..."
echo ""

# Tauri v2 uses a different command
cargo tauri signer generate -w .tauri-keys

echo ""
echo "=== Keys Generated ==="
echo ""
echo "Files created:"
echo "  .tauri-keys (private key - KEEP SECRET)"
echo "  .tauri-keys.pub (public key)"
echo ""
echo "=== Next Steps ==="
echo ""
echo "1. Add the PRIVATE key to GitHub Secrets:"
echo "   - Go to: Settings > Secrets and variables > Actions"
echo "   - Create secret: TAURI_SIGNING_PRIVATE_KEY"
echo "   - Value: Contents of .tauri-keys"
echo ""
echo "2. If you set a password, also add:"
echo "   - Create secret: TAURI_SIGNING_PRIVATE_KEY_PASSWORD"
echo "   - Value: Your password"
echo ""
echo "3. Update tauri.conf.json with the PUBLIC key:"
echo "   - Copy contents of .tauri-keys.pub"
echo "   - Replace UPDATER_PUBKEY_PLACEHOLDER in both apps"
echo ""
echo "4. Delete .tauri-keys from disk (after saving to GitHub Secrets)"
echo ""
echo "=== Public Key ==="
cat .tauri-keys.pub
echo ""
