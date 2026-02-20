# MultiCodex (macOS Menu Bar App)

Native macOS SwiftUI menu bar app for managing multiple Codex accounts.

## What It Does

- Shows 5h and weekly usage in a compact menu bar view.
- Lets you switch accounts and re-login when an account needs auth.
- Opens browser-based `codex login` flows through Terminal.
- Provides account operations in Settings: use, rename, remove, import auth, and status check.
- Uses a fully native Swift runtime (no bundled JavaScript CLI runtime).

## Architecture

The app stays in a single SwiftPM executable target and is organized into clear layers:

- `Sources/MultiCodexMenu/App`
  - App lifecycle and top-level scene wiring.
- `Sources/MultiCodexMenu/Core/Accounts`
  - Account-focused domain payloads, UI state models, merge policy, alert prioritization.
- `Sources/MultiCodexMenu/Core/Usage`
  - Usage/rate-limit models and formatting helpers.
- `Sources/MultiCodexMenu/Infrastructure/Accounts`
  - Account config/auth persistence, preferences, and account service facade.
- `Sources/MultiCodexMenu/Infrastructure/Runtime`
  - Codex runtime resolution and process execution.
- `Sources/MultiCodexMenu/Infrastructure/Usage`
  - Usage API request builders, RPC helpers, and limits cache codecs.
- `Sources/MultiCodexMenu/Features/MenuBar`
  - Menu bar content and status UI.
- `Sources/MultiCodexMenu/Features/Settings`
  - Settings screens and account management UI.
- `Sources/MultiCodexMenu/Features/Shared`
  - Shared view model and reusable UI presentation components.

## Simplification Notes

This cleanup intentionally favors simpler internals over legacy compatibility branches:

- Storage paths remain unchanged:
  - `MULTICODEX_HOME` (default `~/.config/multicodex`)
  - `~/.codex/auth.json`
- `config.json` continues to use schema version `2`.
- Legacy schema version `1` config parsing and legacy `UserDefaults` fallback keys were removed.
- Build/dev workflow is Swift + `just` only (no npm layer).

## Requirements

- macOS 13+
- Xcode 15+ (or Swift 5.9+ toolchain)
- `codex` CLI available in `PATH` (or set custom path in app Settings)
- `just` (recommended)

## Development

```bash
just doctor
just dev
```

Swift-only equivalents:

```bash
swift build -c debug
swift test --parallel
```

Useful commands:

```bash
just list
just dev
just ci
just dmg
just icons
just clean
just release patch
just release 0.2.0
just kickoff-release
```

## Release

- Workflow: `.github/workflows/release-macos.yml`
- Tag format: `vMAJOR.MINOR.PATCH`
- Artifact: `build/dist/MultiCodex.dmg`

Important (unsigned app): run after install.

```bash
sudo xattr -dr com.apple.quarantine /Applications/MultiCodex.app
```

To create a release tag and trigger GitHub Actions:

```bash
just release patch
# or
just release v0.2.0
```

## Troubleshooting

- `codex` not found: install `codex` or set the runtime path in Settings > Runtime.
- Account says auth is needed: use `Re-login` on that account.
- Swift build fails with module/PCH cache path errors after moving clones: run `just clean` and build again.
