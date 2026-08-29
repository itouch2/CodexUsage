#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/Codex Usage.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/CodexUsage"
BUNDLE_ID="app.codexusage.local"

stop_existing_app() {
  /usr/bin/osascript -e \
    "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  /usr/bin/pkill -x CodexUsage >/dev/null 2>&1 || true
  sleep 0.3
}

package_bundle() {
  "$ROOT_DIR/scripts/package_app.sh" >/dev/null
  /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
}

case "$MODE" in
  run)
    stop_existing_app
    package_bundle
    /usr/bin/open "$APP_BUNDLE"
    ;;
  verify|--verify)
    stop_existing_app
    package_bundle
    /usr/bin/open "$APP_BUNDLE"
    sleep 1
    /usr/bin/pgrep -x CodexUsage >/dev/null
    ;;
  debug|--debug)
    stop_existing_app
    package_bundle
    /usr/bin/lldb -- "$APP_BINARY"
    ;;
  logs|--logs)
    stop_existing_app
    package_bundle
    /usr/bin/open "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact \
      --predicate 'process == "CodexUsage"'
    ;;
  *)
    echo "usage: $0 [run|verify|debug|logs]" >&2
    exit 2
    ;;
esac
