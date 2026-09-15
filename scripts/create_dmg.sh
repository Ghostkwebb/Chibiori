#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

APP_PATH="$DIR/Chibiori.app"
DMG_PATH="$DIR/Chibiori.dmg"
ICON_PATH="$DIR/Chibiori_Logo.icns"
STAGING_DIR="$DIR/dmg_staging"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Chibiori.app not found. Run ./scripts/build_app.sh first."
    exit 1
fi

echo "💿 Creating styled DMG with custom volume icon..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"

if command -v create-dmg &> /dev/null; then
    create-dmg \
        --volname "Chibiori" \
        --volicon "$ICON_PATH" \
        --window-pos 200 120 \
        --window-size 500 320 \
        --icon-size 100 \
        --icon "Chibiori.app" 130 150 \
        --hide-extension "Chibiori.app" \
        --app-drop-link 370 150 \
        --no-internet-enable \
        --overwrite \
        "$DMG_PATH" \
        "$STAGING_DIR"
else
    echo "⚠️  create-dmg not found. Falling back to hdiutil..."
    hdiutil create -volname "Chibiori" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
fi

rm -rf "$STAGING_DIR"
echo "✅ Successfully generated: $DMG_PATH"
