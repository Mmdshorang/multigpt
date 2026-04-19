# MultiCodex (macOS Menu Bar App)

Native macOS SwiftUI menu bar app for managing multiple coding agent accounts/profiles.

## What It Does

- Shows 5h and weekly usage in a compact menu bar view for agents that expose usage.
- Lets you switch accounts/profiles and re-login when an account needs auth.
- Opens browser-based `codex login` flows through Terminal.
- Provides account/profile operations in Settings: use, rename, remove, import auth, status check, and runtime selection.
- Uses a fully native Swift runtime (no bundled JavaScript CLI runtime).

## Architecture

The app stays in a single SwiftPM executable target and is organized into clear layers:

- `Sources/MultiCodex/App`
  - App lifecycle and top-level scene wiring.
- `Sources/MultiCodex/Core/Accounts`
  - Account-focused domain payloads, UI state models, merge policy, alert prioritization.
- `Sources/MultiCodex/Core/Usage`
  - Usage/rate-limit models and formatting helpers.
- `Sources/MultiCodex/Infrastructure/Codex`
  - Codex-specific auth/runtime/usage implementations.
- `Sources/MultiCodex/Infrastructure/Preferences`
  - App preference persistence.
- `Sources/MultiCodex/Features/MenuBar`
  - Menu bar content and status UI.
- `Sources/MultiCodex/Features/Settings`
  - Settings screens and account management UI.
- `Sources/MultiCodex/Features/Shared`
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
- `codex` CLI available in `PATH` (or set a custom path in Settings > Runtime)
- `just` (recommended)

## Development

Quickstart:

```bash
just doctor
just run
```

Verification gate:

```bash
just check
```

Swift-only equivalents (same safe behavior used by `just`):

```bash
bash scripts/swift-safe.sh swift build -c debug
bash scripts/swift-safe.sh swift test --parallel
```

Useful commands:

```bash
just help
just run
just test
just package
just check
just icons
just clean
just release patch
just release 0.2.0
```

## Release

- Workflow: `.github/workflows/release-macos.yml`
- Tag format: `vMAJOR.MINOR.PATCH`
- Local `just package` artifacts:
  - Versioned DMG: `build/dist/MultiCodex-<version>.dmg`
  - Latest symlink: `build/dist/MultiCodex.dmg`
- `scripts/release.sh` enforces:
  - current branch is `main`
  - clean working tree
  - tag must not already exist locally or on `origin`

Version source for `just package`:

- Uses `git describe --tags --always --dirty` (leading `v` removed from tags).
- You can override manually: `MULTICODEX_BUILD_VERSION=1.2.3 just package`

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
- Swift build fails with module/PCH cache path errors after moving clones:
  - Normal build flows auto-recover and retry once.
  - For manual recovery, run `just clean` and build again.
