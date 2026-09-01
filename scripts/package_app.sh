#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-Codex Usage}"
EXECUTABLE_NAME="CodexUsage"
BUNDLE_ID="${BUNDLE_ID:-app.codexusage.local}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-2}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-auto}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-debug}"
EXECUTABLE_PATH="${EXECUTABLE_PATH:-}"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
ENTITLEMENTS="$ROOT_DIR/Packaging/CodexUsage.entitlements"
BUILD_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-build.XXXXXX")"
STAGED_APP="$BUILD_WORK_DIR/$APP_NAME.app"

cleanup() {
  /bin/rm -rf "$BUILD_WORK_DIR"
}

trap cleanup EXIT

cd "$ROOT_DIR"
if [[ -n "$EXECUTABLE_PATH" ]]; then
  if [[ ! -f "$EXECUTABLE_PATH" ]]; then
    echo "error: executable not found: $EXECUTABLE_PATH" >&2
    exit 2
  fi
  BUILT_EXECUTABLE="$EXECUTABLE_PATH"
else
  swift build --configuration "$BUILD_CONFIGURATION" --product "$EXECUTABLE_NAME"
  BIN_DIR="$(swift build --configuration "$BUILD_CONFIGURATION" --show-bin-path)"
  BUILT_EXECUTABLE="$BIN_DIR/$EXECUTABLE_NAME"
fi

mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
/bin/cp "$BUILT_EXECUTABLE" \
  "$STAGED_APP/Contents/MacOS/$EXECUTABLE_NAME"
"$ROOT_DIR/scripts/compile_app_icon.sh" \
  "$STAGED_APP/Contents/Resources" \
  "$BUNDLE_ID" \
  "$BUILD_WORK_DIR/CodexUsageIcon.partial.plist" >/dev/null
/usr/bin/sed \
  -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" \
  -e "s/__VERSION__/$VERSION/g" \
  -e "s/__BUILD__/$BUILD_NUMBER/g" \
  "$ROOT_DIR/Packaging/Info.plist.in" \
  > "$STAGED_APP/Contents/Info.plist"

if [[ "$SIGNING_IDENTITY" == "auto" ]]; then
  SIGNING_IDENTITY="$(
    /usr/bin/security find-identity -v -p codesigning |
      /usr/bin/awk '/Developer ID Application/ { print $2; exit }'
  )"
  if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="$(
      /usr/bin/security find-identity -v -p codesigning |
        /usr/bin/awk '/Apple Development/ { print $2; exit }'
    )"
  fi
fi

if [[ -n "$SIGNING_IDENTITY" && "$SIGNING_IDENTITY" != "-" ]]; then
  SIGNING_DETAILS="$(
    /usr/bin/security find-identity -v -p codesigning |
      /usr/bin/awk -v identity="$SIGNING_IDENTITY" \
        'index($0, identity) { print; exit }'
  )"
  TIMESTAMP_ARGS=()
  if [[ "$SIGNING_DETAILS" == *"Developer ID Application"* \
      || "$SIGNING_IDENTITY" == "Developer ID Application:"* ]]; then
    TIMESTAMP_ARGS=(--timestamp)
  fi
  /usr/bin/codesign --force --options runtime "${TIMESTAMP_ARGS[@]}" \
    --sign "$SIGNING_IDENTITY" \
    --entitlements "$ENTITLEMENTS" "$STAGED_APP"
else
  echo "warning: no signing identity found; using ad-hoc signing" >&2
  /usr/bin/codesign --force --options runtime --sign - \
    --entitlements "$ENTITLEMENTS" "$STAGED_APP"
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$STAGED_APP"
mkdir -p "$ROOT_DIR/dist"
/bin/rm -rf "$APP_DIR"
/usr/bin/ditto "$STAGED_APP" "$APP_DIR"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "$APP_DIR"
