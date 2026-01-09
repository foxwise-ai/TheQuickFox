#!/bin/bash

# Create a professional DMG with universal binary

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/.."
MACOS_DIR="$PROJECT_ROOT/macos"

APP_NAME="TheQuickFox"
VERSION=$(defaults read "$MACOS_DIR/.build/release/${APP_NAME}.app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")
DMG_NAME="${APP_NAME}-${VERSION}-Universal"
DMG_FILE="${DMG_NAME}.dmg"
VOLUME_NAME="${APP_NAME}"

echo "🎨 Creating professional Universal DMG installer for ${APP_NAME} v${VERSION}..."

# Check if create-dmg is installed
if ! command -v create-dmg &> /dev/null; then
    echo "❌ create-dmg is not installed"
    echo "   Install it with: brew install create-dmg"
    exit 1
fi

# Build the universal app first
echo "🔨 Building the universal app..."
"$SCRIPT_DIR/build-app.sh" release --universal

# Clean up any existing DMG
if [ -f "${DMG_FILE}" ]; then
    echo "🗑️  Removing existing DMG..."
    rm -f "${DMG_FILE}"
fi

# Check if we have a background image
BACKGROUND_ARGS=""
if [ -f "$MACOS_DIR/Resources/dmg-background.png" ]; then
    echo "🖼️  Using background image"
    BACKGROUND_ARGS="--background $MACOS_DIR/Resources/dmg-background.png"
fi

# Create the DMG
echo "💿 Creating DMG..."
create-dmg \
    --volname "${VOLUME_NAME}" \
    --volicon "$MACOS_DIR/Resources/AppIcon.icns" \
    --window-pos 200 120 \
    --window-size 600 415 \
    --icon-size 72 \
    --icon "${APP_NAME}.app" 322 287 \
    --hide-extension "${APP_NAME}.app" \
    --app-drop-link 495 287 \
    --text-size 14 \
    --hdiutil-verbose \
    --no-internet-enable \
    ${BACKGROUND_ARGS} \
    "${DMG_FILE}" \
    "$MACOS_DIR/.build/release/${APP_NAME}.app"

echo "✅ Universal DMG created: ${DMG_FILE}"
echo ""
echo "File size: $(du -h "${DMG_FILE}" | cut -f1)"
echo ""
echo "The DMG contains a universal binary that runs natively on:"
echo "- Intel Macs (x86_64)"
echo "- Apple Silicon Macs (arm64)"
