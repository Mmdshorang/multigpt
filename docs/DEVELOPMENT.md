# Development Guide

Technical reference for contributing to MultiCodex. For a project overview, see the [README](../README.md).

> **Also see**: [AGENTS.md](../AGENTS.md) for the full contributor cheat-sheet (architecture, patterns, common tasks).

---

## Requirements

| Tool | Version | Notes |
|------|---------|-------|
| macOS | 13+ | Runtime & build |
| Xcode | 15+ | Or Swift 5.9+ toolchain |
| `codex` CLI | latest | Must be in `PATH`, or set custom path in Settings |
| `just` | any | Task runner — recommended, not required |

## Quick Start

```bash
# Verify your environment
just doctor

# Build and launch the debug app
just run

# Run the full verification gate (doctor + build + test)
just check
```

## Useful Commands

```bash
just help         # List all commands
just build        # Build app bundle (debug or release)
just test         # Run Swift tests
just package      # Build versioned release DMG
just icons        # Regenerate app icon (.icns)
just clean        # Clean all build artifacts
```

## Architecture

Single SwiftPM executable target (`MultiCodex`) organized by layer:

```
Sources/MultiCodex/
├── App/                        # App lifecycle, scene wiring, delegate
├── Core/
│   ├── Accounts/               # Domain models, UI state enums, merge policy,
│   │                           # alert policy, switching strategy, recommendation engine
│   └── Usage/                  # Usage/rate-limit models, formatting helpers
├── Infrastructure/
│   ├── Codex/
│   │   ├── Accounts/           # Account CRUD, auth coordination, config store,
│   │   │                       # identity resolution, account service protocol
│   │   ├── Auth/               # Login session coordination
│   │   ├── Runtime/            # CLI command runner, runtime resolution,
│   │   │                       # process output, shell path resolution
│   │   └── Usage/              # Rate limits fetcher, RPC client, usage API,
│   │                           # limits cache store
│   ├── Notifications/          # Auto-switch notification center
│   └── Preferences/            # AppPreferencesStore (UserDefaults wrapper)
└── Features/
    ├── MenuBar/                # Menu bar content view, account rows, status labels
    ├── Settings/               # Settings window (General, Accounts, System, About)
    └── Shared/                 # View model, controllers, design tokens,
                                # reusable UI components
```

## Configuration & Storage

| Store | Location | Contents |
|-------|----------|----------|
| Config directory | `MULTICODEX_HOME` (default `~/.config/multicodex`) | `config.json` (schema v2) |
| Auth files | `~/.codex/auth.json` | Per-account auth tokens |
| Preferences | `AppPreferencesStore` (UserDefaults) | Sort, density, strategy, paths, etc. |

All preference keys are prefixed with `multicodexMenu.`. See [AGENTS.md](../AGENTS.md) for the full list.

## Data Flow

1. `AccountsRefreshController` triggers account/usage fetch on timer + app activation
2. `CodexAccountService` (implements `CodexAccountServicing`) runs CLI commands
3. Results merge into `AccountUsage` models via `AccountUsageMergeService`
4. View model applies sort policy via `updateAccounts(_:)` → `sortedAccounts(_:)`
5. `@Published` updates → SwiftUI re-renders
6. Background refresh loop runs every `limitsCacheTTLSeconds`
7. If auto-switching is non-manual, live refresh is preferred and recommendations are checked

## Auto-Switching Strategies

| Strategy | Behavior |
|----------|----------|
| **Manual** | Never switch automatically. |
| **Failover** | Switch when current account needs login, errors, or is near its rate limit. |
| **Expiry-Aware** | Prefer accounts whose 5h or weekly headroom is most likely to expire unused. Includes a sticky bonus for the current account. |

`AccountSwitchRecommendationService` computes recommendations.  
`AutoSwitchNotificationCenter` delivers macOS native notifications.

## Account Sorting

Shared sort configuration between menu bar and settings:

| Setting | Options | Default |
|---------|---------|---------|
| **Criterion** | Used, Remaining, Name | Used |
| **Window** | 5h, Weekly (hidden for Name) | 5h |
| **Direction** | Ascending, Descending | Descending |

**Behavior rules:**
- Current account is pinned first in the menu bar; included in sort order in settings
- Accounts without usage metrics are always pushed to the bottom
- Ties are broken by case-insensitive account name ascending

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/bundle-app.sh` | Build app bundle from SwiftPM output |
| `scripts/generate-app-icon.sh` | Convert `.appiconset` → `.icns` |
| `scripts/release.sh` | Tag validation + push release tag |
| `scripts/resolve-build-version.sh` | Derive version from `git describe` |
| `scripts/swift-safe.sh` | Build wrapper with PCH/cache error recovery |

## Testing & Quality

Tests live in `Tests/MultiCodexTests/` (~2,400 lines):

| File | Coverage |
|------|----------|
| `AccountsMenuViewModelTests` | View model + sort behavior |
| `AccountRowStateTests` | Row state derivation |
| `AccountUsageMergeServiceTests` | Account/usage merge |
| `AppPreferencesStoreTests` | Preference persistence |
| `CodexAccountServiceTests` | Service layer |
| `MenuAlertPolicyTests` | Alert prioritization |
| `UsageFormatterTests` | Formatting helpers |

**Tooling:**
- Format: `swiftformat .` (config in `.swiftformat`)
- Lint: `swiftlint` (config in `.swiftlint.yml`)
- Safe build: `scripts/swift-safe.sh` (handles PCH/cache errors)

## Release Process

1. Tag format: `vMAJOR.MINOR.PATCH`
2. Workflow: `.github/workflows/release-macos.yml`
3. Local command:

```bash
just release patch    # or: just release v0.5.0
```

`scripts/release.sh` enforces: branch is `main`, clean working tree, tag doesn't exist locally or on `origin`.

**Artifacts:**
- Versioned DMG: `build/dist/MultiCodex-<version>.dmg`
- Latest symlink: `build/dist/MultiCodex.dmg`

**Version source:** `git describe --tags --always --dirty` (leading `v` removed). Override with `MULTICODEX_BUILD_VERSION=1.2.3 just package`.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `codex` not found | Install `codex` or set the path in Settings → System → Runtime |
| Account needs auth | Use "Re-login" to open a Terminal login flow |
| Build fails with PCH/cache errors | Run `just clean` and rebuild |
| Notifications not showing | Check System Settings → Notifications → MultiCodex |
