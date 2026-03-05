#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_CONFIG="${1:-release}"
APP_NAME="Wired Server"
EXECUTABLE_NAME="WiredServerApp"
BUNDLE_ID="fr.read-write.wiredserver.swift"
APP_DIR="$ROOT_DIR/dist/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST="$CONTENTS_DIR/Info.plist"

if [[ "$BUILD_CONFIG" != "debug" && "$BUILD_CONFIG" != "release" ]]; then
  echo "Usage: $0 [debug|release]"
  exit 1
fi

echo "==> Building $EXECUTABLE_NAME ($BUILD_CONFIG)"
cd "$ROOT_DIR"
swift build -c "$BUILD_CONFIG" --product "$EXECUTABLE_NAME"

BINARY_PATH="$ROOT_DIR/.build/$BUILD_CONFIG/$EXECUTABLE_NAME"
if [[ ! -x "$BINARY_PATH" ]]; then
  echo "Binary not found: $BINARY_PATH"
  exit 1
fi

echo "==> Creating app bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BINARY_PATH" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod 755 "$MACOS_DIR/$EXECUTABLE_NAME"

cat > "$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

# Bundle icon (tracked in this repository).
ICON_SOURCE="$ROOT_DIR/Assets/WiredServer.icns"
if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "Missing icon: $ICON_SOURCE"
  exit 1
fi

cp "$ICON_SOURCE" "$RESOURCES_DIR/WiredServer.icns"
if ! /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string WiredServer.icns" "$INFO_PLIST" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile WiredServer.icns" "$INFO_PLIST"
fi
echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP_DIR"

echo "==> Done"
echo "$APP_DIR"
