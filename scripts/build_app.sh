#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

echo "🔨 Building Chibiori Release Binary with macOS 27 Liquid Glass support..."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SDK_PATH=$(xcrun --show-sdk-path 2>/dev/null || echo "")
if [ -n "$SDK_PATH" ]; then
    swift build -c release -Xswiftc -target -Xswiftc arm64-apple-macosx27.0 -Xswiftc -sdk -Xswiftc "$SDK_PATH"
else
    swift build -c release
fi

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
BINARY_PATH=$(find "$DIR/.build" -type f -name "Chibiori" -perm +111 | grep -i "release" | head -n 1)
if [ -z "$BINARY_PATH" ]; then
    BINARY_PATH=$(find "$DIR/.build" -type f -name "Chibiori" -perm +111 | head -n 1)
fi
echo "📦 Copying binary from: $BINARY_PATH"
cp "$BINARY_PATH" "$MACOS/Chibiori"
chmod +x "$MACOS/Chibiori"

# Copy Icon
if [ -f "$DIR/Chibiori_Logo.icns" ]; then
    cp "$DIR/Chibiori_Logo.icns" "$RESOURCES/Chibiori_Logo.icns"
fi

# Copy Dub Datasets
if [ -d "$DIR/Resources/dubs" ]; then
    echo "📦 Copying dub datasets into Resources..."
    mkdir -p "$RESOURCES/dubs"
    cp -R "$DIR/Resources/dubs/" "$RESOURCES/dubs/"
fi

# Copy Resource Bundles (if any)
find "$DIR/.build" -name "*.bundle" 2>/dev/null | while read -r bundle; do
    echo "📦 Copying resource bundle: $bundle"
    cp -R "$bundle" "$RESOURCES/"
    cp -R "$bundle" "$MACOS/"
done

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
    <string>1.0.14</string>
    <key>CFBundleVersion</key>
    <string>15</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>DTSDKName</key>
    <string>macosx27.0</string>
    <key>DTPlatformVersion</key>
    <string>27.0</string>
    <key>DTXcode</key>
    <string>2700</string>
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

if [ -d "/Applications/Chibiori.app" ] && [ -w "/Applications" ]; then
    echo "📦 Updating /Applications/Chibiori.app..."
    rm -rf "/Applications/Chibiori.app"
    cp -R "$APP_PATH" "/Applications/"
    echo "✅ Synchronized to /Applications/Chibiori.app"
fi
