# Final Cleanup DRY PASS Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Do a final codebase cleanup pass that reduces duplication, consolidates refresh/action state, removes stale abstractions, and preserves all behavior with tests.

**Architecture:** Keep behavior stable and refactor in small slices behind existing tests. Consolidate duplicated UI/action/refresh state into explicit helpers, then tighten service APIs and docs after verification. PASS means Performance, Architecture, Stability, and Simplicity: each task must improve one of these without regressing the others.

**Tech Stack:** Swift 5.9+, SwiftUI, Swift concurrency, SwiftPM tests, `just check`.

---

## Scope

This plan is a final polish pass after the branch stability work. It should not add user-facing features. It should remove accidental complexity, make refresh/switch/login behavior easier to reason about, and leave future agents fewer footguns.

## PASS Checklist

- Performance: no unnecessary live refresh, no duplicate slow work, no late stale refresh application.
- Architecture: one clear refresh entrypoint, one clear account-action busy model, one clear auth mutation boundary.
- Stability: cancellation, generation, and manual-auto-switch semantics covered by regression tests.
- Simplicity: delete compatibility shims, duplicate helpers, stale docs, and confusing names after migration.

## File Map

- Modify `Sources/MultiCodex/Features/Shared/AccountsMenuViewModel.swift`
  - Consolidate busy-state computed properties.
  - Keep refresh lifecycle fields private where possible.
- Modify `Sources/MultiCodex/Features/Shared/AccountsRefreshController.swift`
  - Make `triggerRefresh` the only app refresh entrypoint.
  - Extract generation/stale guard helpers.
  - Centralize partial result application.
- Modify `Sources/MultiCodex/Features/Shared/AccountActionController.swift`
  - Remove duplicate refresh scheduling.
  - Use shared busy-state names.
- Modify `Sources/MultiCodex/Features/Shared/AccountManagementController.swift`
  - Keep switch-preempt logic in one helper.
- Modify `Sources/MultiCodex/Features/MenuBar/AccountsMenuContentView+Sections.swift`
  - Use view-model action availability helpers instead of local duplicates.
- Modify `Sources/MultiCodex/Features/Settings/SettingsContentView+Bindings.swift`
  - Remove duplicated busy-state computation after helpers exist.
- Modify `Sources/MultiCodex/Infrastructure/Codex/Accounts/CodexAccountServicing.swift`
  - Remove temporary default overloads if all mocks and services implement explicit API.
- Modify `Sources/MultiCodex/Infrastructure/Codex/Accounts/CodexAccountService.swift`
  - Tighten cancellation wrapper names and service comments.
- Modify `Sources/MultiCodex/Infrastructure/Codex/Usage/RateLimitsFetcher.swift`
  - Extract common partial-emission/cancellation helpers.
  - Remove duplicate payload assembly.
- Modify `Tests/MultiCodexTests/AccountsMenuViewModelTests.swift`
  - Consolidate repeated account/usage fixtures.
  - Keep behavioral tests readable.
- Modify `Tests/MultiCodexTests/TestFixtures.swift`
  - Add reusable account/usage builders if duplication is obvious.
- Modify `docs/superpowers/plans/*.md`
  - Add completion notes only if implementation changes plan assumptions.

---

## Task 1: Baseline And Duplication Inventory

**Files:**
- Read: `Sources/MultiCodex/Features/Shared/AccountsMenuViewModel.swift`
- Read: `Sources/MultiCodex/Features/Shared/AccountsRefreshController.swift`
- Read: `Sources/MultiCodex/Features/Shared/AccountActionController.swift`
- Read: `Sources/MultiCodex/Infrastructure/Codex/Usage/RateLimitsFetcher.swift`
- Read: `Tests/MultiCodexTests/AccountsMenuViewModelTests.swift`

- [ ] **Step 1: Capture baseline status**

Run:

```bash
rtk git status --short
rtk just check
rtk git diff --check
```

Expected:

```text
no unstaged implementation changes
just check exits 0
git diff --check exits 0
```

- [ ] **Step 2: Inventory duplicate busy-state logic**

Run:

```bash
rtk rg -n "isActionBusy|isSwitchBusy|isLoginBusy|isAccountActionRunning|isSwitchActionRunning|isLoginActionRunning|accountActionInFlightName|loginInFlightName|authMutationInFlightName|switchingAccountName" Sources/MultiCodex Tests/MultiCodexTests
```

Write a temporary checklist in the task notes with each duplicate location. Do not commit the task notes.

- [ ] **Step 3: Inventory refresh entrypoints**

Run:

```bash
rtk rg -n "performRefresh\\(|triggerRefresh\\(|activeRefreshTask|refreshGeneration|RefreshCancellationToken" Sources/MultiCodex Tests/MultiCodexTests
```

Expected app code after cleanup:

```text
performRefresh is called only by triggerRefresh and test-only direct calls
all app-initiated refreshes call triggerRefresh
```

- [ ] **Step 4: Inventory repeated test fixtures**

Run:

```bash
rtk rg -n "AccountUsage\\(|UsageSummary\\(|UsageMetric\\(|AccountEntry\\(" Tests/MultiCodexTests/AccountsMenuViewModelTests.swift
```

Look for 3+ repeated blocks that can become fixture helpers.

---

## Task 2: Centralize Action Availability In View Model

**Files:**
- Modify: `Sources/MultiCodex/Features/Shared/AccountsMenuViewModel.swift`
- Modify: `Sources/MultiCodex/Features/MenuBar/AccountsMenuContentView+Sections.swift`
- Modify: `Sources/MultiCodex/Features/Settings/SettingsContentView+Bindings.swift`
- Modify: `Sources/MultiCodex/Features/Settings/SettingsContentView+Accounts.swift`
- Test: `Tests/MultiCodexTests/AccountsMenuViewModelTests.swift`

- [ ] **Step 1: Add failing tests for availability helpers**

Add tests to `AccountsMenuViewModelTests`:

```swift
func testActionAvailabilityAllowsSwitchDuringRefreshAndLogin() {
    let viewModel = AccountsMenuViewModel(accountService: MockCodexAccountService(), startImmediately: false)

    viewModel.isRefreshing = true
    XCTAssertTrue(viewModel.canStartSwitchAction)

    viewModel.loginInFlightName = "new-account"
    XCTAssertTrue(viewModel.canStartSwitchAction)
    XCTAssertFalse(viewModel.canStartLoginAction)

    viewModel.authMutationInFlightName = "alpha"
    XCTAssertFalse(viewModel.canStartSwitchAction)
    XCTAssertFalse(viewModel.canStartLoginAction)
}

func testActionAvailabilityKeepsMaintenanceActionsConservative() {
    let viewModel = AccountsMenuViewModel(accountService: MockCodexAccountService(), startImmediately: false)

    XCTAssertTrue(viewModel.canStartMaintenanceAccountAction)

    viewModel.accountActionInFlightName = "alpha"
    XCTAssertFalse(viewModel.canStartMaintenanceAccountAction)

    viewModel.accountActionInFlightName = nil
    viewModel.sequentialLoginState = SequentialLoginState(items: [SequentialLoginItem(accountName: "beta")])
    viewModel.sequentialLoginState?.isRunning = true
    XCTAssertFalse(viewModel.canStartMaintenanceAccountAction)
}
```

- [ ] **Step 2: Run tests and verify fail**

Run:

```bash
rtk swift test --filter AccountsMenuViewModelTests/testActionAvailability
```

Expected:

```text
compile fails because canStartSwitchAction/canStartLoginAction/canStartMaintenanceAccountAction do not exist
```

- [ ] **Step 3: Add view-model helpers**

Add to `AccountsMenuViewModel`:

```swift
var canStartSwitchAction: Bool {
    switchingAccountName == nil && authMutationInFlightName == nil
}

var canStartLoginAction: Bool {
    loginInFlightName == nil && authMutationInFlightName == nil
}

var canStartMaintenanceAccountAction: Bool {
    accountActionInFlightName == nil
        && switchingAccountName == nil
        && authMutationInFlightName == nil
        && sequentialLoginState?.isRunning != true
}
```

- [ ] **Step 4: Replace menu duplicate logic**

In `AccountsMenuContentView+Sections.swift`, replace local helper bodies:

```swift
var isSwitchBusy: Bool {
    !viewModel.canStartSwitchAction
}

var isLoginBusy: Bool {
    !viewModel.canStartLoginAction
}

var isActionBusy: Bool {
    !viewModel.canStartMaintenanceAccountAction
}
```

- [ ] **Step 5: Replace settings duplicate logic**

In `SettingsContentView+Bindings.swift`, replace local helper bodies:

```swift
var isSwitchActionRunning: Bool {
    !viewModel.canStartSwitchAction
}

var isLoginActionRunning: Bool {
    !viewModel.canStartLoginAction
}

var isAccountActionRunning: Bool {
    !viewModel.canStartMaintenanceAccountAction
}
```

- [ ] **Step 6: Run tests**

Run:

```bash
rtk swift test --filter AccountsMenuViewModelTests/testActionAvailability
rtk swift test --filter AccountsMenuViewModelTests/testSwitchCanStartWhileRefreshIsRunning
rtk swift test --filter AccountsMenuViewModelTests/testSwitchCanStartWhileNewAccountLoginIsRunning
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
rtk git add Sources/MultiCodex/Features/Shared/AccountsMenuViewModel.swift Sources/MultiCodex/Features/MenuBar/AccountsMenuContentView+Sections.swift Sources/MultiCodex/Features/Settings/SettingsContentView+Bindings.swift Sources/MultiCodex/Features/Settings/SettingsContentView+Accounts.swift Tests/MultiCodexTests/AccountsMenuViewModelTests.swift
rtk git commit -m "refactor: centralize account action availability"
```

---

## Task 3: Consolidate Refresh Lifecycle Helpers

**Files:**
- Modify: `Sources/MultiCodex/Features/Shared/AccountsMenuViewModel.swift`
- Modify: `Sources/MultiCodex/Features/Shared/AccountsRefreshController.swift`
- Modify: `Sources/MultiCodex/Features/Shared/AccountActionController.swift`
- Modify: `Sources/MultiCodex/Features/Shared/AccountManagementController.swift`
- Test: `Tests/MultiCodexTests/AccountsMenuViewModelTests.swift`

- [ ] **Step 1: Add explicit refresh preemption helper**

Add to `AccountsMenuViewModel`:

```swift
func cancelActiveRefreshForUserSwitch() {
    activeRefreshTask?.cancel()
    activeRefreshTask = nil
    refreshGeneration += 1
    isRefreshing = false
}
```

- [ ] **Step 2: Use helper in switch path**

In `AccountManagementController.switchToAccount`, replace:

```swift
viewModel.activeRefreshTask?.cancel()
viewModel.activeRefreshTask = nil
viewModel.refreshGeneration += 1
viewModel.isRefreshing = false
```

With:

```swift
viewModel.cancelActiveRefreshForUserSwitch()
```

- [ ] **Step 3: Extract stale check helper**

In `AccountsRefreshController`, add:

```swift
private func isRefreshStale(generation: Int?) -> Bool {
    Task.isCancelled || generation.map { $0 != viewModel.refreshGeneration } == true
}
```

Replace local nested `isStale()` with:

```swift
if isRefreshStale(generation: generation) {
    viewModel.isRefreshing = false
    return
}
```

- [ ] **Step 4: Extract tracked refresh scheduling**

Keep only one path that mutates `activeRefreshTask` and `refreshGeneration`:

```swift
func triggerRefresh(refreshLive: Bool, allowAutoSwitch: Bool = true) {
    let viewModel = viewModel
    viewModel.activeRefreshTask?.cancel()
    viewModel.refreshGeneration += 1
    let generation = viewModel.refreshGeneration
    viewModel.activeRefreshTask = Task { @MainActor in
        await viewModel.refreshController.performRefresh(
            refreshLive: refreshLive,
            allowAutoSwitch: allowAutoSwitch,
            generation: generation
        )
    }
}
```

If this code already matches, only add a comment:

```swift
// All app refreshes must flow through this method so stale results cannot apply after a switch.
```

- [ ] **Step 5: Ensure no app code calls performRefresh directly**

Run:

```bash
rtk rg -n "performRefresh\\(" Sources/MultiCodex
```

Expected only:

```text
Sources/MultiCodex/Features/Shared/AccountsRefreshController.swift
```

- [ ] **Step 6: Run refresh tests**

Run:

```bash
rtk swift test --filter AccountsMenuViewModelTests/testSwitchCancelsActiveRefreshToken
rtk swift test --filter AccountsMenuViewModelTests/testSwitchToAccountCompletesBeforeBackgroundRefreshFinishes
rtk swift test --filter AccountsMenuViewModelTests/testManualStrategyDoesNotReconcileExternalAuthIntoCurrentAccount
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
rtk git add Sources/MultiCodex/Features/Shared/AccountsMenuViewModel.swift Sources/MultiCodex/Features/Shared/AccountsRefreshController.swift Sources/MultiCodex/Features/Shared/AccountActionController.swift Sources/MultiCodex/Features/Shared/AccountManagementController.swift Tests/MultiCodexTests/AccountsMenuViewModelTests.swift
rtk git commit -m "refactor: consolidate refresh lifecycle control"
```

---

## Task 4: Deduplicate Partial Limits Payload Assembly

**Files:**
- Modify: `Sources/MultiCodex/Infrastructure/Codex/Usage/RateLimitsFetcher.swift`
- Test: `Tests/MultiCodexTests/AccountsMenuViewModelTests.swift`
- Test: `Tests/MultiCodexTests/CodexAccountServiceTests.swift`

- [ ] **Step 1: Add local helper in fetcher**

In `RateLimitsFetcher.swift`, inside `fetchLimitsNow(refreshLive:cancellationToken:onPartialResult:)`, add:

```swift
func emitPartial(results: [LimitsResult], errors: [LimitsErrorEntry]) {
    onPartialResult?(LimitsPayload(results: results, errors: errors))
}
```

Replace repeated:

```swift
onPartialResult?(LimitsPayload(results: results, errors: errors))
```

With:

```swift
emitPartial(results: results, errors: errors)
```

- [ ] **Step 2: Extract managed fallback error mapper**

Add private helper:

```swift
private func mergeManagedFallbackReason(
    into error: LimitsErrorEntry,
    managedFallbackReasons: [String: String]
) -> LimitsErrorEntry {
    guard let managedReason = managedFallbackReasons[error.account] else {
        return error
    }
    return LimitsErrorEntry(
        account: error.account,
        message: "\(managedReason); serial fallback failed: \(error.message)"
    )
}
```

Use it in final serial append and partial callback.

- [ ] **Step 3: Make serial partial callback name explicit**

Change `fetchLimitsSerial` parameter:

```swift
onPartialResult: (LimitsPayload) -> Void
```

To:

```swift
onSerialPartial: (LimitsPayload) -> Void
```

Then replace calls:

```swift
onSerialPartial(LimitsPayload(results: results, errors: errors))
```

- [ ] **Step 4: Run service and view-model tests**

Run:

```bash
rtk swift test --filter AccountsMenuViewModelTests/testRefreshAppliesPartialUsageBeforeFullLimitsReturn
rtk swift test --filter CodexAccountServiceTests
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
rtk git add Sources/MultiCodex/Infrastructure/Codex/Usage/RateLimitsFetcher.swift Tests/MultiCodexTests/AccountsMenuViewModelTests.swift Tests/MultiCodexTests/CodexAccountServiceTests.swift
rtk git commit -m "refactor: deduplicate limits partial assembly"
```

---

## Task 5: Tighten Service Cancellation API

**Files:**
- Modify: `Sources/MultiCodex/Infrastructure/Codex/Accounts/CodexAccountServicing.swift`
- Modify: `Sources/MultiCodex/Infrastructure/Codex/Accounts/CodexAccountService.swift`
- Modify: `Tests/MultiCodexTests/AccountsMenuViewModelTests.swift`
- Modify: `Tests/MultiCodexTests/CodexAccountServiceTests.swift`

- [ ] **Step 1: Decide if default protocol overload is still needed**

Run:

```bash
rtk rg -n "func fetchLimits\\(" Sources/MultiCodex Tests/MultiCodexTests
```

If every concrete test mock implements the cancellation/partial overload, remove this default implementation:

```swift
func fetchLimits(
    refreshLive: Bool,
    cancellationToken: RefreshCancellationToken,
    onPartialResult: @escaping @Sendable (LimitsPayload) -> Void
) async throws -> LimitsPayload {
    try await fetchLimits(refreshLive: refreshLive)
}
```

- [ ] **Step 2: Add comments to cancellation token**

Keep comment short:

```swift
/// Crosses the async-to-blocking boundary used by the limits fetcher.
/// Cancelling the Swift task alone cannot stop detached legacy auth work.
```

- [ ] **Step 3: Rename parameter for clarity if needed**

Use `refreshCancellation` instead of `cancellationToken` only if all call sites stay readable:

```swift
func fetchLimits(
    refreshLive: Bool,
    refreshCancellation: RefreshCancellationToken,
    onPartialResult: @escaping @Sendable (LimitsPayload) -> Void
) async throws -> LimitsPayload
```

Do not rename if it causes noisy churn with no clarity gain.

- [ ] **Step 4: Run tests**

Run:

```bash
rtk swift test --filter AccountsMenuViewModelTests/testSwitchCancelsActiveRefreshToken
rtk swift test --filter CodexAccountServiceTests
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
rtk git add Sources/MultiCodex/Infrastructure/Codex/Accounts/CodexAccountServicing.swift Sources/MultiCodex/Infrastructure/Codex/Accounts/CodexAccountService.swift Tests/MultiCodexTests/AccountsMenuViewModelTests.swift Tests/MultiCodexTests/CodexAccountServiceTests.swift
rtk git commit -m "refactor: tighten limits cancellation API"
```

---

## Task 6: Consolidate Test Fixtures

**Files:**
- Modify: `Tests/MultiCodexTests/TestFixtures.swift`
- Modify: `Tests/MultiCodexTests/AccountsMenuViewModelTests.swift`

- [ ] **Step 1: Add reusable account entry fixture**

Add to `TestFixtures.swift`:

```swift
func makeAccountEntry(
    name: String,
    isCurrent: Bool = false,
    hasAuth: Bool = true,
    lastUsedAt: String? = nil,
    lastLoginStatus: String? = nil,
    defaultWorkspaceEmail: String? = nil
) -> AccountEntry {
    AccountEntry(
        name: name,
        isCurrent: isCurrent,
        hasAuth: hasAuth,
        lastUsedAt: lastUsedAt,
        lastLoginStatus: lastLoginStatus,
        defaultWorkspaceEmail: defaultWorkspaceEmail
    )
}
```

- [ ] **Step 2: Add reusable empty usage fixture**

Add to `TestFixtures.swift`:

```swift
func makeEmptyUsageSummary() -> UsageSummary {
    UsageSummary(
        fiveHour: UsageMetric(label: "5h", percentText: "-", usedPercent: nil, periodMinutes: nil, resetsAt: nil),
        weekly: UsageMetric(label: "weekly", percentText: "-", usedPercent: nil, periodMinutes: nil, resetsAt: nil),
        credits: "-"
    )
}
```

- [ ] **Step 3: Add reusable account usage fixture**

Add to `TestFixtures.swift`:

```swift
func makeAccountUsage(
    name: String,
    isCurrent: Bool = false,
    hasAuth: Bool = true,
    usage: UsageSummary = makeEmptyUsageSummary()
) -> AccountUsage {
    AccountUsage(
        name: name,
        isCurrent: isCurrent,
        hasAuth: hasAuth,
        lastUsedAt: nil,
        lastLoginStatus: nil,
        usage: usage,
        source: "",
        usageError: nil
    )
}
```

- [ ] **Step 4: Replace repeated local blocks**

In `AccountsMenuViewModelTests.swift`, replace repeated two-account setup:

```swift
let emptyUsage = makeEmptyUsageSummary()
viewModel.updateAccounts([
    makeAccountUsage(name: "alpha", isCurrent: true, usage: emptyUsage),
    makeAccountUsage(name: "beta", usage: emptyUsage),
])
```

Replace repeated account entries:

```swift
service.stubbedAccounts = [
    makeAccountEntry(name: "alpha", isCurrent: true),
    makeAccountEntry(name: "beta"),
]
```

- [ ] **Step 5: Run tests**

Run:

```bash
rtk swift test --filter AccountsMenuViewModelTests
```

Expected: pass.

- [ ] **Step 6: Commit**

```bash
rtk git add Tests/MultiCodexTests/TestFixtures.swift Tests/MultiCodexTests/AccountsMenuViewModelTests.swift
rtk git commit -m "test: consolidate account view model fixtures"
```

---

## Task 7: Cleanup Comments, Names, And Stale Plan Drift

**Files:**
- Modify: `Sources/MultiCodex/Features/Shared/AccountsRefreshController.swift`
- Modify: `Sources/MultiCodex/Infrastructure/Codex/Usage/RateLimitsFetcher.swift`
- Modify: `docs/superpowers/plans/2026-05-03-startup-switch-responsiveness.md`
- Modify: `docs/superpowers/plans/2026-05-03-final-cleanup-dry-pass-consolidation.md`

- [ ] **Step 1: Remove misleading comments**

Search:

```bash
rtk rg -n "FIXME|temporary|hack|legacy|must|should|partial|generation|cancel" Sources/MultiCodex docs/superpowers/plans
```

Only change comments that are stale or misleading. Do not rewrite useful architecture notes.

- [ ] **Step 2: Add concise invariants**

In `AccountsRefreshController`, keep one invariant comment above `triggerRefresh`:

```swift
// Invariant: all app refreshes go through this method so generation checks can drop stale results.
```

In `RateLimitsFetcher`, keep one invariant comment above `fetchLimitsSerial`:

```swift
// Legacy auth-swap fetch must stay serial because it touches the shared system auth file.
```

- [ ] **Step 3: Update plan completion notes**

At bottom of `2026-05-03-startup-switch-responsiveness.md`, add:

```markdown
## Implementation Note

Implemented in commit `<commit-sha>` with generation-tracked refreshes, refresh cancellation tokens, partial limits application, and manual-mode reconciliation guard.
```

Replace `<commit-sha>` with:

```bash
rtk git rev-parse --short HEAD
```

- [ ] **Step 4: Run docs/check**

Run:

```bash
rtk git diff --check
rtk just check
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
rtk git add Sources/MultiCodex/Features/Shared/AccountsRefreshController.swift Sources/MultiCodex/Infrastructure/Codex/Usage/RateLimitsFetcher.swift docs/superpowers/plans/2026-05-03-startup-switch-responsiveness.md docs/superpowers/plans/2026-05-03-final-cleanup-dry-pass-consolidation.md
rtk git commit -m "docs: document refresh cleanup invariants"
```

---

## Task 8: Final Verification Pass

**Files:**
- Verify all modified files.

- [ ] **Step 1: Run full verification**

Run:

```bash
rtk just check
rtk git diff --check
```

Expected:

```text
doctor passes
debug build passes
all Swift tests pass
no whitespace errors
```

- [ ] **Step 2: Inspect final diff**

Run:

```bash
rtk git status --short
rtk git log --oneline -8
```

Expected:

```text
working tree clean
cleanup commits are small and readable
```

- [ ] **Step 3: Manual smoke test**

Run:

```bash
rtk just run
```

Manual checks:

- App opens with accounts visible quickly.
- Cached usage appears before slow live refresh completes.
- Switch works during refresh.
- Switch works while a sandboxed login is running.
- Manual strategy does not switch current account after external auth changes.
- Automatic strategy still switches only when selected.
- Account cards do not clip expanded content.

- [ ] **Step 4: Do not merge until review**

Request review with focus areas:

```text
Review focus:
- stale refresh cannot apply after switch
- manual strategy cannot mutate current account indirectly
- busy-state helpers match UI disabling intent
- partial usage updates cannot regress usage sorting or pace recording
```

---

## Non-Goals

- Do not redesign the UI.
- Do not parallelize legacy auth-swap refresh.
- Do not remove managed-home fallback.
- Do not change account recommendation scoring.
- Do not change storage schema.

## Completion Notes

Implemented across 7 commits (`a0d5089` through `f7b0c4d`):
- Centralized action availability into `canStartSwitchAction`, `canStartLoginAction`, `canStartMaintenanceAccountAction` on view model.
- Consolidated refresh lifecycle: `cancelActiveRefreshForUserSwitch()` helper, `isRefreshStale(generation:)` helper, single `triggerRefresh` entrypoint.
- Deduplicated limits partial assembly with `emitPartial()` local and `mergeManagedFallbackReason(into:managedReasons:)` helper.
- Removed dead default protocol overload for `fetchLimits(refreshLive:cancellationToken:onPartialResult:)`.
- Added documentation invariant comments on `triggerRefresh` and `fetchLimitsSerial`.
- Consolidated test fixtures: `makeAccountEntry`, `UsageFixtures.makeEmptyUsageSummary`, `UsageFixtures.makeAccountUsage` in `TestFixtures.swift`.

## Completion Criteria

- [x] Duplicate busy-state logic removed from menu/settings.
- [x] All app refresh scheduling flows through one generation-tracked path.
- [x] Cancellation token path remains covered by tests.
- [x] Partial usage update path remains covered by tests.
- [x] Repeated test fixture blocks are reduced.
- [x] Full `rtk just check` passes.
- [x] Full `rtk git diff --check` passes.
- [ ] Manual smoke test passes (pending manual verification).

