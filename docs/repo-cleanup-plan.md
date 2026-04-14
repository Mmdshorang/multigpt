# MultiCodex Repo-Wide Cleanup Plan (DRY/KISS)

## Audit Summary

- Baseline is healthy: `just ci` passes (`52` tests, `0` failures).
- Repo size is moderate (`56` Swift files, about `9,000` LOC total).
- Main cleanup hotspots by size/complexity:
  - `Sources/MultiCodex/Features/Shared/AccountsMenuViewModel.swift`
  - `Sources/MultiCodex/Features/MenuBar/AccountsMenuContentView+Sections.swift`
  - `Sources/MultiCodex/Features/Settings/SettingsContentView+DashboardAccounts.swift`
  - `Sources/MultiCodex/Infrastructure/Codex/Usage/RateLimitsUsageAPI.swift`
  - `Sources/MultiCodex/Infrastructure/Codex/Usage/RateLimitsFetcher.swift`
  - `Sources/MultiCodex/Features/Shared/AccountActionController.swift`
- Clear DRY/KISS opportunities:
  - Dead fallback menu path still present but disabled (`isSafeMenuFallbackEnabled == false`).
  - Repeated `AccountUsage(...)` reconstruction and sort logic in local state updates.
  - Repeated diagnostics/status UI blocks across settings sections.
  - `CodexAccountService` is organized by extension files but still effectively a large mixed-responsibility service.

## Principles

- Preserve behavior by default; do not add net-new product features.
- Prefer explicit/simple code over abstraction for abstraction's sake.
- Delete dead paths first, then consolidate duplicates.
- Keep refactors in atomic batches with passing quality gates.

## Planned Batches

### Batch 1 (Low Risk): Remove dead menu fallback path

Goal: reduce branch complexity in menu rendering.

Changes:
- Delete `safe*` view helpers and the `if isSafeMenuFallbackEnabled` branch.
- Keep only active menu UI path.

Primary files:
- `Sources/MultiCodex/Features/MenuBar/AccountsMenuContentView.swift`
- `Sources/MultiCodex/Features/MenuBar/AccountsMenuContentView+Sections.swift`

Validation:
- `swift build`
- menu open/render smoke test
- `just ci`

### Batch 2 (Low Risk): DRY account list mutations

Goal: remove repetitive mapping/sorting and improve correctness/readability.

Changes:
- Introduce shared helpers for:
  - account mapping/update
  - current-first sort
  - localized mutation operations (`applyCurrent`, `rename`, `remove`, `upsertAuth`)
- Replace duplicated constructors in `AccountsMenuViewModel`.

Primary file:
- `Sources/MultiCodex/Features/Shared/AccountsMenuViewModel.swift`

Validation:
- `swift test --filter AccountsMenuViewModelTests`
- `just ci`

### Batch 3 (Low-Medium Risk): Split oversized UI files

Goal: lower cognitive load and improve maintainability.

Changes:
- Break large settings/account views into focused subcomponents.
- Consolidate repeated diagnostics/status UI blocks.

Primary files:
- `Sources/MultiCodex/Features/Settings/SettingsContentView+DashboardAccounts.swift`
- `Sources/MultiCodex/Features/Settings/SettingsContentView+RuntimeAdvanced.swift`
- `Sources/MultiCodex/Features/MenuBar/MenuAccountQuickRow.swift`

Validation:
- `swift build`
- settings + menubar navigation smoke tests
- `just ci`

### Batch 4 (Medium Risk): Decompose `CodexAccountService` internals

Goal: separate concerns while preserving public behavior.

Changes:
- Keep `CodexAccountServicing` API stable.
- Extract internal collaborators for:
  - account/auth filesystem operations
  - usage transport/parsing
  - runtime command execution

Primary files:
- `Sources/MultiCodex/Infrastructure/Codex/Accounts/CodexAccountService.swift`
- Existing extension modules under `Infrastructure/Codex/**`

Validation:
- `swift test --filter CodexAccountServiceTests`
- full `just ci`

### Batch 5 (Medium Risk): Simplify usage fetch flow

Goal: reduce nested control flow and centralize parsing.

Changes:
- Flatten nested `do/catch` in limits fetching to explicit fallback steps.
- Move parsing helpers into a dedicated parser utility/type.

Primary files:
- `Sources/MultiCodex/Infrastructure/Codex/Usage/RateLimitsFetcher.swift`
- `Sources/MultiCodex/Infrastructure/Codex/Usage/RateLimitsUsageAPI.swift`

Validation:
- usage-related tests
- manual refresh/live refresh checks
- `just ci`

### Batch 6 (Low Risk): Test-suite consolidation

Goal: reduce test duplication and improve readability.

Changes:
- Add shared fixtures/builders for accounts/snapshots/view-model setup.
- Split large tests into thematic suites.

Primary files:
- `Tests/MultiCodexTests/AccountsMenuViewModelTests.swift`
- `Tests/MultiCodexTests/CodexAccountServiceTests.swift`

Validation:
- `swift test`
- `just ci`

### Batch 7 (Low Risk): Consistency + polish pass

Goal: tighten quality and documentation alignment.

Changes:
- Normalize naming/style inconsistencies.
- Remove stale comments/obsolete notes.
- Update README architecture section if structure changes.

Primary files:
- Touched modules + `README.md`

Validation:
- `just ci`
- quick manual UX smoke test

## Execution Order

1. Batch 1
2. Batch 2
3. Batch 3
4. Batch 4
5. Batch 5
6. Batch 6
7. Batch 7

## Quality Gates

For each batch:
- run targeted tests for changed area
- run `just ci` before closing the batch
- perform manual smoke tests for UI/auth flows when relevant

## Risk Notes

- Highest-risk work is auth/runtime/service decomposition (Batches 4-5).
- Keep those changes incremental and verify behavior parity after each slice.
- Avoid combining structural and behavioral changes in the same batch.
