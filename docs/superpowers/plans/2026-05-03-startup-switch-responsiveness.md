# Startup Usage + Switch Responsiveness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make initial app start populate account usage quickly and keep manual account switching available during refreshes and sandboxed login flows.

**Architecture:** Split "data refresh" from "auth mutation" and stop using one global busy flag for unrelated operations. Startup should paint account rows and cached/stale usage immediately, then update live usage per account or per small batch without blocking user switching. Account switching should be priority auth work that cancels/suspends refresh work before touching shared `~/.codex/auth.json`.

**Tech Stack:** Swift 5.9, SwiftUI, Swift concurrency, SwiftPM tests, `just check`.

---

## Problem Summary

Four validated issues need fixes:

- Cold start calls `performRefresh(refreshLive: false)` and waits for `fetchLimits(false)`. On cold cache, every account becomes a live target, so usage stats appear only after all account limits finish.
- Legacy/cold limits are fetched serially. One slow account delays all later accounts and final UI application.
- Menu switching is disabled while `viewModel.isRefreshing == true`.
- Login flow sets `accountActionInFlightName` for the whole browser/terminal login, and menu/settings use that as a global blocker for switching.

## Design Constraints

- Never run two global-auth mutations at same time. Switching, import-auth, remove/rename that touches auth, legacy refresh auth-swap, and final login import/apply must coordinate.
- Switching must win over refresh. If refresh is using legacy auth-swap, switch waits only for current tiny critical section or cancels refresh before the next account.
- Sandboxed login must not block switching. Login uses `loginSandboxHome`; only the final import/apply phase needs auth mutation lock.
- UI should show available data early. Account list and cached/stale usage should paint before live usage completes.
- Keep implementation small. Avoid broad architectural rewrite.

## File Map

- Modify `Sources/MultiCodex/Features/Shared/AccountsMenuViewModel.swift`
  - Add separate busy state fields.
  - Add cancellable refresh generation/task tracking.
  - Add startup fast-path entrypoint.
- Modify `Sources/MultiCodex/Features/Shared/AccountsRefreshController.swift`
  - Add cached/stale first refresh mode.
  - Add live refresh cancellation checks.
  - Apply partial usage updates.
- Modify `Sources/MultiCodex/Infrastructure/Codex/Usage/RateLimitsFetcher.swift`
  - Add cached/stale fetch helper.
  - Add partial live fetch API or callback-based API.
  - Add cancellation checks around serial legacy path.
- Modify `Sources/MultiCodex/Infrastructure/Codex/Accounts/CodexAccountServicing.swift`
  - Add protocol methods for cached/stale and partial limits fetch.
- Modify `Sources/MultiCodex/Infrastructure/Codex/Accounts/CodexAccountService.swift`
  - Implement new protocol methods by delegating to fetcher.
- Modify `Sources/MultiCodex/Features/Shared/AccountActionController.swift`
  - Split login busy state from auth mutation state.
  - Do not block switch during sandboxed login.
- Modify `Sources/MultiCodex/Features/Shared/AccountManagementController.swift`
  - Make switch cancel/suspend active refresh before auth mutation.
- Modify `Sources/MultiCodex/Features/MenuBar/AccountsMenuContentView+Sections.swift`
  - Remove refresh from switch gating.
  - Disable only actions that actually conflict.
- Modify `Sources/MultiCodex/Features/Settings/SettingsContentView+Bindings.swift`
  - Replace global `isAccountActionRunning` with more precise flags.
- Modify `Sources/MultiCodex/Features/Settings/SettingsContentView+Accounts.swift`
  - Allow switch during login and refresh.
- Modify `Tests/MultiCodexTests/AccountsMenuViewModelTests.swift`
  - Add startup fast paint, switch during refresh, switch during login tests.
- Modify `Tests/MultiCodexTests/CodexAccountServiceTests.swift`
  - Add cached/stale helper tests if service-level behavior is not fully covered by view-model tests.

## New State Model

Add these fields to `AccountsMenuViewModel`:

```swift
@Published var loginInFlightName: String?
@Published var authMutationInFlightName: String?
var activeRefreshTask: Task<Void, Never>?
var refreshGeneration = 0
```

Keep existing fields temporarily:

```swift
@Published var accountActionInFlightName: String?
@Published var switchingAccountName: String?
```

Migration rule:

- `switchingAccountName`: switch-only spinner/state.
- `loginInFlightName`: browser/terminal/sandbox login spinner/state.
- `authMutationInFlightName`: short critical auth operations, final login import/apply, import default auth, legacy auth swap if surfaced to UI.
- `accountActionInFlightName`: keep for rename/remove/status/import until all call sites are migrated; do not use it to block switch.

## Desired User Behavior

- Open app:
  - Account cards appear as soon as account list loads.
  - Cached/stale usage appears immediately if any cache exists.
  - Live usage fills in per account while spinner remains subtle.
- Click switch while refresh running:
  - Switch starts.
  - Refresh cancels or pauses.
  - UI current account changes after switch succeeds.
  - Lightweight refresh restarts for selected account or normal cached refresh restarts.
- Start new account login:
  - Login progress/toast shows.
  - Existing account switch buttons remain enabled.
  - Final import/apply may briefly disable conflicting auth actions only.

---

## Task 1: Add Fast Startup Tests

**Files:**
- Modify: `Tests/MultiCodexTests/AccountsMenuViewModelTests.swift`

- [ ] **Step 1: Add fake-service support for cached-first limits**

In `MockCodexAccountService`, add:

```swift
var fetchCachedLimitsResult = LimitsPayload(results: [], errors: [])
var fetchCachedLimitsDelayNanoseconds: UInt64 = 0
private(set) var fetchCachedLimitsCalls = 0
var onFetchLimitsStarted: (() -> Void)?
```

Update `fetchLimits(refreshLive:)`:

```swift
func fetchLimits(refreshLive: Bool) async throws -> LimitsPayload {
    if let fetchLimitsError {
        throw fetchLimitsError
    }
    fetchLimitsRefreshLiveCalls.append(refreshLive)
    onFetchLimitsStarted?()
    if fetchLimitsDelayNanoseconds > 0 {
        try? await Task.sleep(nanoseconds: fetchLimitsDelayNanoseconds)
    }
    return fetchLimitsResult
}
```

Add protocol stub method:

```swift
func fetchCachedLimits() async throws -> LimitsPayload {
    fetchCachedLimitsCalls += 1
    if fetchCachedLimitsDelayNanoseconds > 0 {
        try? await Task.sleep(nanoseconds: fetchCachedLimitsDelayNanoseconds)
    }
    return fetchCachedLimitsResult
}
```

- [ ] **Step 2: Write failing test for immediate cached usage paint**

Add test:

```swift
func testStartPaintsCachedUsageBeforeSlowLiveRefreshCompletes() async {
    let service = MockCodexAccountService()
    service.accountsPayload = AccountsListPayload(
        accounts: ["alpha"],
        currentAccount: "alpha",
        authenticatedAccounts: ["alpha"]
    )
    service.fetchCachedLimitsResult = LimitsPayload(
        results: [
            LimitsResult(
                account: "alpha",
                source: "cached",
                snapshot: RateLimitSnapshot(
                    fiveHour: RateLimitWindow(usedPercent: 25, resetsAt: nil),
                    weekly: RateLimitWindow(usedPercent: 50, resetsAt: nil)
                ),
                ageSec: 120
            )
        ],
        errors: []
    )
    service.fetchLimitsDelayNanoseconds = 500_000_000

    let viewModel = AccountsMenuViewModel(accountService: service, startImmediately: true)

    await fulfillment(of: [
        expectation(description: "cached usage painted") { @MainActor in
            viewModel.accounts.first?.usage.fiveHour.usedPercent == 25
        }
    ], timeout: 0.2)

    XCTAssertEqual(service.fetchCachedLimitsCalls, 1)
    XCTAssertTrue(viewModel.isRefreshing)
}
```

- [ ] **Step 3: Run focused test and verify fail**

Run:

```bash
rtk swift test --filter AccountsMenuViewModelTests/testStartPaintsCachedUsageBeforeSlowLiveRefreshCompletes
```

Expected before implementation: compile failure because `fetchCachedLimits()` is not in protocol/service, or test timeout because startup waits for slow live limits.

---

## Task 2: Add Cached/Stale Limits API

**Files:**
- Modify: `Sources/MultiCodex/Infrastructure/Codex/Accounts/CodexAccountServicing.swift`
- Modify: `Sources/MultiCodex/Infrastructure/Codex/Accounts/CodexAccountService.swift`
- Modify: `Sources/MultiCodex/Infrastructure/Codex/Usage/RateLimitsFetcher.swift`

- [ ] **Step 1: Extend service protocol**

Add to `CodexAccountServicing`:

```swift
func fetchCachedLimits() async throws -> LimitsPayload
```

- [ ] **Step 2: Implement service method**

In `CodexAccountService`, add:

```swift
func fetchCachedLimits() async throws -> LimitsPayload {
    try await Task.detached(priority: .userInitiated) {
        try fetchCachedLimitsNow()
    }.value
}
```

- [ ] **Step 3: Add cached fetcher method**

In `RateLimitsFetcher`, add:

```swift
func fetchCachedLimitsNow() throws -> LimitsPayload {
    let paths = currentPaths()
    let config = try loadConfig(paths: paths)
    let targets = config.accounts.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    let ttlSeconds = Self.normalizedLimitsCacheTTLSeconds(limitsCacheTTLSeconds)
    var results: [LimitsResult] = []

    for account in targets {
        if let cached = try getCachedLimits(account: account, ttlMs: Double(ttlSeconds * 1000), paths: paths) {
            let ageSec = Int((cached.ageMs / 1000.0).rounded())
            results.append(LimitsResult(account: account, source: "cached", snapshot: cached.snapshot, ageSec: ageSec))
        }
    }

    return LimitsPayload(results: results, errors: [])
}
```

- [ ] **Step 4: Run compile-focused tests**

Run:

```bash
rtk swift test --filter AccountsMenuViewModelTests/testStartPaintsCachedUsageBeforeSlowLiveRefreshCompletes
```

Expected: compile passes, test still may fail until startup uses cached API.

---

## Task 3: Startup Fast Paint Then Background Live

**Files:**
- Modify: `Sources/MultiCodex/Features/Shared/AccountsMenuViewModel.swift`
- Modify: `Sources/MultiCodex/Features/Shared/AccountsRefreshController.swift`

- [ ] **Step 1: Add startup method**

In `AccountsMenuViewModel.start()`, replace initial task body with:

```swift
Task { @MainActor in
    await refreshController.performStartupRefresh()
}
```

- [ ] **Step 2: Add startup refresh controller method**

Add to `AccountsRefreshController`:

```swift
func performStartupRefresh() async {
    let viewModel = viewModel
    guard !viewModel.isRefreshing else {
        return
    }

    viewModel.isRefreshing = true
    let previousAccounts = viewModel.accounts

    do {
        let accountsPayload = try await viewModel.accountService.fetchAccounts()
        let cachedLimits = try? await viewModel.accountService.fetchCachedLimits()
        await applyMergedAccounts(
            accountsPayload: accountsPayload,
            limits: cachedLimits ?? LimitsPayload(results: [], errors: []),
            previousAccounts: previousAccounts,
            recordPace: cachedLimits?.results.isEmpty == false
        )
        viewModel.lastRefreshError = nil
        viewModel.refreshWarningMessage = nil

        Task { @MainActor in
            await viewModel.refreshController.performRefresh(
                refreshLive: viewModel.shouldPreferLiveRefreshForAutoSwitching,
                allowAutoSwitch: true
            )
        }
    } catch {
        viewModel.lastRefreshError = error.localizedDescription
        viewModel.refreshWarningMessage = nil
    }

    viewModel.isRefreshing = false
}
```

- [ ] **Step 3: Avoid skipped live refresh after startup**

Because `performStartupRefresh()` schedules live refresh after setting `isRefreshing = false`, ensure the `Task` is created after the assignment:

```swift
let shouldRunLive = true
viewModel.isRefreshing = false
if shouldRunLive {
    Task { @MainActor in
        await viewModel.refreshController.performRefresh(
            refreshLive: viewModel.shouldPreferLiveRefreshForAutoSwitching,
            allowAutoSwitch: true
        )
    }
}
```

- [ ] **Step 4: Run startup test**

Run:

```bash
rtk swift test --filter AccountsMenuViewModelTests/testStartPaintsCachedUsageBeforeSlowLiveRefreshCompletes
```

Expected: PASS.

---

## Task 4: Add Switch During Refresh Tests

**Files:**
- Modify: `Tests/MultiCodexTests/AccountsMenuViewModelTests.swift`

- [ ] **Step 1: Add test that switch starts while refresh is active**

Add test:

```swift
func testSwitchCanStartWhileRefreshIsRunning() async {
    let service = MockCodexAccountService()
    service.accountsPayload = AccountsListPayload(
        accounts: ["alpha", "beta"],
        currentAccount: "alpha",
        authenticatedAccounts: ["alpha", "beta"]
    )
    service.fetchLimitsDelayNanoseconds = 500_000_000

    let viewModel = AccountsMenuViewModel(accountService: service, startImmediately: false)
    viewModel.updateAccounts([
        AccountUsage(name: "alpha", isCurrent: true, usage: .empty, connectionState: .connected),
        AccountUsage(name: "beta", isCurrent: false, usage: .empty, connectionState: .connected),
    ])

    viewModel.refreshLive()
    await fulfillment(of: [
        expectation(description: "refresh active") { @MainActor in
            viewModel.isRefreshing
        }
    ], timeout: 0.2)

    viewModel.switchToAccount(named: "beta")

    await fulfillment(of: [
        expectation(description: "switch started") { @MainActor in
            viewModel.switchingAccountName == "beta" || viewModel.currentAccount?.name == "beta"
        }
    ], timeout: 0.2)
}
```

- [ ] **Step 2: Run focused test and verify fail if UI/view-model still gates**

Run:

```bash
rtk swift test --filter AccountsMenuViewModelTests/testSwitchCanStartWhileRefreshIsRunning
```

Expected before final implementation: view-model may pass because gating is mostly UI. Keep this test as model guard; Task 5 adds UI logic change.

---

## Task 5: Remove Refresh From Switch Gating

**Files:**
- Modify: `Sources/MultiCodex/Features/MenuBar/AccountsMenuContentView+Sections.swift`
- Modify: `Sources/MultiCodex/Features/Settings/SettingsContentView+Bindings.swift`
- Modify: `Sources/MultiCodex/Features/Settings/SettingsContentView+Accounts.swift`

- [ ] **Step 1: Split menu busy flags**

Replace menu `isActionBusy` with:

```swift
var isSwitchBusy: Bool {
    viewModel.switchingAccountName != nil || viewModel.authMutationInFlightName != nil
}

var isLoginBusy: Bool {
    viewModel.loginInFlightName != nil || viewModel.authMutationInFlightName != nil
}

var isActionBusy: Bool {
    viewModel.accountActionInFlightName != nil
        || viewModel.switchingAccountName != nil
        || viewModel.authMutationInFlightName != nil
}
```

- [ ] **Step 2: Update menu primary actions**

Change:

```swift
case .switchAccount:
    guard !isActionBusy else { return }
    viewModel.switchToAccount(named: row.name)
case .relogin:
    guard !isActionBusy else { return }
    viewModel.openLoginInTerminal(for: row.name)
```

To:

```swift
case .switchAccount:
    guard !isSwitchBusy else { return }
    viewModel.switchToAccount(named: row.name)
case .relogin:
    guard !isLoginBusy else { return }
    viewModel.openLoginInTerminal(for: row.name)
```

- [ ] **Step 3: Split settings busy flags**

In `SettingsContentView+Bindings.swift`, replace `isAccountActionRunning` with:

```swift
var isSwitchActionRunning: Bool {
    viewModel.switchingAccountName != nil || viewModel.authMutationInFlightName != nil
}

var isLoginActionRunning: Bool {
    viewModel.loginInFlightName != nil || viewModel.authMutationInFlightName != nil
}

var isAccountActionRunning: Bool {
    viewModel.accountActionInFlightName != nil
        || viewModel.switchingAccountName != nil
        || viewModel.authMutationInFlightName != nil
        || viewModel.sequentialLoginState?.isRunning == true
}
```

- [ ] **Step 4: Update settings switch button disabling**

In `SettingsContentView+Accounts.swift`, change switch button disable:

```swift
.disabled(isAccountActionRunning)
```

To:

```swift
.disabled(isSwitchActionRunning)
```

Change login buttons that call `openLoginInTerminal` or `startNewAccountLogin` to:

```swift
.disabled(isLoginActionRunning)
```

Leave rename/remove/import/check-status on `isAccountActionRunning`.

- [ ] **Step 5: Run UI compile test**

Run:

```bash
rtk swift test --filter AccountsMenuViewModelTests/testSwitchCanStartWhileRefreshIsRunning
```

Expected: PASS and compile no missing symbol errors.

---

## Task 6: Split Login Busy State From Account Action State

**Files:**
- Modify: `Sources/MultiCodex/Features/Shared/AccountsMenuViewModel.swift`
- Modify: `Sources/MultiCodex/Features/Shared/AccountActionController.swift`

- [ ] **Step 1: Add state fields**

In `AccountsMenuViewModel`, add:

```swift
@Published var loginInFlightName: String?
@Published var authMutationInFlightName: String?
```

- [ ] **Step 2: Update login flow guard**

In `AccountActionController.startLoginFlow`, replace guard:

```swift
guard viewModel.accountActionInFlightName == nil,
      viewModel.pendingInteractiveLoginSession?.phase != .waitingForExternalCompletion
else {
    return
}
```

With:

```swift
guard viewModel.loginInFlightName == nil,
      viewModel.pendingInteractiveLoginSession?.phase != .waitingForExternalCompletion
else {
    return
}
```

- [ ] **Step 3: Update login spinner assignment**

Replace:

```swift
viewModel.accountActionInFlightName = accountName
defer {
    viewModel.accountActionInFlightName = nil
}
```

With:

```swift
viewModel.loginInFlightName = accountName
defer {
    viewModel.loginInFlightName = nil
}
```

- [ ] **Step 4: Add auth mutation bracket helper**

In `AccountsMenuViewModel`, add:

```swift
func runAuthMutation<T>(
    named name: String,
    operation: () async throws -> T
) async throws -> T {
    while authMutationInFlightName != nil {
        try Task.checkCancellation()
        try await Task.sleep(for: .milliseconds(25))
    }
    authMutationInFlightName = name
    defer { authMutationInFlightName = nil }
    return try await operation()
}
```

- [ ] **Step 5: Wrap final login import/apply only**

In `completeInteractiveLogin`, replace:

```swift
_ = try await viewModel.accountService.importAuth(fromHome: session.loginSandboxHome, into: session.accountName)
if session.shouldApplyAccountAuthOnSuccess {
    try await viewModel.accountService.switchAccount(name: session.accountName)
}
```

With:

```swift
try await viewModel.runAuthMutation(named: session.accountName) {
    _ = try await viewModel.accountService.importAuth(fromHome: session.loginSandboxHome, into: session.accountName)
    if session.shouldApplyAccountAuthOnSuccess {
        try await viewModel.accountService.switchAccount(name: session.accountName)
    }
}
```

- [ ] **Step 6: Run compile**

Run:

```bash
rtk swift test --filter AccountsMenuViewModelTests
```

Expected: compile succeeds. Some tests may need expectation updates from `accountActionInFlightName` to `loginInFlightName`.

---

## Task 7: Add Switch During Login Test

**Files:**
- Modify: `Tests/MultiCodexTests/AccountsMenuViewModelTests.swift`

- [ ] **Step 1: Add test for switch while sandbox login active**

Add test:

```swift
func testSwitchCanStartWhileNewAccountLoginIsRunning() async {
    let service = MockCodexAccountService()
    service.loginInAppDelayNanoseconds = 500_000_000

    let viewModel = AccountsMenuViewModel(accountService: service, startImmediately: false)
    viewModel.updateAccounts([
        AccountUsage(name: "alpha", isCurrent: true, usage: .empty, connectionState: .connected),
        AccountUsage(name: "beta", isCurrent: false, usage: .empty, connectionState: .connected),
    ])

    viewModel.startNewAccountLogin()

    await fulfillment(of: [
        expectation(description: "login active") { @MainActor in
            viewModel.loginInFlightName != nil
        }
    ], timeout: 0.2)

    viewModel.switchToAccount(named: "beta")

    await fulfillment(of: [
        expectation(description: "switch completed") { @MainActor in
            viewModel.currentAccount?.name == "beta"
        }
    ], timeout: 0.3)

    XCTAssertNotNil(viewModel.loginInFlightName)
}
```

- [ ] **Step 2: Run focused test**

Run:

```bash
rtk swift test --filter AccountsMenuViewModelTests/testSwitchCanStartWhileNewAccountLoginIsRunning
```

Expected: PASS after Task 6.

---

## Task 8: Make Switch Preempt Refresh

**Files:**
- Modify: `Sources/MultiCodex/Features/Shared/AccountsMenuViewModel.swift`
- Modify: `Sources/MultiCodex/Features/Shared/AccountsRefreshController.swift`
- Modify: `Sources/MultiCodex/Features/Shared/AccountManagementController.swift`

- [ ] **Step 1: Track active refresh task**

In `AccountsMenuViewModel`, add:

```swift
var activeRefreshTask: Task<Void, Never>?
var refreshGeneration = 0
```

Update `AccountsRefreshController.triggerRefresh`:

```swift
func triggerRefresh(refreshLive: Bool) {
    let viewModel = viewModel
    viewModel.activeRefreshTask?.cancel()
    viewModel.refreshGeneration += 1
    let generation = viewModel.refreshGeneration
    viewModel.activeRefreshTask = Task { @MainActor in
        await viewModel.refreshController.performRefresh(refreshLive: refreshLive, generation: generation)
    }
}
```

- [ ] **Step 2: Add generation-aware refresh overload**

Change signature:

```swift
func performRefresh(refreshLive: Bool, allowAutoSwitch: Bool = true) async
```

To:

```swift
func performRefresh(refreshLive: Bool, allowAutoSwitch: Bool = true, generation: Int? = nil) async
```

Add after each await:

```swift
if Task.isCancelled || generation.map({ $0 != viewModel.refreshGeneration }) == true {
    viewModel.isRefreshing = false
    return
}
```

Add this check after:

- `refreshStaleTokens()`
- `fetchAccounts()`
- `fetchLimits(refreshLive:)`

- [ ] **Step 3: Cancel refresh before manual switch**

In `AccountManagementController.switchToAccount`, before `runSwitchAction`:

```swift
viewModel.activeRefreshTask?.cancel()
viewModel.activeRefreshTask = nil
viewModel.refreshGeneration += 1
viewModel.isRefreshing = false
```

- [ ] **Step 4: Wrap switch in auth mutation**

Inside `runSwitchAction` operation, replace:

```swift
try await viewModel.accountService.switchAccount(name: name)
```

With:

```swift
try await viewModel.runAuthMutation(named: name) {
    try await viewModel.accountService.switchAccount(name: name)
}
```

- [ ] **Step 5: Restart lightweight refresh after switch**

Keep existing post-switch refresh but make it cached/non-live:

```swift
Task { @MainActor in
    await viewModel.refreshController.performRefresh(refreshLive: false, allowAutoSwitch: false)
}
```

- [ ] **Step 6: Run switch tests**

Run:

```bash
rtk swift test --filter AccountsMenuViewModelTests/testSwitchCanStartWhileRefreshIsRunning
rtk swift test --filter AccountsMenuViewModelTests/testSwitchCanStartWhileNewAccountLoginIsRunning
```

Expected: both PASS.

---

## Task 9: Partial Live Usage Updates

**Files:**
- Modify: `Sources/MultiCodex/Infrastructure/Codex/Accounts/CodexAccountServicing.swift`
- Modify: `Sources/MultiCodex/Infrastructure/Codex/Accounts/CodexAccountService.swift`
- Modify: `Sources/MultiCodex/Infrastructure/Codex/Usage/RateLimitsFetcher.swift`
- Modify: `Sources/MultiCodex/Features/Shared/AccountsRefreshController.swift`
- Modify: `Tests/MultiCodexTests/AccountsMenuViewModelTests.swift`

- [ ] **Step 1: Add protocol partial fetch**

Add to `CodexAccountServicing`:

```swift
func fetchLimits(
    refreshLive: Bool,
    onPartialResult: @escaping @Sendable (LimitsPayload) async -> Void
) async throws -> LimitsPayload
```

- [ ] **Step 2: Default implementation for existing service**

In `CodexAccountService`, add:

```swift
func fetchLimits(
    refreshLive: Bool,
    onPartialResult: @escaping @Sendable (LimitsPayload) async -> Void
) async throws -> LimitsPayload {
    try await Task.detached(priority: .userInitiated) {
        try fetchLimitsNow(refreshLive: refreshLive) { partial in
            Task {
                await onPartialResult(partial)
            }
        }
    }.value
}
```

- [ ] **Step 3: Add callback overload in fetcher**

Add overload:

```swift
func fetchLimitsNow(
    refreshLive: Bool,
    onPartialResult: @escaping (LimitsPayload) -> Void
) throws -> LimitsPayload {
    let payload = try fetchLimitsNow(refreshLive: refreshLive, partialSink: onPartialResult)
    return payload
}
```

Refactor existing body into:

```swift
private func fetchLimitsNow(
    refreshLive: Bool,
    partialSink: ((LimitsPayload) -> Void)?
) throws -> LimitsPayload
```

Keep existing public method:

```swift
func fetchLimitsNow(refreshLive: Bool) throws -> LimitsPayload {
    try fetchLimitsNow(refreshLive: refreshLive, partialSink: nil)
}
```

- [ ] **Step 4: Emit partial after each result**

In managed parallel completion and serial loop, after appending each result or error, call:

```swift
partialSink?(LimitsPayload(results: results, errors: errors))
```

For serial loop, emit inside the `for account in targets` loop after success or error.

- [ ] **Step 5: Use partials in refresh controller**

Replace:

```swift
let limits = try await viewModel.accountService.fetchLimits(refreshLive: refreshLive)
```

With:

```swift
let limits = try await viewModel.accountService.fetchLimits(refreshLive: refreshLive) { partial in
    await MainActor.run {
        Task { @MainActor in
            await self.applyMergedAccounts(
                accountsPayload: accountsPayload,
                limits: partial,
                previousAccounts: previousAccounts,
                recordPace: false
            )
        }
    }
}
```

Then keep final `applyMergedAccounts(... recordPace: true)` after full payload.

- [ ] **Step 6: Add test for partial paint**

In mock service, implement partial overload:

```swift
func fetchLimits(
    refreshLive: Bool,
    onPartialResult: @escaping @Sendable (LimitsPayload) async -> Void
) async throws -> LimitsPayload {
    let partial = LimitsPayload(
        results: [
            LimitsResult(
                account: "alpha",
                source: "live-api",
                snapshot: RateLimitSnapshot(
                    fiveHour: RateLimitWindow(usedPercent: 10, resetsAt: nil),
                    weekly: RateLimitWindow(usedPercent: 20, resetsAt: nil)
                ),
                ageSec: nil
            )
        ],
        errors: []
    )
    await onPartialResult(partial)
    if fetchLimitsDelayNanoseconds > 0 {
        try? await Task.sleep(nanoseconds: fetchLimitsDelayNanoseconds)
    }
    return fetchLimitsResult
}
```

Add test:

```swift
func testRefreshAppliesPartialUsageBeforeFullLimitsReturn() async {
    let service = MockCodexAccountService()
    service.accountsPayload = AccountsListPayload(
        accounts: ["alpha"],
        currentAccount: "alpha",
        authenticatedAccounts: ["alpha"]
    )
    service.fetchLimitsDelayNanoseconds = 500_000_000
    service.fetchLimitsResult = LimitsPayload(results: [], errors: [])

    let viewModel = AccountsMenuViewModel(accountService: service, startImmediately: false)
    viewModel.refreshLive()

    await fulfillment(of: [
        expectation(description: "partial usage painted") { @MainActor in
            viewModel.accounts.first?.usage.fiveHour.usedPercent == 10
        }
    ], timeout: 0.2)
}
```

- [ ] **Step 7: Run partial test**

Run:

```bash
rtk swift test --filter AccountsMenuViewModelTests/testRefreshAppliesPartialUsageBeforeFullLimitsReturn
```

Expected: PASS.

---

## Task 10: Cancellation Checks In Serial Legacy Limits

**Files:**
- Modify: `Sources/MultiCodex/Infrastructure/Codex/Usage/RateLimitsFetcher.swift`
- Modify: `Tests/MultiCodexTests/CodexAccountServiceTests.swift`

- [ ] **Step 1: Add cancellation check in serial loop**

At top of `fetchLimitsSerial` loop:

```swift
if Thread.current.isCancelled {
    break
}
```

If using Swift concurrency in refactor, prefer:

```swift
try Task.checkCancellation()
```

and change function to `throws`.

- [ ] **Step 2: Bound per-account RPC wait**

Confirm `fetchRateLimitsViaPersistentRpc()` semaphore timeout remains bounded at 35 seconds. If one-shot RPC has no timeout, add a process timeout in `runCodexCapture` or skip one-shot fallback when task is cancelled:

```swift
if Task.isCancelled {
    throw CancellationError()
}
```

- [ ] **Step 3: Add service test if feasible**

If `CodexAccountServiceTests` already has fake command runner hooks, add a test that cancels live fetch after first account and asserts second account is not fetched. If fake hooks are not present, document this as covered by view-model `refreshGeneration` tests and do not add invasive test scaffolding.

- [ ] **Step 4: Run relevant tests**

Run:

```bash
rtk swift test --filter CodexAccountServiceTests
rtk swift test --filter AccountsMenuViewModelTests
```

Expected: PASS.

---

## Task 11: Update Existing Tests For Busy-State Rename

**Files:**
- Modify: `Tests/MultiCodexTests/AccountsMenuViewModelTests.swift`

- [ ] **Step 1: Replace login expectations**

Where tests wait for browser/new login action using:

```swift
viewModel.accountActionInFlightName != nil
```

Change to:

```swift
viewModel.loginInFlightName != nil
```

- [ ] **Step 2: Keep non-login expectations unchanged**

For rename/remove/import/status tests, keep:

```swift
viewModel.accountActionInFlightName != nil
```

- [ ] **Step 3: Add assertion that login does not set global action busy**

In one login test, after login starts:

```swift
XCTAssertNotNil(viewModel.loginInFlightName)
XCTAssertNil(viewModel.accountActionInFlightName)
```

- [ ] **Step 4: Run full view-model tests**

Run:

```bash
rtk swift test --filter AccountsMenuViewModelTests
```

Expected: PASS.

---

## Task 12: Final Verification And Polish

**Files:**
- Verify all modified files.

- [ ] **Step 1: Run full check**

Run:

```bash
rtk just check
```

Expected: PASS.

- [ ] **Step 2: Run whitespace check**

Run:

```bash
rtk git diff --check
```

Expected: no output.

- [ ] **Step 3: Manual app smoke test**

Run app:

```bash
rtk just run
```

Manual checks:

- Launch app with at least 3 accounts.
- Delete or age limits cache to simulate cold start.
- Open menu immediately.
- Confirm accounts appear before live usage completes.
- Confirm cached/stale stats appear if cache exists.
- Start live refresh.
- While refresh spinner active, switch to another existing account.
- Start new account login.
- While login is active, switch to another existing account.
- Return to app after login and confirm final import/apply still works.

- [ ] **Step 4: Commit**

```bash
rtk git add Sources/MultiCodex Tests/MultiCodexTests docs/superpowers/plans/2026-05-03-startup-switch-responsiveness.md
rtk git commit -m "fix: improve startup usage and switch responsiveness"
```

Expected: commit succeeds.

---

## Risk Notes

- Partial usage updates can overwrite newer data if a stale refresh returns late. Use `refreshGeneration` checks before applying partials.
- Legacy auth swap remains the riskiest path. Do not parallelize legacy auth-swap unless a real lock/queue guarantees only one process owns `~/.codex/auth.json`.
- `authMutationInFlightName` is UI state, not a real cross-process lock. Service-level auth locking must remain inside auth swap/switch services.
- If partial callback creates nested `Task` calls, verify no MainActor ordering bug lets final empty limits erase partials.

## Implementation Note

Implemented in commit `49141e8` and earlier with generation-tracked refreshes, refresh cancellation tokens, partial limits application, and manual-mode reconciliation guard.

## Completion Criteria

- Startup account rows render before live limits complete.
- Cached usage renders within one fast refresh pass.
- Live usage updates do not wait for all accounts.
- Manual switch works during refresh.
- Manual switch works during sandboxed login.
- Auth mutations remain serialized.
- `rtk just check` passes.
- `rtk git diff --check` passes.

