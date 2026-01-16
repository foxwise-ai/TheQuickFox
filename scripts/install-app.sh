#!/bin/bash

# Build and install TheQuickFox app
# Usage: ./scripts/install-app.sh [release|debug] [--universal]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/.."
MACOS_DIR="$PROJECT_ROOT/macos"

BUILD_CONFIG="release"
UNIVERSAL=false

echo "🗑️  Removing old installation..."
rm -rf ~/Applications/TheQuickFox.app

echo "📦 Installing new version..."
ditto "$MACOS_DIR/.build/$BUILD_CONFIG/TheQuickFox.app" ~/Applications/TheQuickFox.app

echo "✅ Installation complete!"

if [ "$UNIVERSAL" = true ]; then
    echo ""
    echo "Architecture support:"
    lipo -info ~/Applications/TheQuickFox.app/Contents/MacOS/TheQuickFox
fi

echo ""
echo "Note: If permissions aren't working:"
echo "1. Quit TheQuickFox completely"
echo "2. Run: tccutil reset All com.foxwiseai.thequickfox"
echo "3. Launch TheQuickFox again and re-grant permissions"
