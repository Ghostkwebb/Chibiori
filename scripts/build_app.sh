#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

echo "🔨 Building Chibiori Release Binary..."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build -c release

APP_NAME="Chibiori.app"
APP_PATH="$DIR/$APP_NAME"
CONTENTS="$APP_PATH/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "📦 Packaging $APP_NAME..."
rm -rf "$APP_PATH"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

# Copy binary
cp "$DIR/.build/release/Chibiori" "$MACOS/Chibiori"
chmod +x "$MACOS/Chibiori"

# Copy Icon
if [ -f "$DIR/Chibiori_Logo.icns" ]; then
    cp "$DIR/Chibiori_Logo.icns" "$RESOURCES/Chibiori_Logo.icns"
fi

# Copy Resource Bundles (SPM Assets)
if [ -d "$DIR/.build/release/Chibiori_Chibiori.bundle" ]; then
    cp -R "$DIR/.build/release/Chibiori_Chibiori.bundle" "$RESOURCES/"
fi

# Create Info.plist
cat << 'EOF' > "$CONTENTS/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Chibiori</string>
    <key>CFBundleIconFile</key>
    <string>Chibiori_Logo</string>
    <key>CFBundleIdentifier</key>
    <string>com.ghostkwebb.chibiori</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Chibiori</string>
    <key>CFBundleDisplayName</key>
    <string>Chibiori</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.2</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 GhostKWebb. All rights reserved.</string>
</dict>
</plist>
EOF

# Create PkgInfo
echo -n "APPL????" > "$CONTENTS/PkgInfo"

# Ad-hoc code sign for macOS Gatekeeper and CloudKit entitlements
echo "✍️ Signing application bundle with CloudKit entitlements..."
if [ -f "$DIR/Chibiori.entitlements" ]; then
    codesign --force --deep --sign - --entitlements "$DIR/Chibiori.entitlements" "$APP_PATH"
else
    codesign --force --deep --sign - "$APP_PATH"
fi

echo "✅ Successfully built and packaged Chibiori.app at:"
echo "   $APP_PATH"
