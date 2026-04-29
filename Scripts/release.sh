#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
#  Scripts/release.sh
#  Build, sign, notarize and copy Wired Server artefacts to ~/Downloads.
#
#  Usage:
#    bash Scripts/release.sh [debug|release]          (default: release)
#
#  Optional environment variables:
#    WIRED_MARKETING_VERSION  override marketing version  (default: from last git tag)
#    WIRED_BUILD_NUMBER       override build number       (default: from last git tag)
#    WIRED_GIT_COMMIT         override commit hash        (default: current HEAD)
#    APPLE_SIGN_IDENTITY      codesign identity           (default: auto from keychain)
#    NOTARY_PROFILE           notarytool keychain profile (enables notarization)
#    NOTARIZE                 force notarization (1/true/yes; auto if NOTARY_PROFILE set)
# ─────────────────────────────────────────────────────────────────────────────

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_CONFIG="${1:-release}"
DOWNLOADS_DIR="$HOME/Downloads"

# ── Version: auto-detect from last git tag (e.g. v3.0-beta.21+38) ────────────

detect_version_from_tag() {
  local tag stripped marketing build
  tag="$(git -C "$ROOT_DIR" describe --tags --abbrev=0 2>/dev/null || echo "")"
  [[ -z "$tag" ]] && return 1
  stripped="${tag#v}"                    # e.g. "3.0-beta.21+38"
  marketing="${stripped%%+*}"            # e.g. "3.0-beta.21"
  build="1"
  [[ "$stripped" == *+* ]] && build="${stripped##*+}"
  echo "${marketing}|${build}"
}

if VERSION_INFO="$(detect_version_from_tag 2>/dev/null)"; then
  DETECTED_MARKETING="${VERSION_INFO%%|*}"
  DETECTED_BUILD="${VERSION_INFO##*|}"
else
  DETECTED_MARKETING="3.0"
  DETECTED_BUILD="1"
fi

MARKETING_VERSION="${WIRED_MARKETING_VERSION:-$DETECTED_MARKETING}"
BUILD_NUMBER="${WIRED_BUILD_NUMBER:-$DETECTED_BUILD}"
GIT_COMMIT="${WIRED_GIT_COMMIT:-$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")}"
TAG="${MARKETING_VERSION}+${BUILD_NUMBER}"

echo "============================================================"
echo "  Wired Server – release"
echo "  Version  : ${TAG}"
echo "  Commit   : ${GIT_COMMIT}"
echo "  Config   : ${BUILD_CONFIG}"
echo "============================================================"
echo ""

# ── Delegate all building / signing / notarization to the main script ─────────

export WIRED_MARKETING_VERSION="$MARKETING_VERSION"
export WIRED_BUILD_NUMBER="$BUILD_NUMBER"
export WIRED_GIT_COMMIT="$GIT_COMMIT"

bash "$ROOT_DIR/Scripts/build-wired-server-app.sh" "$BUILD_CONFIG"

# ── Copy artefacts to ~/Downloads ─────────────────────────────────────────────

DIST_DIR="$ROOT_DIR/dist"
APP_ZIP="$DIST_DIR/Wired-Server.app.zip"
SERVER_ZIP="$DIST_DIR/wired3.zip"
DIST_APP="$DIST_DIR/Wired Server.app"

mkdir -p "$DOWNLOADS_DIR"

echo ""
echo "==> Copying artefacts to: ${DOWNLOADS_DIR}"

copied=0

if [[ -f "$APP_ZIP" ]]; then
  DEST="$DOWNLOADS_DIR/Wired-Server-${TAG}.app.zip"
  cp -f "$APP_ZIP" "$DEST"
  echo "    Wired-Server-${TAG}.app.zip"
  copied=$((copied + 1))
fi

if [[ -f "$SERVER_ZIP" ]]; then
  DEST="$DOWNLOADS_DIR/wired3-${TAG}.zip"
  cp -f "$SERVER_ZIP" "$DEST"
  echo "    wired3-${TAG}.zip"
  copied=$((copied + 1))
fi

if [[ -d "$DIST_APP" ]]; then
  DEST_APP="$DOWNLOADS_DIR/Wired Server.app"
  rm -rf "$DEST_APP"
  cp -R "$DIST_APP" "$DEST_APP"
  echo "    Wired Server.app"
  copied=$((copied + 1))
fi

if [[ $copied -eq 0 ]]; then
  echo "    WARNING: No artefacts found in $DIST_DIR"
fi

echo ""
echo "==> Release complete"
