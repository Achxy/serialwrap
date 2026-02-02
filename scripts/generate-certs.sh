#!/bin/bash
# Generate self-signed certificates for code signing
# Usage: ./scripts/generate-certs.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CERTS_DIR="$PROJECT_ROOT/.certs"

mkdir -p "$CERTS_DIR"

echo "=== SerialWarp Certificate Generation ==="
echo ""

# Detect platform
case "$(uname -s)" in
    Darwin)
        echo "Platform: macOS"
        echo ""

        # Generate macOS certificate
        echo "Generating macOS code signing certificate..."

        # Create private key
        openssl genrsa -out "$CERTS_DIR/mac-key.pem" 2048

        # Create certificate signing request
        openssl req -new \
            -key "$CERTS_DIR/mac-key.pem" \
            -out "$CERTS_DIR/mac-csr.pem" \
            -subj "/CN=SerialWarp Developer/O=SerialWarp/C=US"

        # Create self-signed certificate
        openssl x509 -req \
            -days 365 \
            -in "$CERTS_DIR/mac-csr.pem" \
            -signkey "$CERTS_DIR/mac-key.pem" \
            -out "$CERTS_DIR/mac-cert.pem"

        # Create PKCS12 bundle for Keychain import
        openssl pkcs12 -export \
            -in "$CERTS_DIR/mac-cert.pem" \
            -inkey "$CERTS_DIR/mac-key.pem" \
            -out "$CERTS_DIR/mac-cert.p12" \
            -name "SerialWarp Developer" \
            -passout pass:serialwarp

        echo ""
        echo "macOS certificate generated successfully!"
        echo ""
        echo "To import into Keychain:"
        echo "  security import $CERTS_DIR/mac-cert.p12 -k ~/Library/Keychains/login.keychain-db -P serialwarp -T /usr/bin/codesign"
        echo ""
        echo "After importing, you may need to trust the certificate:"
        echo "  1. Open Keychain Access"
        echo "  2. Find 'SerialWarp Developer' certificate"
        echo "  3. Double-click and expand 'Trust'"
        echo "  4. Set 'Code Signing' to 'Always Trust'"
        ;;

    MINGW*|MSYS*|CYGWIN*|Windows*)
        echo "Platform: Windows"
        echo ""
        echo "Please run generate-certs.ps1 on Windows."
        echo ""
        cat > "$CERTS_DIR/generate-certs.ps1" << 'POWERSHELL'
# Generate self-signed certificate for Windows code signing
# Run as Administrator in PowerShell

$cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject "CN=SerialWarp Developer, O=SerialWarp" `
    -CertStoreLocation Cert:\CurrentUser\My `
    -HashAlgorithm sha256 `
    -KeyLength 2048 `
    -NotAfter (Get-Date).AddYears(1)

$password = ConvertTo-SecureString -String "serialwarp" -Force -AsPlainText

Export-PfxCertificate `
    -Cert $cert `
    -FilePath "$PSScriptRoot\win-cert.pfx" `
    -Password $password

Write-Host ""
Write-Host "Windows certificate generated successfully!"
Write-Host ""
Write-Host "Certificate thumbprint: $($cert.Thumbprint)"
Write-Host ""
Write-Host "The certificate has been added to your personal certificate store."
Write-Host "The PFX file is at: $PSScriptRoot\win-cert.pfx"
Write-Host "Password: serialwarp"
POWERSHELL
        echo "PowerShell script created at: $CERTS_DIR/generate-certs.ps1"
        ;;

    Linux)
        echo "Platform: Linux"
        echo ""
        echo "Linux does not require code signing certificates for app distribution."
        echo "If you need to cross-compile for Windows, run generate-certs.ps1 on Windows."
        ;;

    *)
        echo "Unknown platform: $(uname -s)"
        exit 1
        ;;
esac

echo ""
echo "=== Certificate Generation Complete ==="
