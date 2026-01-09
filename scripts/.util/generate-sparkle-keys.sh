#!/bin/bash

# Generate Sparkle EdDSA keys for update signing

set -e

echo "🔑 Generating Sparkle EdDSA keys..."

# Create directory for keys
mkdir -p ~/.sparkle_keys

# Generate keys
cd ~/.sparkle_keys
/opt/homebrew/Caskroom/sparkle/2.8.0/bin/generate_keys

echo ""
echo "✅ Keys generated in ~/.sparkle_keys/"
echo ""
echo "⚠️  IMPORTANT:"
echo "1. Your PRIVATE key is in: ~/.sparkle_keys/ed25519_secret_key"
echo "   NEVER commit this to git!"
echo ""
echo "2. Your PUBLIC key:"
cat ~/.sparkle_keys/ed25519_public_key.pub
echo ""
echo "3. Add this public key to macos/Info.plist:"
echo "   <key>SUPublicEDKey</key>"
echo "   <string>$(cat ~/.sparkle_keys/ed25519_public_key.pub)</string>"
