#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_CONFIG="${1:-release}"
APP_NAME="Wired Server"
EXECUTABLE_NAME="WiredServerApp"
SERVER_BINARY_NAME="wired3"
BUNDLE_ID="fr.read-write.WiredServer3"
MARKETING_VERSION="${WIRED_MARKETING_VERSION:-3.0}"
BUILD_NUMBER="${WIRED_BUILD_NUMBER:-1}"
GIT_COMMIT="${WIRED_GIT_COMMIT:-unknown}"
APP_DIR="$ROOT_DIR/dist/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST="$CONTENTS_DIR/Info.plist"
DIST_SERVER_BINARY="$ROOT_DIR/dist/$SERVER_BINARY_NAME"
APP_ZIP_PATH="$ROOT_DIR/dist/Wired-Server.app.zip"
SERVER_ZIP_PATH="$ROOT_DIR/dist/$SERVER_BINARY_NAME.zip"
NOTARIZE="${NOTARIZE:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
VERSION_SWIFT="$ROOT_DIR/Sources/wired3/Version.swift"
VERSION_SWIFT_BACKUP=""

if [[ "$BUILD_CONFIG" != "debug" && "$BUILD_CONFIG" != "release" ]]; then
  echo "Usage: $0 [debug|release]"
  exit 1
fi

if [[ ! "$MARKETING_VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
  echo "Invalid WIRED_MARKETING_VERSION: $MARKETING_VERSION"
  exit 1
fi
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Invalid WIRED_BUILD_NUMBER: $BUILD_NUMBER"
  exit 1
fi

cleanup_version_file() {
  if [[ -n "$VERSION_SWIFT_BACKUP" && -f "$VERSION_SWIFT_BACKUP" ]]; then
    cp "$VERSION_SWIFT_BACKUP" "$VERSION_SWIFT"
    rm -f "$VERSION_SWIFT_BACKUP"
  fi
}
trap cleanup_version_file EXIT

if [[ -f "$VERSION_SWIFT" ]]; then
  VERSION_SWIFT_BACKUP="$(mktemp)"
  cp "$VERSION_SWIFT" "$VERSION_SWIFT_BACKUP"
fi

cat > "$VERSION_SWIFT" <<SWIFT
import Foundation

enum WiredServerVersion {
    static let marketingVersion = "$MARKETING_VERSION"
    static let buildNumber = "$BUILD_NUMBER"
    static let commit = "$GIT_COMMIT"
    static let number = marketingVersion
    static let display = "wired3 \\(marketingVersion) (\\(buildNumber)+\\(commit))"
}
SWIFT

echo "==> Building $EXECUTABLE_NAME ($BUILD_CONFIG)"
cd "$ROOT_DIR"

run_swift_build() {
  swift build -c "$BUILD_CONFIG" --product "$EXECUTABLE_NAME"
  swift build -c "$BUILD_CONFIG" --product "$SERVER_BINARY_NAME"
}

BUILD_LOG="$(mktemp)"
if ! run_swift_build 2>&1 | tee "$BUILD_LOG"; then
  if grep -q "PCH was compiled with module cache path" "$BUILD_LOG"; then
    echo "==> Detected stale module cache path, cleaning .build and retrying once"
    rm -rf "$ROOT_DIR/.build"
    run_swift_build
  else
    echo "Build failed. See log: $BUILD_LOG" >&2
    exit 1
  fi
fi
rm -f "$BUILD_LOG"

BIN_DIR="$(swift build -c "$BUILD_CONFIG" --show-bin-path)"
BINARY_PATH="$BIN_DIR/$EXECUTABLE_NAME"
SERVER_BINARY_PATH="$BIN_DIR/$SERVER_BINARY_NAME"
if [[ ! -x "$BINARY_PATH" ]]; then
  echo "Binary not found: $BINARY_PATH"
  exit 1
fi
if [[ ! -x "$SERVER_BINARY_PATH" ]]; then
  echo "Binary not found: $SERVER_BINARY_PATH"
  exit 1
fi

echo "==> Creating app bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BINARY_PATH" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod 755 "$MACOS_DIR/$EXECUTABLE_NAME"

cp "$SERVER_BINARY_PATH" "$DIST_SERVER_BINARY"
chmod 755 "$DIST_SERVER_BINARY"

# Embed wired3 inside the app so installation works on machines without source checkout.
cp "$SERVER_BINARY_PATH" "$RESOURCES_DIR/$SERVER_BINARY_NAME"
chmod 755 "$RESOURCES_DIR/$SERVER_BINARY_NAME"

# Embed default runtime assets used by wired3 bootstrap.
cp "$ROOT_DIR/Sources/wired3/wired.xml" "$RESOURCES_DIR/wired.xml"
cp "$ROOT_DIR/Sources/wired3/banner.png" "$RESOURCES_DIR/banner.png"

echo "==> Copying SwiftPM resource bundles"
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
  cp -R "$bundle" "$RESOURCES_DIR/"
done
shopt -u nullglob

cat > "$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>fr</string>
  </array>
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
  <string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>WiredGitCommit</key>
  <string>$GIT_COMMIT</string>
  <key>WiredBuildMetadata</key>
  <string>$MARKETING_VERSION ($BUILD_NUMBER+$GIT_COMMIT)</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
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

resolve_signing_identity() {
  if [[ -n "${APPLE_SIGN_IDENTITY:-}" ]]; then
    echo "$APPLE_SIGN_IDENTITY"
    return 0
  fi

  local auto
  auto="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\\(Developer ID Application:[^"]*\\)".*/\\1/p' | head -n 1)"
  if [[ -n "$auto" ]]; then
    echo "$auto"
  fi
}

sign_file() {
  local identity="$1"
  local file="$2"
  codesign --force --timestamp --options runtime --sign "$identity" "$file"
}

sign_app_bundle() {
  local identity="$1"
  local app="$2"
  codesign --force --deep --timestamp --options runtime --sign "$identity" "$app"
}

notarize_zip() {
  local profile="$1"
  local zip_path="$2"
  local label="$3"

  echo "==> Notarizing $label"
  xcrun notarytool submit "$zip_path" --keychain-profile "$profile" --wait
}

SIGNING_IDENTITY="$(resolve_signing_identity || true)"
SIGNING_MODE="adhoc"
if [[ -n "$SIGNING_IDENTITY" ]]; then
  SIGNING_MODE="developer-id"
  if [[ -n "${APPLE_DEV_ACCOUNT:-}" ]]; then
    echo "==> Signing with Developer ID for account hint: $APPLE_DEV_ACCOUNT"
  fi
  echo "==> Using signing identity: $SIGNING_IDENTITY"

  sign_file "$SIGNING_IDENTITY" "$DIST_SERVER_BINARY"
  sign_file "$SIGNING_IDENTITY" "$RESOURCES_DIR/$SERVER_BINARY_NAME"
  sign_app_bundle "$SIGNING_IDENTITY" "$APP_DIR"
else
  echo "==> No Developer ID identity found, using ad-hoc signing"
  codesign --force --sign - "$DIST_SERVER_BINARY"
  codesign --force --sign - "$RESOURCES_DIR/$SERVER_BINARY_NAME"
  codesign --force --deep --sign - "$APP_DIR"
fi

if [[ -z "$NOTARIZE" ]]; then
  if [[ -n "$NOTARY_PROFILE" ]]; then
    NOTARIZE="1"
  else
    NOTARIZE="0"
  fi
fi

case "$NOTARIZE" in
  1|true|TRUE|yes|YES) NOTARIZE="1" ;;
  0|false|FALSE|no|NO|"") NOTARIZE="0" ;;
  *)
    echo "Invalid NOTARIZE value: $NOTARIZE (expected 1/0/true/false)"
    exit 1
    ;;
esac

echo "==> Creating distribution archives"
rm -f "$APP_ZIP_PATH" "$SERVER_ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$APP_ZIP_PATH"
ditto -c -k --keepParent "$DIST_SERVER_BINARY" "$SERVER_ZIP_PATH"

if [[ "$NOTARIZE" == "1" ]]; then
  if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "Notarization requires a Developer ID signature. Set APPLE_SIGN_IDENTITY."
    exit 1
  fi
  if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "NOTARIZE=1 requires NOTARY_PROFILE (xcrun notarytool keychain profile name)."
    exit 1
  fi

  echo "==> Creating notarization archives"
  notarize_zip "$NOTARY_PROFILE" "$APP_ZIP_PATH" "$APP_NAME"
  notarize_zip "$NOTARY_PROFILE" "$SERVER_ZIP_PATH" "$SERVER_BINARY_NAME"

  echo "==> Stapling notarization ticket to app"
  xcrun stapler staple "$APP_DIR"
  xcrun stapler validate "$APP_DIR"
  rm -f "$APP_ZIP_PATH"
  ditto -c -k --keepParent "$APP_DIR" "$APP_ZIP_PATH"
fi

echo "==> Verifying signatures"
codesign --verify --deep --strict --verbose=2 "$DIST_SERVER_BINARY"
codesign --verify --strict --verbose=2 "$RESOURCES_DIR/$SERVER_BINARY_NAME"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

if [[ "$SIGNING_MODE" == "developer-id" ]]; then
  echo "==> Gatekeeper assessment"
  spctl --assess --type execute --verbose=4 "$APP_DIR"
else
  echo "==> Skipping Gatekeeper assessment for ad-hoc signature"
fi

echo "==> Done"
echo "$APP_DIR"
