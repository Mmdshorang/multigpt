# MultiCodex (macOS Menu Bar App)

Native macOS SwiftUI menu bar app for managing multiple Codex profiles.

## What It Does

- Shows 5h and weekly usage in a compact menu bar view.
- Lets you switch profiles and re-login when a profile needs auth.
- Opens browser-based `codex login` flows through Terminal.
- Provides profile operations in Settings: use, rename, remove, import auth, and status check.
- Uses a fully native Swift runtime (no bundled JavaScript CLI runtime).

## Storage Layout

MultiCodex follows the same storage layout as the `multicodex` CLI:

- `~/.config/multicodex` (or `MULTICODEX_HOME`)
- `~/.codex/auth.json`

Note: the temporary test config/sandbox flow is debug-only.

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

- `codex` not found: install `codex` or set the runtime path in Settings > Codex Runtime.
- Profile says auth is needed: use `Re-login` on that profile.
- Swift build fails with module/PCH cache path errors after moving clones: run `just clean` and build again.
