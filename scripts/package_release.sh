#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-Codex Usage}"
EXECUTABLE_NAME="CodexUsage"
BUNDLE_ID="${BUNDLE_ID:-app.codexusage.local}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-4}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_PASSWORD}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-auto}"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
RELEASE_DIR="$ROOT_DIR/dist/release"
ARTIFACT_BASENAME="Codex-Usage-$VERSION-$BUILD_NUMBER"
DMG_PATH="$RELEASE_DIR/$ARTIFACT_BASENAME.dmg"
ZIP_PATH="$RELEASE_DIR/$ARTIFACT_BASENAME.zip"
CHECKSUM_PATH="$RELEASE_DIR/SHA256SUMS.txt"
RELEASE_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-release.XXXXXX")"
ARM_BUILD_DIR="$RELEASE_WORK_DIR/arm64"
X86_BUILD_DIR="$RELEASE_WORK_DIR/x86_64"
UNIVERSAL_EXECUTABLE="$RELEASE_WORK_DIR/$EXECUTABLE_NAME"
SUBMISSION_ZIP="$RELEASE_WORK_DIR/$ARTIFACT_BASENAME-submission.zip"
DMG_STAGE="$RELEASE_WORK_DIR/dmg"

cleanup() {
  /bin/rm -rf "$RELEASE_WORK_DIR"
}

fail() {
  echo "error: $1" >&2
  exit "${2:-1}"
}

trap cleanup EXIT

if [[ "$SIGNING_IDENTITY" == "auto" ]]; then
  SIGNING_IDENTITY="$(
    /usr/bin/security find-identity -v -p codesigning |
      /usr/bin/awk '/Developer ID Application/ { print $2; exit }'
  )"
fi

[[ -n "$SIGNING_IDENTITY" && "$SIGNING_IDENTITY" != "-" ]] || \
  fail "a Developer ID Application signing identity is required" 3

SIGNING_DETAILS="$(
  /usr/bin/security find-identity -v -p codesigning |
    /usr/bin/awk -v identity="$SIGNING_IDENTITY" \
      'index($0, identity) { print; exit }'
)"
[[ "$SIGNING_DETAILS" == *"Developer ID Application"* ]] || \
  fail "the selected identity is not a Developer ID Application certificate" 3

/usr/bin/xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" \
  >/dev/null || fail "notary profile '$NOTARY_PROFILE' is unavailable" 4

cd "$ROOT_DIR"
swift build --configuration release \
  --triple arm64-apple-macosx13.0 \
  --scratch-path "$ARM_BUILD_DIR" \
  --product "$EXECUTABLE_NAME"
swift build --configuration release \
  --triple x86_64-apple-macosx13.0 \
  --scratch-path "$X86_BUILD_DIR" \
  --product "$EXECUTABLE_NAME"

/usr/bin/lipo -create \
  "$ARM_BUILD_DIR/arm64-apple-macosx/release/$EXECUTABLE_NAME" \
  "$X86_BUILD_DIR/x86_64-apple-macosx/release/$EXECUTABLE_NAME" \
  -output "$UNIVERSAL_EXECUTABLE"
/usr/bin/lipo "$UNIVERSAL_EXECUTABLE" -verify_arch arm64 x86_64

EXECUTABLE_PATH="$UNIVERSAL_EXECUTABLE" \
  APP_NAME="$APP_NAME" \
  BUNDLE_ID="$BUNDLE_ID" \
  VERSION="$VERSION" \
  BUILD_NUMBER="$BUILD_NUMBER" \
  SIGNING_IDENTITY="$SIGNING_IDENTITY" \
  "$ROOT_DIR/scripts/package_app.sh" >/dev/null

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"
/usr/sbin/spctl --assess --type execute --verbose=2 "$APP_DIR" >/dev/null 2>&1 \
  || true

/usr/bin/ditto -c -k --keepParent "$APP_DIR" "$SUBMISSION_ZIP"
/usr/bin/xcrun notarytool submit "$SUBMISSION_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait --timeout 1h
/usr/bin/xcrun stapler staple "$APP_DIR"
/usr/bin/xcrun stapler validate "$APP_DIR"

/bin/mkdir -p "$DMG_STAGE" "$RELEASE_DIR"
/usr/bin/ditto "$APP_DIR" "$DMG_STAGE/$APP_NAME.app"
/bin/ln -s /Applications "$DMG_STAGE/Applications"
/bin/rm -f "$DMG_PATH" "$ZIP_PATH" "$CHECKSUM_PATH"
/usr/bin/hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGE" \
  -format UDZO \
  -ov "$DMG_PATH"
/usr/bin/codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
/usr/bin/xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait --timeout 1h
/usr/bin/xcrun stapler staple "$DMG_PATH"
/usr/bin/xcrun stapler validate "$DMG_PATH"

/usr/bin/ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
(
  cd "$RELEASE_DIR"
  /usr/bin/shasum -a 256 "$(basename "$DMG_PATH")" \
    "$(basename "$ZIP_PATH")" > "$(basename "$CHECKSUM_PATH")"
)

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"
/usr/sbin/spctl --assess --type execute --verbose=2 "$APP_DIR"
/usr/bin/hdiutil verify "$DMG_PATH"

echo "$DMG_PATH"
echo "$ZIP_PATH"
echo "$CHECKSUM_PATH"
