# AGENTS.md — MultiCodex

Native macOS menu bar app for managing multiple Codex accounts with usage tracking, account switching, and auto-switching.

## Project Quick Reference

- **Language**: Swift 5.9+
- **Platform**: macOS 13+
- **Build**: SwiftPM + `just` (see `justfile`)
- **Entry**: `Sources/MultiCodex/App/MultiCodexApp.swift`
- **Latest release**: v0.4.0
- **Lines of code**: ~8,200 (source) + ~2,400 (tests)

## Architecture

Single executable target organized by layer:

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

## Key Patterns

### View Model Architecture

- **Main view model**: `AccountsMenuViewModel` (`@MainActor`, `ObservableObject`)
- **Controllers** (lazy-initialized, domain-scoped):
  - `refreshController` — data refresh loop + runtime probe
  - `accountActions` — login/logout flows + feedback
  - `settingsController` — preferences mutations (sort, density, paths, etc.)
  - `accountManagement` — CRUD operations (switch, rename, remove, import auth)

### UI Component Patterns

- **Design tokens**: `DashboardTokens` (colors, spacing, fonts)
- **Reusable components**:
  - `ActionPillButton` — primary/secondary/icon-only pill buttons
  - `SettingsPanelCard` — card container with padding/ styling
  - `SettingsSegmentedPicker` — labeled segmented controls
  - `SettingsToggle` — toggle row for boolean prefs
  - `SettingsTextField` — styled text input
  - `SettingsDestructiveButton` — red destructive action button
  - `AlertActionCard` — alert banner with action button
  - `DashboardProgressRing` — circular progress indicator
  - `DashboardSparkline` — inline sparkline chart
  - `DashboardStatCard` — labeled stat display
  - `CardBackground` / `.cardStyle()` modifier — consistent card styling

### Account Row Interaction

- `DashboardAccountRow` shows account with inline micro usage bar
- Checkbox button (left side): shows switch/relogin/current depending on state
- Row tap: toggles expanded state showing 5h + weekly bar details
- Expand/collapse all button in section header
- Show all / show less for overflow accounts beyond density limit

### Sort System

Shared sort configuration between menu bar and settings:

- `AccountSortCriterion` — `.used`, `.remaining`, `.name`
- `AccountSortWindow` — `.fiveHour`, `.weekly` (hidden for name criterion)
- `SortDirection` — `.ascending`, `.descending`
- Current account pinned first in menu; included in sort in settings
- Missing usage data → always bottom; tie-break by name ascending
- Defaults: Used + 5h + Descending
- Menu bar: compact pill menus for quick sort changes
- Settings > Accounts: full segmented pickers

### Auto-Switching

Three strategies via `AccountSwitchingStrategy`:

- `.manual` — no automatic switching
- `.failover` — switch when current account needs login, errors, or near limit
- `.expiryAware` — prefer account with most expiring-unused headroom (sticky bonus for current)

`AccountSwitchRecommendationService` computes recommendations.
`AutoSwitchNotificationCenter` delivers macOS native notifications.

## Data Flow

1. `AccountsRefreshController` triggers account/usage fetch on timer + app activation
2. `CodexAccountService` (implements `CodexAccountServicing`) runs CLI commands
3. Results merge into `AccountUsage` models via `AccountUsageMergeService`
4. View model applies sort policy via `updateAccounts(_:)` → `sortedAccounts(_:)`
5. View model publishes updates → SwiftUI re-renders
6. Background refresh loop runs every `limitsCacheTTLSeconds`
7. If auto-switching is non-manual, live refresh is preferred and recommendations checked

## Configuration & Storage

| Store | Location | Contents |
|-------|----------|----------|
| Config dir | `MULTICODEX_HOME` (default `~/.config/multicodex`) | `config.json` (schema v2) |
| Auth files | `~/.codex/auth.json` | Per-account auth tokens |
| Preferences | `AppPreferencesStore` (UserDefaults) | Sort, density, strategy, paths, etc. |

### Preference Keys

All prefixed with `multicodexMenu.`:
`customCodexPath`, `resetDisplayMode`, `selectedSettingsSection`, `selectedSettingsAccountName`, `menuDensity`, `usageBarStyle`, `accountSortCriterion`, `accountSortWindow`, `accountSortDirection`, `accountSwitchingStrategy`, `autoSwitchNotificationsEnabled`, `limitsCacheTTLSeconds`

## Common Tasks

### Build & Run

```bash
just run          # Build debug, kill existing, open app
just check        # Doctor + build + test (verification gate)
just package      # Build versioned release DMG
```

### Adding UI Controls

- Menu bar buttons: Use `ActionPillButton` with `.iconOnly` layout
- Settings controls: Use `SettingsSegmentedPicker`, `SettingsToggle`, `SettingsTextField`
- Section headers: Use `DashboardSectionHeader`
- Cards: Use `SettingsPanelCard` or `.cardStyle()` modifier
- State changes: Modify `@Published` in view model → UI auto-updates

### Account Operations

All async account work goes through controllers:

- Switch account: `accountManagement.switchToAccount(named:)`
- Login: `accountManagement.startNewAccountLogin()`
- Relogin: `accountManagement.openLoginInTerminal(for:)`
- Rename/remove: `accountManagement.renameAccount()` / `removeAccount()`
- Import auth: `accountManagement.importCurrentAuth(into:)`
- Check status: `accountManagement.checkLoginStatus(for:)`

### Adding Sort Criteria

1. Add case to `AccountSortCriterion` in `AccountUIStateModels.swift`
2. Add key + property to `AppPreferencesStore`
3. Add `@Published` + setter to `AccountsMenuViewModel`
4. Add sorting logic in `compareAccounts(_:_:)` and `sortValue(for:)`
5. Add passthrough in `AccountsSettingsController`
6. Add binding in `SettingsContentView+Bindings.swift`
7. Add UI controls in menu bar (`AccountsMenuContentView+Sections`) and settings

### Adding Settings Sections

1. Add case to `SettingsSection` enum (must be `String, CaseIterable, Identifiable`)
2. Add `title`, `symbol` properties
3. Add page view in `SettingsContentView` extension
4. Add `case` in `detailContent` switch

## Testing & Quality

- Swift tests in `Tests/MultiCodexTests/` (~2,400 lines):
  - `AccountsMenuViewModelTests` — view model + sort behavior
  - `AccountRowStateTests` — row state derivation
  - `AccountUsageMergeServiceTests` — account/usage merge
  - `AppPreferencesStoreTests` — preference persistence
  - `CodexAccountServiceTests` — service layer
  - `MenuAlertPolicyTests` — alert prioritization
  - `UsageFormatterTests` — formatting helpers
- Format: `swiftformat .` (config in `.swiftformat`)
- Lint: `swiftlint` (config in `.swiftlint.yml`)
- Safe build wrapper: `scripts/swift-safe.sh` (handles PCH/cache errors)

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/bundle-app.sh` | Build app bundle from SwiftPM output |
| `scripts/generate-app-icon.sh` | Convert .appiconset → .icns |
| `scripts/release.sh` | Tag validation + push release tag |
| `scripts/resolve-build-version.sh` | Derive version from git describe |
| `scripts/swift-safe.sh` | Build wrapper with PCH/cache error recovery |

## Release

- Tag format: `vMAJOR.MINOR.PATCH`
- Workflow: `.github/workflows/release-macos.yml`
- Command: `just release patch` (or specific version)
- Artifact: `build/dist/MultiCodex-<version>.dmg` + `MultiCodex.dmg` symlink
- Release notes: `.github/release-notes-macos.md`

## Important Notes

- **Unsigned app**: Users must run `sudo xattr -dr com.apple.quarantine /Applications/MultiCodex.app`
- **Runtime requirement**: `codex` CLI must be in PATH (or set custom path in Settings > System)
- **No JS runtime**: Pure Swift implementation
- **Menu bar only**: Uses `MenuBarExtra`, no dock icon in normal operation
- **Keyboard shortcuts**: ⌘R (refresh), ⌘, (settings)
