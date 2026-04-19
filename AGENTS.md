# AGENTS.md — MultiCodex

Native macOS menu bar app for managing multiple coding agent accounts (Codex, Pi) with usage tracking and account switching.

## Project Quick Reference

- **Language**: Swift 5.9+
- **Platform**: macOS 13+
- **Build**: SwiftPM + `just` (see `justfile`)
- **Entry**: `Sources/MultiCodex/App/MultiCodexApp.swift`

## Architecture

Single executable target organized by layer:

```
Sources/MultiCodex/
├── App/                    # App lifecycle, scene wiring
├── Core/
│   ├── Accounts/           # Domain models, UI state, alert policy
│   └── Usage/              # Usage/rate-limit models, formatting
├── Infrastructure/
│   ├── Codex/              # CLI integration (runtime, auth, usage)
│   ├── Preferences/        # AppPreferencesStore (UserDefaults wrapper)
│   └── Notifications/      # Auto-switch notifications
└── Features/
    ├── MenuBar/            # Menu bar UI (AccountsMenuContentView, rows)
    ├── Settings/           # Settings window UI
    └── Shared/             # View model, controllers, design tokens
```

## Key Patterns

### View Model Architecture

- **Main view model**: `AccountsMenuViewModel` (`@MainActor`, `ObservableObject`)
- **Controllers**: Lazy-initialized for specific domains:
    - `refreshController` — data refresh loop
    - `accountActions` — login/logout flows
    - `settingsController` — preferences mutations
    - `accountManagement` — CRUD operations

### UI Component Patterns

- Design tokens: `DashboardTokens` (colors, spacing, fonts)
- Reusable buttons: `ActionPillButton` (primary/secondary, icon-only)
- Cards: `SettingsPanelCard`, `AlertActionCard`
- Progress: `DashboardProgressRing`, `DashboardSparkline`

### Account Row Interaction

- `DashboardAccountRow` shows account with inline usage bar
- Selection indicator: circle (selected = filled accent)
- When selected + action available: icon button shows (switch/relogin)
- Chevron toggles expanded state with usage details

## Data Flow

1. `AccountsRefreshController` triggers account/usage fetch
2. `CodexAccountService` (implements `CodexAccountServicing`) runs CLI commands
3. Results merge into `AccountUsage` models
4. View model publishes updates → SwiftUI re-renders
5. Background refresh loop runs every `limitsCacheTTLSeconds`

## Configuration & Storage

- **Config dir**: `MULTICODEX_HOME` (default `~/.config/multicodex`)
- **Schema**: `config.json` with version `2`
- **Auth files**: `~/.codex/auth.json` (per account)
- **Preferences**: `AppPreferencesStore` (UserDefaults)

## Common Tasks

### Build & Run

```bash
just run          # Build debug, kill existing, open app
just check        # Build + test (local verification gate)
just package      # Build versioned release DMG
```

### Adding UI Controls

- Menu bar buttons: Use `ActionPillButton` with `.iconOnly` layout
- Section headers: Use `DashboardSectionHeader`
- State changes: Modify `@Published` in view model → UI auto-updates

### Account Operations

All async account work goes through controllers:

- Switch account: `accountManagement.switchToAccount(named:)`
- Login: `accountManagement.startNewAccountLogin()`
- Relogin: `accountManagement.openLoginInTerminal(for:)`
- Rename/remove: `accountManagement.renameAccount()` / `removeAccount()`

## Testing & Quality

- Swift tests in `Tests/MultiCodexTests/`
- Format: `swiftformat .` (config in `.swiftformat`)
- Lint: `swiftlint` (config in `.swiftlint.yml`)
- Safe build wrapper: `scripts/swift-safe.sh` (handles PCH/cache errors)

## Release

- Tag format: `vMAJOR.MINOR.PATCH`
- Workflow: `.github/workflows/release-macos.yml`
- Command: `just release patch` (or specific version)
- Artifact: `build/dist/MultiCodex.dmg`

## Important Notes

- **Unsigned app**: Users must run `sudo xattr -dr com.apple.quarantine /Applications/MultiCodex.app`
- **Runtime requirement**: `codex` or `pi` CLI must be in PATH (or set custom path in Settings)
- **No JS runtime**: Pure Swift implementation
- **Menu bar only**: Uses `MenuBarExtra`, no dock icon in normal operation
