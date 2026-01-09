#!/bin/bash

# Build TheQuickFox as a proper macOS app bundle
# Usage: ./scripts/build-app.sh [release|debug] [--universal]

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MACOS_SRC_DIR="$PROJECT_ROOT/macos"
BUILD_CONFIG="release"
BUILD_UNIVERSAL=false

# Change to macos directory for build
cd "$MACOS_SRC_DIR"

# Parse arguments
for arg in "$@"; do
    case $arg in
        debug|release)
            BUILD_CONFIG="$arg"
            ;;
        --universal)
            BUILD_UNIVERSAL=true
            ;;
    esac
done

BUILD_DIR="$MACOS_SRC_DIR/.build/$BUILD_CONFIG"
APP_NAME="TheQuickFox"
BUNDLE_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

if [ "$BUILD_UNIVERSAL" = true ]; then
    echo "🏗️  Building Universal TheQuickFox app bundle ($BUILD_CONFIG)..."
else
    echo "🏗️  Building TheQuickFox app bundle ($BUILD_CONFIG)..."
fi

# Clean previous builds if building universal
if [ "$BUILD_UNIVERSAL" = true ]; then
    echo "🧹 Cleaning previous builds..."
    rm -rf .build
fi

# Clean previous app bundle
if [ -d "$BUNDLE_DIR" ]; then
    echo "🧹 Cleaning previous app bundle..."
    rm -rf "$BUNDLE_DIR"
fi

# Build the executable
echo "⚙️  Building executable..."
if [ "$BUILD_UNIVERSAL" = true ]; then
    # Build for both architectures
    echo "🔨 Building for Apple Silicon (arm64)..."
    swift build -c $BUILD_CONFIG --arch arm64

    echo "🔨 Building for Intel (x86_64)..."
    swift build -c $BUILD_CONFIG --arch x86_64

    # Remove the symlink that Swift creates (points to last-built arch)
    # and create a real directory for the universal build
    rm -rf ".build/$BUILD_CONFIG"
    mkdir -p ".build/$BUILD_CONFIG"

    # Create universal binary from both architectures
    ARM_BINARY=".build/arm64-apple-macosx/$BUILD_CONFIG/$APP_NAME"
    INTEL_BINARY=".build/x86_64-apple-macosx/$BUILD_CONFIG/$APP_NAME"
    UNIVERSAL_BINARY=".build/$BUILD_CONFIG/$APP_NAME"
    lipo -create "$ARM_BINARY" "$INTEL_BINARY" -output "$UNIVERSAL_BINARY"

    echo "✅ Universal binary created!"
    lipo -info "$UNIVERSAL_BINARY"
else
    swift build -c $BUILD_CONFIG
fi

# Also copy resources to debug build directory for 'swift run'
if [ "$BUILD_CONFIG" = "debug" ]; then
    DEBUG_RESOURCES_DIR="$BUILD_DIR/TheQuickFox_TheQuickFox.resources"
    echo "📚 Copying resources for debug build..."
    mkdir -p "$DEBUG_RESOURCES_DIR/Onboarding"
    cp -r "Sources/TheQuickFox/Onboarding/Resources"/* "$DEBUG_RESOURCES_DIR/Onboarding/"

    mkdir -p "$DEBUG_RESOURCES_DIR/Upgrade"
    cp -r "Sources/TheQuickFox/Upgrade/Resources"/* "$DEBUG_RESOURCES_DIR/Upgrade/"

    # Copy Metal shader
    if [ -f "Sources/TheQuickFox/Visual/MorphShader.metal" ]; then
        echo "⚡ Copying Metal shader for debug..."
        cp "Sources/TheQuickFox/Visual/MorphShader.metal" "$DEBUG_RESOURCES_DIR/"
    fi

    # Copy TheQuickFox logo if it exists
    if [ -f "Resources/TheQuickFoxLogo.png" ]; then
        cp "Resources/TheQuickFoxLogo.png" "$DEBUG_RESOURCES_DIR/"
    fi

    # Copy tail icon if it exists
    if [ -f "Resources/tail-black.svg" ]; then
        cp "Resources/tail-black.svg" "$DEBUG_RESOURCES_DIR/"
    fi
fi

# Create app bundle structure
echo "📁 Creating app bundle structure..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
echo "📋 Copying executable..."
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/"

# Copy Info.plist
echo "📋 Copying Info.plist..."
cp "Info.plist" "$CONTENTS_DIR/"

# Update appcast URL for debug builds
if [ "$BUILD_CONFIG" = "debug" ]; then
    echo "🔧 Setting appcast URL to localhost for debug build..."
    /usr/libexec/PlistBuddy -c "Set :SUFeedURL http://localhost:4003/api/v1/appcast.xml" "$CONTENTS_DIR/Info.plist"
fi

# Copy all resources from Resources directory
echo "📦 Copying resources..."
cp -r "Resources/"* "$RESOURCES_DIR/"

# Copy onboarding resources
if [ -d "Sources/TheQuickFox/Onboarding/Resources" ]; then
    echo "📚 Copying onboarding resources..."
    mkdir -p "$RESOURCES_DIR/Onboarding"
    cp -r "Sources/TheQuickFox/Onboarding/Resources"/* "$RESOURCES_DIR/Onboarding/"
fi

# Copy upgrade resources
if [ -d "Sources/TheQuickFox/Upgrade/Resources" ]; then
    echo "💳 Copying upgrade resources..."
    mkdir -p "$RESOURCES_DIR/Upgrade"
    cp -r "Sources/TheQuickFox/Upgrade/Resources"/* "$RESOURCES_DIR/Upgrade/"
fi

# Copy Metal shader
if [ -f "Sources/TheQuickFox/Visual/MorphShader.metal" ]; then
    echo "⚡ Copying Metal shader..."
    cp "Sources/TheQuickFox/Visual/MorphShader.metal" "$RESOURCES_DIR/"
fi

# Note: SPM resource bundle (TheQuickFox_TheQuickFox.bundle) is NOT copied
# because our code uses Bundle.main for resources, not Bundle.module.
# Individual resource files are copied above (onboarding, upgrade, metal shader, etc.)

# Make executable
chmod +x "$MACOS_DIR/$APP_NAME"

# Copy Sparkle framework
echo "📦 Embedding Sparkle.framework..."
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"

# Find Sparkle framework in build artifacts
if [ "$BUILD_UNIVERSAL" = true ]; then
    # For universal builds, use the xcframework which contains both architectures
    SPARKLE_FRAMEWORK="$MACOS_SRC_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
else
    # For single-arch builds, use the arch-specific directory
    SPARKLE_FRAMEWORK="$MACOS_SRC_DIR/.build/arm64-apple-macosx/$BUILD_CONFIG/Sparkle.framework"
fi
if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
    # Fallback - search for it
    echo "   Searching for Sparkle.framework..."
    SPARKLE_FRAMEWORK=$(find "$MACOS_SRC_DIR/.build" -name "Sparkle.framework" -type d | grep -E "(artifacts.*macos|arm64.*/$BUILD_CONFIG/)" | head -n 1)
fi

if [ -n "$SPARKLE_FRAMEWORK" ]; then
    echo "   Found Sparkle.framework at: $SPARKLE_FRAMEWORK"
    cp -R "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/"
    
    # Update rpath to find the framework
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME" 2>/dev/null || true
    echo "✅ Sparkle.framework embedded successfully"
else
    echo "❌ Error: Could not find Sparkle.framework"
    echo "   The app will crash at launch without it!"
fi

# Code signing
echo "🔏 Signing the app..."

# Source code signing configuration
# Use PROJECT_ROOT since SCRIPT_DIR might be relative and we've cd'd
CODESIGN_CONFIG="$PROJECT_ROOT/scripts/.util/codesign-config.sh"
if [ -f "$CODESIGN_CONFIG" ]; then
    echo "   Loading signing config from $CODESIGN_CONFIG"
    source "$CODESIGN_CONFIG"
else
    echo "   No signing config found at $CODESIGN_CONFIG"
    SIGNING_IDENTITY="-"
fi

if [ "$SIGNING_IDENTITY" = "-" ]; then
    echo "   Using ad-hoc signing (no certificate)"

    # Clear all extended attributes first
    echo "   Clearing extended attributes..."
    xattr -cr "$BUNDLE_DIR" 2>/dev/null || true

    # Remove all existing signatures
    echo "   Removing all existing signatures..."
    find "$BUNDLE_DIR" -type f \( -name "*.dylib" -o -name "*.framework" -o -name "*.app" -o -perm +111 \) | while read binary; do
        codesign --remove-signature "$binary" 2>/dev/null || true
    done

    # Sign the app bundle with --deep (includes resource bundle contents)
    echo "   Signing app bundle..."
    codesign --force --deep --sign - "$BUNDLE_DIR"
else
    echo "   Using certificate: $SIGNING_IDENTITY"

    # Clear all extended attributes first
    echo "   Clearing extended attributes..."
    xattr -cr "$BUNDLE_DIR" 2>/dev/null || true

    # Remove all existing signatures
    echo "   Removing all existing signatures..."
    find "$BUNDLE_DIR" -type f \( -name "*.dylib" -o -name "*.framework" -o -name "*.app" -o -perm +111 \) | while read binary; do
        codesign --remove-signature "$binary" 2>/dev/null || true
    done

    # Sign components individually (innermost to outermost) for proper notarization
    # --deep is unreliable for nested frameworks like Sparkle
    echo "   Signing Sparkle framework components..."

    SPARKLE_DIR="$FRAMEWORKS_DIR/Sparkle.framework/Versions/B"

    # Sign XPC services first (deepest)
    if [ -d "$SPARKLE_DIR/XPCServices" ]; then
        for xpc in "$SPARKLE_DIR/XPCServices"/*.xpc; do
            if [ -d "$xpc" ]; then
                echo "   Signing $(basename "$xpc")..."
                codesign --force --sign "$SIGNING_IDENTITY" --timestamp --options runtime "$xpc"
            fi
        done
    fi

    # Sign nested apps
    if [ -d "$SPARKLE_DIR/Updater.app" ]; then
        echo "   Signing Updater.app..."
        codesign --force --sign "$SIGNING_IDENTITY" --timestamp --options runtime "$SPARKLE_DIR/Updater.app"
    fi

    # Sign helper binaries
    for helper in Autoupdate Sparkle; do
        if [ -f "$SPARKLE_DIR/$helper" ]; then
            echo "   Signing $helper..."
            codesign --force --sign "$SIGNING_IDENTITY" --timestamp --options runtime "$SPARKLE_DIR/$helper"
        fi
    done

    # Sign the framework itself
    echo "   Signing Sparkle.framework..."
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp --options runtime "$FRAMEWORKS_DIR/Sparkle.framework"

    # Finally sign the main app bundle
    echo "   Signing main app bundle..."
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp --options runtime "$BUNDLE_DIR"
fi

echo "✅ Successfully built $BUNDLE_DIR"
echo ""
echo "🚀 You can now:"
echo "1. Double-click $BUNDLE_DIR to launch TheQuickFox"
echo "2. Drag it to your Applications folder"
echo "3. It will show in the dock with your fox icon!"
echo ""
echo "💡 Use the status bar menu to toggle dock visibility"
