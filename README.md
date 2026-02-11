# MultiCodex (macOS Menu Bar App)

Native macOS SwiftUI menu bar app for `multicodex`.

## Features

- Menu bar item showing current profile.
- Lists all configured profiles from `multicodex accounts list --json`.
- Shows per-profile usage from `multicodex limits --json` (5h, weekly, source).
- One-click profile switch via `multicodex accounts use <name> --json`.
- Profile and login management in Settings.

## Build and run

Requirements:

- macOS 13+
- Xcode 15+ (or Swift 5.9+ toolchain)
- Node.js available on the machine (the app runs bundled `multicodex` through `node`)
- Bun (used to fetch/build bundled CLI)
- `just` (recommended for local app workflow)

From repo root:

```bash
just doctor
just dev
```

## Bundled CLI source

The app does not rely on a local sibling CLI checkout.

`sync:cli` downloads the latest CLI release source from GitHub (repo default: `mohammadhmn/multicodex`), builds it, and embeds `dist/cli.js` into:

- `Sources/MultiCodexMenu/Resources/multicodex-cli.js`

Optional overrides:

- `CLI_GITHUB_REPO` (default: `mohammadhmn/multicodex`)
- `CLI_VERSION` (`vX.Y.Z` or `X.Y.Z`) to pin a specific CLI tag

Examples:

```bash
CLI_VERSION=v0.2.1 bun run sync:cli
CLI_GITHUB_REPO=your-org/multicodex bun run sync:cli
```

## Common `just` commands

```bash
just list
just doctor
just dev
just dmg
just ci
just clean
just kickoff-release
just release 0.1.0
```

## GitHub release (DMG)

- Workflow: `.github/workflows/release-macos.yml`
- Trigger tag format: `macos-vMAJOR.MINOR.PATCH`
- Release artifact: `build/dist/MultiCodex.dmg`

Create and push a release tag:

```bash
just kickoff-release
# or
just release 0.1.0
```
