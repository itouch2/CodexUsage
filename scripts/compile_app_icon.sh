#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon/CodexUsage.icon"
OUTPUT_DIR="${1:?usage: compile_app_icon.sh OUTPUT_DIR [BUNDLE_ID] [PARTIAL_PLIST]}"
BUNDLE_ID="${2:-app.codexusage.local}"
PARTIAL_PLIST="${3:-$OUTPUT_DIR/CodexUsage-Generated.plist}"
ACTOOL="$(xcrun --find actool)"

mkdir -p "$OUTPUT_DIR" "$(dirname "$PARTIAL_PLIST")"

"$ACTOOL" "$ICON_SOURCE" \
  --compile "$OUTPUT_DIR" \
  --output-format human-readable-text \
  --notices \
  --warnings \
  --output-partial-info-plist "$PARTIAL_PLIST" \
  --app-icon CodexUsage \
  --enable-on-demand-resources NO \
  --development-region en \
  --target-device mac \
  --minimum-deployment-target 13.0 \
  --platform macosx \
  --bundle-identifier "$BUNDLE_ID"

test -f "$OUTPUT_DIR/Assets.car"
test -f "$OUTPUT_DIR/CodexUsage.icns"

echo "$OUTPUT_DIR/CodexUsage.icns"
