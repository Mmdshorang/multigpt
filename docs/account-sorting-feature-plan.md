# Account Sorting Feature Plan

> **Status: ✅ Fully Implemented** (merged in PR #8, commit `37c439d`)
>
> This document is retained as historical reference. All items below were shipped.

## Objective

Add flexible sorting for account lists in MultiCodex across both the menu bar accounts list and the Settings > Accounts list.

The feature must support:

- Sorting by multiple criteria (`Used`, `Remaining`, `Name`)
- Window choice for usage-based sorts (`5h`, `Weekly`)
- Sort direction (`Ascending`, `Descending`)
- Current account always pinned at the top
- Accounts with missing usage data always at the bottom
- Persisted preferences (sticky across app restarts)
- Quick sort controls directly in the menu bar accounts section

---

## Final Product Behavior

### Surface-Specific Note (Implemented)

- **Menu bar accounts list**: current account is handled separately (shown in the dedicated "current account" card) and is excluded from sortable account rows.
- **Settings > Accounts list**: current account is included in the list and sorted with the same selected sort options as all other accounts (not pinned).

### Core Behavior Rules

1. Menu and Settings share one sort configuration source (criterion/window/direction).
2. Menu and Settings may render the current account differently by surface (see note above), but both use the same underlying sort policy.
3. If a sort value is missing for an account (for example no usage metric yet), that account is always placed at the bottom of the non-current list.
4. If two accounts tie on primary sort key, tie-break by account name (case-insensitive ascending) for deterministic order.

### Default Sort

- Default to usage-based sorting:
    - Criterion: `Used`
    - Window: `5h`
    - Direction: `Descending`

This keeps likely high-usage accounts visible near the top by default, while still keeping the current account pinned first.

---

## Architecture Decisions

### 1) Single Source of Truth for Sort State

Sort state will live in `AccountsMenuViewModel` as published properties and be persisted via `AppPreferencesStore`.

Why:

- All UI surfaces already consume the view model.
- Prevents divergent sorting behavior between Menu and Settings.
- Simplifies testing of sorting logic in one place.

### 2) Sorting Policy Owned by ViewModel

`AccountUsageMergeService` should not impose UI-level ordering. Its job is merging account + limits payloads, not view presentation policy.

Why:

- Avoids double-sorting and inconsistent ordering during refresh/local mutations.
- Makes sort updates immediate when the user changes options.

### 3) Comparator-Based Sort with Deterministic Tie-Breakers

Introduce a dedicated comparator path in the view model that applies all feature rules in one place.

Why:

- Easier to reason about than ad-hoc sorts.
- Easier to unit test and extend later (e.g., future criterion like `Last Used`).

---

## Data Model and Settings Additions

## New UI State Enums

File: `Sources/MultiCodex/Core/Accounts/AccountUIStateModels.swift`

Add:

- `AccountSortCriterion: String, CaseIterable, Identifiable`
    - `.used`
    - `.remaining`
    - `.name`
- `AccountSortWindow: String, CaseIterable, Identifiable`
    - `.fiveHour`
    - `.weekly`
- `SortDirection: String, CaseIterable, Identifiable`
    - `.ascending`
    - `.descending`

Each should provide display text for pickers (for example `title`).

## Persisted Preferences

File: `Sources/MultiCodex/Infrastructure/Preferences/AppPreferencesStore.swift`

Add persisted properties:

- `accountSortCriterion`
- `accountSortWindow`
- `accountSortDirection`

Add keys in `AppPreferencesStore.Keys`:

- `multicodexMenu.accountSortCriterion`
- `multicodexMenu.accountSortWindow`
- `multicodexMenu.accountSortDirection`

Fallback defaults for migration-safe behavior:

- Criterion default: `.used`
- Window default: `.fiveHour`
- Direction default: `.descending`

---

## ViewModel Changes

File: `Sources/MultiCodex/Features/Shared/AccountsMenuViewModel.swift`

## New State

Add:

- `@Published var accountSortCriterion: AccountSortCriterion`
- `@Published var accountSortWindow: AccountSortWindow`
- `@Published var accountSortDirection: SortDirection`

Initialize from preferences in `init`.

## New Mutations

Add methods:

- `setAccountSortCriterion(_:)`
- `setAccountSortWindow(_:)`
- `setAccountSortDirection(_:)`

Each method should:

1. Update in-memory value
2. Persist to preferences
3. Reapply sorting immediately (`resortAccounts()`)

## Central Sorting API

Replace `sortedCurrentFirst(_:)` with a generalized sort path:

- `private func sortedAccounts(_ accounts: [AccountUsage]) -> [AccountUsage]`
- `private func sortValue(for account: AccountUsage) -> Double?`
- `private func resortAccounts()`

`updateAccounts(_:)` should always call `sortedAccounts`.

Pseudo-flow:

1. Partition account list:
    - `currentAccounts` (should normally be 0 or 1)
    - `otherAccounts`
2. Sort `otherAccounts` by comparator:
    - Missing sort value last
    - Apply criterion/window/direction
    - Tie-break by name
3. Return `currentAccounts + sortedOthers`

### Sort Value Mapping

- `criterion == .name`: sort directly by name (window ignored)
- `criterion == .used`:
    - window `.fiveHour` => `usage.fiveHour.usedPercent`
    - window `.weekly` => `usage.weekly.usedPercent`
- `criterion == .remaining`:
    - remaining = `100 - usedPercent`
    - same window selection applies

Missing metric handling:

- If `usedPercent == nil`, treat sort value as missing -> always bottom.

### Name Sorting

For `name` criterion:

- Compare names case-insensitively.
- Apply direction by inverting comparison for descending.

---

## Controller and Binding Wiring

## Settings Controller

File: `Sources/MultiCodex/Features/Shared/AccountsSettingsController.swift`

Add passthrough setters:

- `setAccountSortCriterion(_:)`
- `setAccountSortWindow(_:)`
- `setAccountSortDirection(_:)`

Mirror existing style used for menu density / usage bar style:

- Guard if unchanged
- Update view model + preferences

## Settings Bindings

File: `Sources/MultiCodex/Features/Settings/SettingsContentView+Bindings.swift`

Add bindings:

- `accountSortCriterionBinding`
- `accountSortWindowBinding`
- `accountSortDirectionBinding`

---

## UI Changes

## Settings UI (Full Controls)

File: `Sources/MultiCodex/Features/Settings/SettingsContentView+General.swift`

Add an `Accounts sorting` row in the Appearance card with:

1. Criterion segmented picker (`Name`, `Used`, `Remaining`)
2. Window segmented picker (`5h`, `Weekly`) shown only when criterion is `Used` or `Remaining`
3. Direction segmented picker (`Asc`, `Desc`)

Design notes:

- Reuse `SettingsSegmentedPicker`.
- Keep widths consistent with existing controls.
- Add short helper text explaining:
    - current account is pinned
    - missing usage is pushed to bottom

## Menu Bar Quick Sort

File: `Sources/MultiCodex/Features/MenuBar/AccountsMenuContentView+Sections.swift`

Add a compact quick-sort control in the accounts section header.

Recommended implementation:

- Use `Menu` anchored in header (icon/button style consistent with `ActionPillButton`)
- Include:
    - Criterion submenu or grouped actions
    - Window options (only meaningful for usage criteria)
    - Direction toggle

Example quick labels:

- `Used (5h) ↓`
- `Used (weekly) ↑`
- `Remaining (5h) ↓`
- `Name A→Z`

Behavior:

- Any quick selection updates shared view-model sort state.
- Settings controls reflect the same value automatically.

---

## Data Flow Updates During Refresh

## Merge Service

File: `Sources/MultiCodex/Core/Accounts/AccountUsageMergeService.swift`

Adjust to avoid final UI sorting policy. It should return merged accounts with stable data but no presentation-specific sort assumptions.

## Refresh Controller

File: `Sources/MultiCodex/Features/Shared/AccountsRefreshController.swift`

After merge, ensure accounts are routed through view-model sorting API (for example a dedicated method instead of direct assignment to `viewModel.accounts`).

Goal:

- Fresh payloads still honor user sort preferences immediately.

---

## Step-by-Step Implementation Guide

1. Add enums in `AccountUIStateModels.swift`.
2. Add new preferences properties and keys in `AppPreferencesStore.swift`.
3. Extend view model state/init in `AccountsMenuViewModel.swift`.
4. Implement generalized sorting comparator + helper methods in `AccountsMenuViewModel.swift`.
5. Update existing local mutation paths to use the generalized sorter (`updateAccounts`, etc.).
6. Refactor merge/refresh path to avoid sorting conflicts (`AccountUsageMergeService`, `AccountsRefreshController`).
7. Add setters in `AccountsSettingsController.swift`.
8. Add SwiftUI bindings in `SettingsContentView+Bindings.swift`.
9. Add full sorting controls to `SettingsContentView+General.swift`.
10. Add quick sort menu/button to `AccountsMenuContentView+Sections.swift`.
11. Ensure Settings Accounts list uses the same sorted source (`SettingsContentView+Accounts.swift`).
12. Add/adjust tests.
13. Run formatting/lint/tests.
14. Manual smoke-test in app UI.

---

## Test Plan

## Unit Tests

File: `Tests/MultiCodexTests/AccountsMenuViewModelTests.swift`

Add tests for:

1. Default sort values on fresh preferences (`used`, `5h`, `descending`)
2. Current account pinned first under all sort criteria
3. Used + 5h ascending
4. Used + 5h descending
5. Used + weekly ascending/descending
6. Remaining + 5h ascending/descending
7. Remaining + weekly ascending/descending
8. Name ascending/descending
9. Missing usage always bottom even when descending
10. Tie-break by name (deterministic)
11. Sort changes are immediately reflected in menu rows and settings list source

File: `Tests/MultiCodexTests/AppPreferencesStoreTests.swift`

Add tests for:

1. Preference persistence round-trip for criterion/window/direction
2. Fallback defaults when keys are missing
3. Invalid raw values fallback to defaults

## Regression Tests

Confirm existing tests around:

- switch account
- rename account
- remove account
- import auth
- refresh flows

still pass and maintain expected ordering constraints with current pinned top.

---

## Manual QA Checklist

1. Launch app with existing preferences (no sort keys) and verify default is `Used + 5h + Desc`.
2. Open Settings > General and change sort criterion/window/direction; verify menu updates immediately.
3. Use quick sort in menu bar; verify Settings controls reflect the change.
4. Verify current account remains first no matter selected sort option.
5. Simulate accounts with missing usage and verify they stay at bottom.
6. Verify show-all/collapse-all behaviors still work after resorting.
7. Restart app and confirm sort preferences persist.

---

## Acceptance Criteria

- Sorting controls exist in both Settings and menu-bar accounts header.
- Both list surfaces show the same ordering at all times.
- Default sort is usage-based (`Used + 5h + Descending`).
- Current account is always pinned first.
- Missing usage metrics always appear at bottom.
- Preferences persist across relaunch.
- Unit tests cover all sorting dimensions and pass.

---

## Implementation Notes / Risks

1. Risk: conflicting sort behavior from merge service and view model.
    - Mitigation: keep final presentation sort only in view model.

2. Risk: confusing UX if quick sort shows window while criterion is name.
    - Mitigation: hide/disable window control for `Name`.

3. Risk: unstable ordering causing UI jumpiness.
    - Mitigation: deterministic tie-breakers (name), stable comparator path.

4. Risk: edge cases during live refresh.
    - Mitigation: ensure all account assignment paths route through `updateAccounts`.

---

## Suggested Execution Order (Low-Risk)

1. Data model + preferences + tests for defaults
2. ViewModel sorting logic + tests
3. Refresh/merge path updates
4. Settings UI controls
5. Menu quick sort UI
6. Full test + manual QA pass
