#!/bin/bash

# Setup code signing for TheQuickFox

echo "🔐 Setting up code signing for TheQuickFox..."
echo ""
echo "This script will help you set up proper code signing."
echo ""

# Check if user has signing certificates
IDENTITIES=$(security find-identity -p codesigning -v | grep -c "valid identities found")

if [ "$IDENTITIES" -eq "0" ]; then
    echo "❌ No code signing certificates found."
    echo ""
    echo "To create one:"
    echo "1. Open Xcode"
    echo "2. Go to Xcode → Settings → Accounts"
    echo "3. Sign in with your Apple ID"
    echo "4. Click 'Manage Certificates'"
    echo "5. Click '+' and choose 'Apple Development'"
    echo ""
    echo "Or visit: https://developer.apple.com/account/resources/certificates/add"
    echo ""
    exit 1
fi

echo "✅ Found code signing certificates:"
security find-identity -p codesigning -v

echo ""
echo "To use a certificate, update scripts/.util/codesign-config.sh with:"
echo ""
echo "codesign --force --deep --sign \"YOUR_CERTIFICATE_NAME\" macos/.build/release/TheQuickFox.app"
echo ""
echo "Example:"
echo "codesign --force --deep --sign \"Apple Development: Your Name (TEAMID)\" macos/.build/release/TheQuickFox.app"