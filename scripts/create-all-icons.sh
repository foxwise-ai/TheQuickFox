#!/bin/bash

# Create all icons script for TheQuickFox
# Usage: ./scripts/create-all-icons.sh dock-image.png menubar-image.png

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <dock-icon-source> <menubar-icon-source>"
    echo "Example: $0 fox-image.png menubar-icon.png"
    echo ""
    echo "Requirements:"
    echo "- Dock icon: Color image, preferably 1024x1024 or larger"
    echo "- Menu bar icon: Black/white image with transparency, ideally square"
    exit 1
fi

DOCK_SOURCE="$1"
MENUBAR_SOURCE="$2"

if [ ! -f "$DOCK_SOURCE" ]; then
    echo "Error: Dock source image '$DOCK_SOURCE' not found!"
    exit 1
fi

if [ ! -f "$MENUBAR_SOURCE" ]; then
    echo "Error: Menu bar source image '$MENUBAR_SOURCE' not found!"
    exit 1
fi

# Get macos directory path
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACOS_DIR="$SCRIPT_DIR/../macos"

# Create directories
ICONSET_DIR="$MACOS_DIR/Resources/AppIcon.iconset"
MENUBAR_DIR="$MACOS_DIR/Resources/StatusBarIcon.iconset"
mkdir -p "$ICONSET_DIR"
mkdir -p "$MENUBAR_DIR"
mkdir -p "$MACOS_DIR/Resources"

echo "🦊 Creating dock icon from $DOCK_SOURCE..."

# Generate all required dock icon sizes
sips -z 16 16 "$DOCK_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$DOCK_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$DOCK_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$DOCK_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$DOCK_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$DOCK_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$DOCK_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$DOCK_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$DOCK_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$DOCK_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

# Create dock .icns file
iconutil -c icns "$ICONSET_DIR" -o "$MACOS_DIR/Resources/AppIcon.icns"

if [ $? -eq 0 ]; then
    echo "✅ Created dock icon: Resources/AppIcon.icns"
else
    echo "❌ Failed to create dock icon"
    exit 1
fi

echo "📊 Creating menu bar icon from $MENUBAR_SOURCE..."

# Generate menu bar icon sizes
# For PDFs, we need to rasterize them for the PNG versions
if [[ "$MENUBAR_SOURCE" == *.pdf ]]; then
    echo "Rasterizing PDF for PNG versions..."
    # Use sips to rasterize PDF to PNG at specific sizes
    sips -s format png -z 16 16 "$MENUBAR_SOURCE" --out "$MACOS_DIR/Resources/StatusBarIcon.png" >/dev/null
    sips -s format png -z 32 32 "$MENUBAR_SOURCE" --out "$MACOS_DIR/Resources/StatusBarIcon@2x.png" >/dev/null
else
    # For raster images, just resize
    sips -z 16 16 "$MENUBAR_SOURCE" --out "$MACOS_DIR/Resources/StatusBarIcon.png" >/dev/null
    sips -z 32 32 "$MENUBAR_SOURCE" --out "$MACOS_DIR/Resources/StatusBarIcon@2x.png" >/dev/null
fi

# Handle PDF version
if [[ "$MENUBAR_SOURCE" == *.pdf ]]; then
    echo "Source is PDF - checking size..."

    # Get PDF dimensions using sips
    PDF_HEIGHT=$(sips -g pixelHeight "$MENUBAR_SOURCE" | awk '/pixelHeight:/ {print $2}')

    if (( $(echo "$PDF_HEIGHT > 44" | bc -l) )); then
        echo "  PDF is ${PDF_HEIGHT}px tall - too large for menu bar (should be ~18-22pt)"
        echo "  ⚠️  Large PDFs may not render correctly in the menu bar"
    fi

    # For now, just copy the PDF as-is
    # Menu bar icons should be designed at the correct size
    echo "  Copying PDF as-is (design at 18-22pt for best results)..."
    cp "$MENUBAR_SOURCE" "$MACOS_DIR/Resources/StatusBarIcon.pdf"
elif [[ "$MENUBAR_SOURCE" == *.svg ]]; then
    echo "Source is SVG - converting to PDF at 18pt height..."
    # Try different SVG to PDF converters with size constraints
    if command -v rsvg-convert &> /dev/null; then
        rsvg-convert -f pdf -h 18 -o "$MACOS_DIR/Resources/StatusBarIcon.pdf" "$MENUBAR_SOURCE"
    elif command -v inkscape &> /dev/null; then
        inkscape "$MENUBAR_SOURCE" --export-height=18 --export-pdf="$MACOS_DIR/Resources/StatusBarIcon.pdf" 2>/dev/null
    else
        echo "Note: Install rsvg-convert or inkscape to convert SVG to PDF"
    fi
else
    echo "Note: For vector menu bar icons, provide a PDF or SVG source"
fi

echo "✅ Created menu bar icons:"
echo "   - macos/Resources/StatusBarIcon.png (16x16)"
echo "   - macos/Resources/StatusBarIcon@2x.png (32x32)"
[ -f "$MACOS_DIR/Resources/StatusBarIcon.pdf" ] && echo "   - macos/Resources/StatusBarIcon.pdf (vector)"

echo ""
echo "🎉 All icons created successfully!"
echo ""
echo "Next steps:"
echo "1. Update main.swift to use the menu bar icon:"
echo "   button.image = NSImage(named: \"StatusBarIcon\")"
echo "   button.image?.isTemplate = true"
echo "2. Add the icon files to your Xcode project or build script"
echo "3. Build and run!"
