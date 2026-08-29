#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT_DIR/Resources/AppIcon/codex-usage-icon-concept-v2.png"
MASTER="$ROOT_DIR/Resources/AppIcon/codex-usage-icon-1024.png"
OUTPUT="$ROOT_DIR/Resources/AppIcon/CodexUsageIcon.icns"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-icon.XXXXXX")"
ICONSET="$WORK_DIR/CodexUsageIcon.iconset"

cleanup() {
  /bin/rm -rf "$WORK_DIR"
}

trap cleanup EXIT

mkdir -p "$ICONSET"
/usr/bin/sips -z 1024 1024 "$SOURCE" --out "$MASTER" >/dev/null

render() {
  local size="$1"
  local filename="$2"
  /usr/bin/sips -z "$size" "$size" "$MASTER" \
    --out "$ICONSET/$filename" >/dev/null
}

render 16 icon_16x16.png
render 32 icon_16x16@2x.png
render 32 icon_32x32.png
render 64 icon_32x32@2x.png
render 128 icon_128x128.png
render 256 icon_128x128@2x.png
render 256 icon_256x256.png
render 512 icon_256x256@2x.png
render 512 icon_512x512.png
/bin/cp "$MASTER" "$ICONSET/icon_512x512@2x.png"

/usr/bin/iconutil -c icns "$ICONSET" -o "$OUTPUT"
echo "$OUTPUT"
