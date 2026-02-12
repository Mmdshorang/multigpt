# MultiCodex (macOS Menu Bar App)

Native macOS SwiftUI menu bar app for managing multiple Codex logins.

## Highlights

- Fully native Swift core (no bundled JavaScript CLI runtime).
- Uses the same storage layout as `multicodex` CLI:
  - `~/.config/multicodex` (or `MULTICODEX_HOME`)
  - `~/.codex/auth.json`
- Profile management: add/remove/rename/use/import/status.
- Login flows directly in Terminal with browser-based `codex login`.
- Login-first onboarding for new profiles with auto-generated names (rename later).
- Optional temporary sandbox mode for safe setup testing.
- Menubar usage view with 5h + weekly limits and profile switching.

## Requirements

- macOS 13+
- Xcode 15+ (or Swift 5.9+ toolchain)
- `codex` available in `PATH`
- `just` (recommended)

## Development

```bash
just doctor
just dev
```

Common commands:

```bash
just list
just dev
just dmg
just ci
just icons
just release 0.1.0
just kickoff-release
```

## Release

- Workflow: `.github/workflows/release-macos.yml`
- Tag format: `vMAJOR.MINOR.PATCH`
- Artifact: `build/dist/MultiCodex.dmg`
