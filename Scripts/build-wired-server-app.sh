#!/usr/bin/env bash
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
HELPER_BINARY_NAME="WiredServerHelper"
HELPER_BUNDLE_ID="fr.read-write.WiredServer3.Helper"
LAUNCH_SERVICES_DIR="$CONTENTS_DIR/Library/LaunchServices"
BUNDLE_DAEMONS_DIR="$CONTENTS_DIR/Library/LaunchDaemons"
NOTARIZE="${NOTARIZE:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

# Auto-load notary profile from ~/.wired-notary if not set via environment.
# File format (shell-sourceable):  NOTARY_PROFILE="<your-profile>"
if [[ -z "$NOTARY_PROFILE" && -f "${HOME}/.wired-notary" ]]; then
  # shellcheck source=/dev/null
  source "${HOME}/.wired-notary"
  NOTARY_PROFILE="${NOTARY_PROFILE:-}"
fi

VERSION_SWIFT="$ROOT_DIR/Sources/wired3/Core/Version.swift"
VERSION_SWIFT_BACKUP=""

if [[ "$BUILD_CONFIG" != "debug" && "$BUILD_CONFIG" != "release" ]]; then
  echo "Usage: $0 [debug|release]"
  exit 1
fi

if [[ ! "$MARKETING_VERSION" =~ ^[0-9]+(\.[0-9]+)*(-[a-zA-Z0-9.]+)?$ ]]; then
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

public enum WiredServerVersion {
    public static let marketingVersion = "$MARKETING_VERSION"
    public static let buildNumber = "$BUILD_NUMBER"
    public static let commit = "$GIT_COMMIT"
    public static let number = marketingVersion
    public static let display = "wired3 \\(marketingVersion) (\\(buildNumber)+\\(commit))"
}
SWIFT

# ── i18n lint: catch hardcoded UI strings before spending time on the build ───

echo "==> Checking for hardcoded UI strings"
I18N_VIOLATIONS="$(grep -rEn \
  'Text\("[A-Za-z]|Button\("[A-Za-z]|Label\("[A-Za-z]|Section\("[A-Za-z]|Toggle\("[A-Za-z]' \
  "$ROOT_DIR/Sources/WiredServerApp/" --include="*.swift" 2>/dev/null \
  | grep -v 'L(' || true)"

if [[ -n "$I18N_VIOLATIONS" ]]; then
  echo ""
  echo "  ERROR: Hardcoded UI strings found — wrap every user-visible string with L():"
  echo "$I18N_VIOLATIONS" | sed 's/^/    /'
  echo ""
  exit 1
fi
echo "    OK"

# ── Build ─────────────────────────────────────────────────────────────────────

echo "==> Building $EXECUTABLE_NAME ($BUILD_CONFIG)"
cd "$ROOT_DIR"

TARGET_ARCHS=("arm64" "x86_64")
UNIVERSAL_BIN_DIR="$ROOT_DIR/.build/universal/$BUILD_CONFIG"
mkdir -p "$UNIVERSAL_BIN_DIR"

build_for_arch() {
  local arch="$1"
  local scratch_path="$ROOT_DIR/.build/$BUILD_CONFIG-$arch"

  swift build -c "$BUILD_CONFIG" --arch "$arch" --scratch-path "$scratch_path" --product "$EXECUTABLE_NAME"
  swift build -c "$BUILD_CONFIG" --arch "$arch" --scratch-path "$scratch_path" --product "$SERVER_BINARY_NAME"
  swift build -c "$BUILD_CONFIG" --arch "$arch" --scratch-path "$scratch_path" --product "$HELPER_BINARY_NAME"
}

declare -a EXEC_SLICES=()
declare -a SERVER_SLICES=()
declare -a HELPER_SLICES=()

for arch in "${TARGET_ARCHS[@]}"; do
  echo "==> Building $EXECUTABLE_NAME ($BUILD_CONFIG, $arch)"
  BUILD_LOG="$(mktemp)"
  if ! build_for_arch "$arch" 2>&1 | tee "$BUILD_LOG"; then
    if grep -q "PCH was compiled with module cache path" "$BUILD_LOG"; then
      echo "==> Detected stale module cache path for $arch, cleaning and retrying once"
      rm -rf "$ROOT_DIR/.build/$BUILD_CONFIG-$arch"
      build_for_arch "$arch"
    else
      echo "Build failed for arch $arch. See log: $BUILD_LOG" >&2
      exit 1
    fi
  fi
  rm -f "$BUILD_LOG"

  ARCH_BIN_DIR="$ROOT_DIR/.build/$BUILD_CONFIG-$arch/$BUILD_CONFIG"
  ARCH_EXECUTABLE="$ARCH_BIN_DIR/$EXECUTABLE_NAME"
  ARCH_SERVER_BINARY="$ARCH_BIN_DIR/$SERVER_BINARY_NAME"

  if [[ ! -x "$ARCH_EXECUTABLE" ]]; then
    echo "Binary not found: $ARCH_EXECUTABLE"
    exit 1
  fi
  if [[ ! -x "$ARCH_SERVER_BINARY" ]]; then
    echo "Binary not found: $ARCH_SERVER_BINARY"
    exit 1
  fi

  EXEC_SLICES+=("$ARCH_EXECUTABLE")
  SERVER_SLICES+=("$ARCH_SERVER_BINARY")

  ARCH_HELPER_BINARY="$ARCH_BIN_DIR/$HELPER_BINARY_NAME"
  if [[ ! -x "$ARCH_HELPER_BINARY" ]]; then
    echo "Binary not found: $ARCH_HELPER_BINARY"
    exit 1
  fi
  HELPER_SLICES+=("$ARCH_HELPER_BINARY")
done

BINARY_PATH="$UNIVERSAL_BIN_DIR/$EXECUTABLE_NAME"
SERVER_BINARY_PATH="$UNIVERSAL_BIN_DIR/$SERVER_BINARY_NAME"

HELPER_BINARY_PATH="$UNIVERSAL_BIN_DIR/$HELPER_BINARY_NAME"

echo "==> Creating universal binaries (arm64 + x86_64)"
lipo -create "${EXEC_SLICES[@]}" -output "$BINARY_PATH"
lipo -create "${SERVER_SLICES[@]}" -output "$SERVER_BINARY_PATH"
lipo -create "${HELPER_SLICES[@]}" -output "$HELPER_BINARY_PATH"
chmod 755 "$BINARY_PATH" "$SERVER_BINARY_PATH" "$HELPER_BINARY_PATH"

SERVER_BINARY_SHA256="$(/usr/bin/shasum -a 256 "$SERVER_BINARY_PATH" | awk '{print $1}')"
if [[ -z "$SERVER_BINARY_SHA256" ]]; then
  echo "Failed to compute SHA-256 for $SERVER_BINARY_PATH"
  exit 1
fi

echo "==> Universal binary info"
lipo -info "$BINARY_PATH"
lipo -info "$SERVER_BINARY_PATH"
lipo -info "$HELPER_BINARY_PATH"

echo "==> Creating app bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$LAUNCH_SERVICES_DIR" "$BUNDLE_DAEMONS_DIR"

cp "$BINARY_PATH" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod 755 "$MACOS_DIR/$EXECUTABLE_NAME"

cp "$SERVER_BINARY_PATH" "$DIST_SERVER_BINARY"
chmod 755 "$DIST_SERVER_BINARY"

# Embed wired3 inside the app so installation works on machines without source checkout.
cp "$SERVER_BINARY_PATH" "$RESOURCES_DIR/$SERVER_BINARY_NAME"
chmod 755 "$RESOURCES_DIR/$SERVER_BINARY_NAME"

# Embed privileged helper for SMAppService.
cp "$HELPER_BINARY_PATH" "$LAUNCH_SERVICES_DIR/$HELPER_BUNDLE_ID"
chmod 755 "$LAUNCH_SERVICES_DIR/$HELPER_BUNDLE_ID"

# Bundle daemon plist for SMAppService.daemon registration.
cp "$ROOT_DIR/Sources/WiredServerHelper/LaunchDaemon.plist" "$BUNDLE_DAEMONS_DIR/$HELPER_BUNDLE_ID.plist"

# Embed default runtime assets used by wired3 bootstrap.
cp "$ROOT_DIR/Sources/WiredSwift/Resources/wired.xml" "$RESOURCES_DIR/wired.xml"
cp "$ROOT_DIR/Sources/wired3/banner.png" "$RESOURCES_DIR/banner.png"

echo "==> Copying SwiftPM resource bundles"
BUNDLE_SOURCE_DIR="$ROOT_DIR/.build/$BUILD_CONFIG-${TARGET_ARCHS[0]}/$BUILD_CONFIG"
shopt -s nullglob
for bundle in "$BUNDLE_SOURCE_DIR"/*.bundle; do
  cp -R "$bundle" "$RESOURCES_DIR/"
done
shopt -u nullglob

# Also copy .lproj dirs directly into Contents/Resources so Bundle.main can
# find strings even when the SPM resource bundle is absent (e.g. after a
# partial build or a distribution problem).
for lproj_dir in "$ROOT_DIR/Sources/WiredServerApp/Resources/"*.lproj; do
  [ -d "$lproj_dir" ] && cp -R "$lproj_dir" "$RESOURCES_DIR/"
done

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
    <string>de</string>
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
  <key>Wired3EmbeddedSHA256</key>
  <string>$SERVER_BINARY_SHA256</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>SMPrivilegedExecutables</key>
  <dict>
    <key>$HELPER_BUNDLE_ID</key>
    <string>anchor apple generic and identifier "$HELPER_BUNDLE_ID" and certificate leaf[subject.OU] = "VGB467J8DZ"</string>
  </dict>
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
  auto="$(security find-identity -v -p codesigning 2>/dev/null | sed -nE 's/.*"(Developer ID Application:[^"]*)".*/\1/p' | head -n 1)"
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

extract_notary_submission_id() {
  sed -nE 's/^[[:space:]]*id:[[:space:]]*([0-9a-fA-F-]{36})[[:space:]]*$/\1/p' | tail -n 1
}

is_transient_notary_error() {
  local output="${1:-}"
  [[ "$output" == *"HTTPClientError.connectTimeout"* ]] ||
    [[ "$output" == *"timed out"* ]] ||
    [[ "$output" == *"timeout"* ]] ||
    [[ "$output" == *"connection reset"* ]] ||
    [[ "$output" == *"connection refused"* ]] ||
    [[ "$output" == *"network connection was lost"* ]] ||
    [[ "$output" == *"HTTP status code: 500"* ]] ||
    [[ "$output" == *"HTTP status code: 502"* ]] ||
    [[ "$output" == *"HTTP status code: 503"* ]] ||
    [[ "$output" == *"HTTP status code: 504"* ]]
}

wait_for_notary_submission() {
  local profile="$1"
  local submission_id="$2"
  local max_attempts="${NOTARY_WAIT_RETRY_ATTEMPTS:-4}"
  local sleep_seconds="${NOTARY_WAIT_RETRY_DELAY_SECONDS:-30}"
  local attempt=1
  local output=""
  local status=0

  while true; do
    echo "==> Waiting for notarization submission $submission_id"
    if output="$(xcrun notarytool wait "$submission_id" --keychain-profile "$profile" --timeout "${NOTARY_WAIT_TIMEOUT:-30m}" 2>&1)"; then
      printf '%s\n' "$output"
      return 0
    fi
    status=$?
    printf '%s\n' "$output" >&2

    if (( attempt >= max_attempts )) || ! is_transient_notary_error "$output"; then
      return "$status"
    fi

    echo "==> Notary wait failed with a transient network error (attempt ${attempt}/${max_attempts}); retrying in ${sleep_seconds}s"
    sleep "$sleep_seconds"
    attempt=$((attempt + 1))
    sleep_seconds=$((sleep_seconds * 2))
  done
}

notarize_zip() {
  local profile="$1"
  local zip_path="$2"
  local label="$3"
  local max_attempts="${NOTARY_SUBMIT_RETRY_ATTEMPTS:-3}"
  local sleep_seconds="${NOTARY_SUBMIT_RETRY_DELAY_SECONDS:-30}"
  local attempt=1
  local output=""
  local status=0
  local submission_id=""

  echo "==> Notarizing $label"
  while true; do
    if output="$(xcrun notarytool submit "$zip_path" --keychain-profile "$profile" --wait --timeout "${NOTARY_WAIT_TIMEOUT:-30m}" 2>&1)"; then
      printf '%s\n' "$output"
      return 0
    fi
    status=$?
    printf '%s\n' "$output" >&2

    submission_id="$(printf '%s\n' "$output" | extract_notary_submission_id)"
    if [[ -n "$submission_id" ]]; then
      echo "==> Notary submission was created before the error: $submission_id"
      wait_for_notary_submission "$profile" "$submission_id"
      return $?
    fi

    if (( attempt >= max_attempts )) || ! is_transient_notary_error "$output"; then
      return "$status"
    fi

    echo "==> Notary submit failed with a transient network error (attempt ${attempt}/${max_attempts}); retrying in ${sleep_seconds}s"
    sleep "$sleep_seconds"
    attempt=$((attempt + 1))
    sleep_seconds=$((sleep_seconds * 2))
  done
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
  sign_file "$SIGNING_IDENTITY" "$LAUNCH_SERVICES_DIR/$HELPER_BUNDLE_ID"
  sign_app_bundle "$SIGNING_IDENTITY" "$APP_DIR"
else
  echo "==> No Developer ID identity found, using ad-hoc signing"
  codesign --force --sign - "$DIST_SERVER_BINARY"
  codesign --force --sign - "$RESOURCES_DIR/$SERVER_BINARY_NAME"
  codesign --force --sign - "$LAUNCH_SERVICES_DIR/$HELPER_BUNDLE_ID"
  codesign --force --deep --sign - "$APP_DIR"
fi

if [[ "$SIGNING_MODE" == "developer-id" && -z "$NOTARY_PROFILE" ]]; then
  echo ""
  echo "    TIP: Notarization is disabled. To enable it, create ~/.wired-notary:"
  echo "         NOTARY_PROFILE=\"<profile-name>\""
  echo "         Then store the credentials once with:"
  echo "         xcrun notarytool store-credentials \"<profile-name>\" --apple-id <id> --team-id <team>"
  echo ""
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

if [[ "$SIGNING_MODE" == "developer-id" && "$NOTARIZE" == "1" ]]; then
  echo "==> Gatekeeper assessment"
  spctl --assess --type execute --verbose=4 "$APP_DIR"
elif [[ "$SIGNING_MODE" == "developer-id" ]]; then
  echo "==> Gatekeeper assessment skipped (app not notarized)"
else
  echo "==> Skipping Gatekeeper assessment for ad-hoc signature"
fi

echo "==> Done"
echo "$APP_DIR"
