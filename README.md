# Codex Usage

A standalone macOS 13+ SwiftUI app extracted from Dots. It provides:

- current Codex rolling-window quota and cycle token usage;
- recent local Codex session and daily usage summaries;
- the movable desktop usage widget and palette controls;
- Reset Radar community signals and optional notifications;
- an optional local Work Trail using approximate Mac location.

The authoritative app icon source is the layered Icon Composer document at
`Resources/AppIcon/CodexUsage.icon`. Packaging compiles it with Xcode's asset
compiler into `Assets.car` and `CodexUsage.icns`; the older PNG/ICNS files in
`Resources/AppIcon/` are retained only as visual history and are not active.
Regenerate them with `scripts/generate_app_icon.sh`; normal app packaging does
this automatically.

The normal refresh path reads the newest Codex session JSONL under
`~/.codex/sessions` or `~/.codex/archived_sessions`, then asks the locally
installed `codex app-server` for account usage and rate-limit status. It does
not read `~/.codex/auth.json` or send a synthetic quota probe.

## Build and test

```sh
swift build
swift test
```

## Build and launch a real app bundle

```sh
script/build_and_run.sh
script/build_and_run.sh verify
```

The bundle is generated at `dist/Codex Usage.app` with bundle identifier
`app.codexusage.local`. The packaging script uses an available Apple
Development or Developer ID identity when possible and otherwise falls back to
ad-hoc signing.
