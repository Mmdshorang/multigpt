# Branch Stability Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stabilize `feature/account-intelligence-managed-auth` by fixing branch-specific reliability, auth safety, RPC lifecycle, import/export security, reconciliation, and polish regressions found during audit.

**Architecture:** Keep fixes local and test-first. Prioritize destructive/auth-token safety first, then main-thread responsiveness, RPC lifecycle, reconciliation correctness, and low-risk polish. Avoid broad refactors unless needed to remove root cause.

**Tech Stack:** Swift 5.9+/Swift 6-compatible code, SwiftPM, XCTest, SwiftUI, AppKit, Foundation, UserNotifications, `just`, `scripts/swift-safe.sh`.

---

## Audit Context

Branch: `feature/account-intelligence-managed-auth`

Verification already run:

```bash
rtk just check
```

Observed result: doctor, debug build, and Swift tests passed.

Extra checks:

```bash
rtk sh -lc 'command -v swiftformat || echo swiftformat-missing; command -v swiftlint || echo swiftlint-missing; git diff --check main...HEAD; echo diff-check-exit:$?'
```

Observed result:
- `swiftformat` missing from PATH.
- `swiftlint` missing from PATH.
- `git diff --check` found trailing whitespace in `docs/ROADMAP_IMPLEMENTATION_PLAN.md`.

Risk summary:
- Build green does not mean app stable.
- Most issues are runtime-only: auth swap semantics, RPC timeouts, UI blocking, import path safety, async races, and persistence drift.
- Auth-token code touches real user data. Keep changes small, test all destructive paths with sandbox dirs.

---

## Files Map

Primary files likely modified:

- `Sources/MultiCodex/Features/Shared/AccountExportService.swift` - export/import payload handling and account-name validation.
- `Sources/MultiCodex/Features/Settings/SettingsContentView+Data.swift` - export file permissions and live preference refresh after import.
- `Sources/MultiCodex/Features/Shared/AccountsRefreshController.swift` - refresh flow, main-thread blocking, reconciliation behavior.
- `Sources/MultiCodex/Infrastructure/Codex/Runtime/CodexRPCSession.swift` - persistent JSON-RPC process lifecycle and request timeout cleanup.
- `Sources/MultiCodex/Infrastructure/Codex/Usage/RateLimitsFetcher.swift` - managed parallel refresh timeout behavior and sync semaphore wrapper.
- `Sources/MultiCodex/Infrastructure/Codex/Accounts/AuthSwapService.swift` - switch safety when target/previous auth is missing or unwritable.
- `Sources/MultiCodex/Infrastructure/Codex/Accounts/AccountsRepository.swift` - switch flow and RPC shutdown ordering.
- `Sources/MultiCodex/Infrastructure/Codex/Auth/AuthSessionCoordinator.swift` - token refresh sync to managed/legacy paths and auth mtime helpers.
- `Sources/MultiCodex/Infrastructure/Codex/Accounts/ManagedAccountMigrator.swift` - migration marker write correctness.
- `Sources/MultiCodex/Core/Accounts/AccountUsageMergeService.swift` - pace snapshot write side effects.
- `Sources/MultiCodex/Core/Usage/UsagePaceStore.swift` - shared/batched pace persistence if needed.
- `Sources/MultiCodex/Infrastructure/UpdateCheck/UpdateChecker.swift` - repo owner constant.
- `docs/ROADMAP_IMPLEMENTATION_PLAN.md` - trailing whitespace cleanup only.

Primary tests likely modified/added:

- `Tests/MultiCodexTests/AccountExportServiceTests.swift`
- `Tests/MultiCodexTests/AuthSwapServiceTests.swift`
- `Tests/MultiCodexTests/CodexRPCSessionTests.swift`
- `Tests/MultiCodexTests/CodexAccountServiceTests.swift`
- `Tests/MultiCodexTests/ManagedAccountMigratorTests.swift`
- `Tests/MultiCodexTests/AccountsMenuViewModelTests.swift`
- `Tests/MultiCodexTests/UsagePaceTests.swift`
- `Tests/MultiCodexTests/UpdateCheckerTests.swift`

Recommended commit grouping:

1. `fix(security): harden account import and export`
2. `fix(auth): make account switching fail safe`
3. `fix(rpc): clean up persistent session lifecycle`
4. `fix(refresh): prevent UI blocking and managed timeout holes`
5. `fix(accounts): persist reconciliation and pace snapshots safely`
6. `fix(update): point update checker at release repo`
7. `docs: clean roadmap whitespace`

---

## Delegation Queue

### Task 1: Harden Backup Import Against Path Traversal

**Priority:** `P0`

**Issue:** `AccountExportService.importAccounts` writes backup account names directly into filesystem paths.

**Root Cause:** `payload.accounts[*].name` is trusted without validation. Existing app account creation validates names with `validatedAccountName`, but import bypasses that guard.

**Failure Mode:** A malicious or corrupted backup can use names like `../../.codex` or `/tmp/x` and escape the intended `accounts/` directory. Because auth tokens are written with `.atomic`, this can overwrite or create sensitive files outside MultiCodex config.

**Files:**
- Modify: `Sources/MultiCodex/Features/Shared/AccountExportService.swift`
- Test: `Tests/MultiCodexTests/AccountExportServiceTests.swift`

**Proposed Solution:**
- Validate every imported account name through `accountService.validatedAccountName` before deriving paths.
- Reject if `validated != account.name` to avoid silently importing trimmed/normalized aliases.
- Add explicit error case `invalidAccountName(String)`.
- Ensure failed invalid entries do not partially write files.

**Steps:**
- [ ] Add failing test `testImportRejectsPathTraversalAccountName`.
- [ ] Run `rtk scripts/swift-safe.sh swift test --filter AccountExportServiceTests/testImportRejectsPathTraversalAccountName` and confirm fail before fix.
- [ ] Add `ExportError.invalidAccountName(String)`.
- [ ] In import loop, validate `account.name`; use validated name for all config/path work.
- [ ] Re-run `rtk scripts/swift-safe.sh swift test --filter AccountExportServiceTests`.

**Suggested test skeleton:**

```swift
func testImportRejectsPathTraversalAccountName() throws {
    let tempDir = NSTemporaryDirectory() + "mc-test-import-traversal-\(UUID().uuidString)"
    let fm = FileManager.default
    try fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(atPath: tempDir) }

    let service = CodexAccountService()
    service.sandboxHomeDirectory = (tempDir as NSString).appendingPathComponent("home")
    service.sandboxMulticodexHomeDirectory = (tempDir as NSString).appendingPathComponent("config")
    try fm.createDirectory(atPath: service.effectiveMulticodexHomePath(), withIntermediateDirectories: true)

    let payload = AccountExportService.ExportPayload(
        version: 1,
        exportedAt: "2026-05-03T00:00:00Z",
        appVersion: "0.5.0",
        accounts: [.init(name: "../../escaped", auth: Data("{}".utf8))],
        preferences: nil,
        currentAccount: nil
    )

    let exportURL = URL(fileURLWithPath: tempDir).appendingPathComponent("bad-export.json")
    try JSONEncoder().encode(payload).write(to: exportURL)
    var prefs = AppPreferencesStore(defaults: makeEphemeralDefaults())

    XCTAssertThrowsError(
        try AccountExportService.importAccounts(
            from: exportURL,
            accountService: service,
            preferencesStore: &prefs
        )
    )
    XCTAssertFalse(fm.fileExists(atPath: (tempDir as NSString).appendingPathComponent("escaped/auth.json")))
}
```

---

### Task 2: Export Managed Auth And Secure Backup File Permissions

**Priority:** `P1`

**Issue:** Export reads only legacy auth files; save panel writes exported token backup without forcing restrictive permissions.

**Root Cause:** Managed-home migration added a fresher auth source under `managed-homes`, but export still uses `paths.accountAuthPath(accountName)`. UI writes with `data.write(to:)`, which uses default umask-dependent permissions.

**Failure Mode:**
- Export can miss refreshed tokens stored only in managed home.
- Backup JSON containing auth tokens may be world/group-readable depending on environment.

**Files:**
- Modify: `Sources/MultiCodex/Features/Shared/AccountExportService.swift`
- Modify: `Sources/MultiCodex/Features/Settings/SettingsContentView+Data.swift`
- Test: `Tests/MultiCodexTests/AccountExportServiceTests.swift`

**Proposed Solution:**
- Export from `service.managedAuthPath(for:paths:) ?? paths.accountAuthPath(accountName)`.
- Add helper `writeBackupData(_:to:)` that writes atomically then sets `0o600`.
- Use helper from `DataPane.performExport`.

**Steps:**
- [ ] Add test `testExportPrefersManagedAuthWhenMigrationComplete`.
- [ ] Change export auth source to prefer managed auth.
- [ ] Add `AccountExportService.writeBackupData`.
- [ ] Replace `try data.write(to: url)` in `SettingsContentView+Data.swift`.
- [ ] Add permission test for `0o600`.
- [ ] Run `rtk scripts/swift-safe.sh swift test --filter AccountExportServiceTests`.

**Suggested helper:**

```swift
static func writeBackupData(_ data: Data, to url: URL) throws {
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: Int16(0o600))],
        ofItemAtPath: url.path
    )
}
```

---

### Task 3: Apply Imported Preferences To Live View Model

**Priority:** `P1`

**Issue:** Import writes to a copied `AppPreferencesStore`, then assigns `viewModel.preferences = prefs`; published settings remain stale.

**Root Cause:** `AccountsMenuViewModel` initializes published values from preferences once. Replacing the store object does not re-run initialization or setters.

**Failure Mode:** UI shows old sort/density/strategy until app restart. Background refresh uses stale TTL/strategy. Imported settings appear broken.

**Files:**
- Modify: `Sources/MultiCodex/Features/Shared/AccountsMenuViewModel.swift`
- Modify: `Sources/MultiCodex/Features/Settings/SettingsContentView+Data.swift`
- Test: `Tests/MultiCodexTests/AccountsMenuViewModelTests.swift` or `Tests/MultiCodexTests/AccountExportServiceTests.swift`

**Proposed Solution:**
- Add `reloadPreferencesFromStore()` on view model.
- After import, assign preferences then call reload method.
- The reload method must also propagate `customCodexPath` and `limitsCacheTTLSeconds` to `accountService`.

**Steps:**
- [ ] Add view model method to copy all persisted settings into published properties.
- [ ] Call `viewModel.reloadPreferencesFromStore()` after import.
- [ ] Add test proving imported TTL/strategy/density appear without restart.
- [ ] Run `rtk scripts/swift-safe.sh swift test --filter AccountsMenuViewModelTests`.

**Suggested method body:**

```swift
func reloadPreferencesFromStore() {
    customCodexPath = preferences.customCodexPath
    resetDisplayMode = preferences.resetDisplayMode
    selectedSettingsSection = preferences.selectedSettingsSection
    selectedSettingsAccountName = preferences.selectedSettingsAccountName
    menuDensity = preferences.menuDensity
    usageBarStyle = preferences.usageBarStyle
    accountSortCriterion = preferences.accountSortCriterion
    accountSortWindow = preferences.accountSortWindow
    accountSortDirection = preferences.accountSortDirection
    showAllAccountsInMenu = preferences.showAllAccountsInMenu
    accountSwitchingStrategy = preferences.accountSwitchingStrategy
    autoSwitchNotificationsEnabled = preferences.autoSwitchNotificationsEnabled
    limitsCacheTTLSeconds = CodexAccountService.normalizedLimitsCacheTTLSeconds(preferences.limitsCacheTTLSeconds)
    accountService.customCodexPath = customCodexPath.isEmpty ? nil : customCodexPath
    accountService.limitsCacheTTLSeconds = limitsCacheTTLSeconds
    resortAccounts()
}
```

---

### Task 4: Make Auth Swap Fail Safe When Target Auth Missing

**Priority:** `P1`

**Issue:** Switching to an account with no target auth deletes system auth.

**Root Cause:** `AuthSwapService.switchToAccount` treats missing target auth as “clear system auth” instead of error. Account switching should never silently log user out.

**Failure Mode:** User clicks switch, target auth missing/corrupt, app removes `~/.codex/auth.json`; active Codex session becomes logged out.

**Files:**
- Modify: `Sources/MultiCodex/Infrastructure/Codex/Accounts/AuthSwapService.swift`
- Test: `Tests/MultiCodexTests/AuthSwapServiceTests.swift`

**Proposed Solution:**
- Throw `AuthSwapError.authNotFound(targetName)` if target auth missing.
- Never delete system auth in account-switch path.
- Keep explicit delete behavior only in remove-last-account/logout flows.

**Steps:**
- [ ] Add failing test `testSwitchMissingTargetAuthPreservesSystemAuth`.
- [ ] Replace missing-target delete branch with `throw AuthSwapError.authNotFound(targetName)`.
- [ ] Run `rtk scripts/swift-safe.sh swift test --filter AuthSwapServiceTests`.

---

### Task 5: Make Previous Auth Preservation Mandatory

**Priority:** `P1`

**Issue:** `AuthSwapService` ignores failures while preserving displaced auth.

**Root Cause:** `try? writeAuthData(currentSystemAuth, account: previousName, paths: paths)` discards errors.

**Failure Mode:** If backup write fails, switch continues. Previous account can lose refreshed token state or become stale.

**Files:**
- Modify: `Sources/MultiCodex/Infrastructure/Codex/Accounts/AuthSwapService.swift`
- Test: `Tests/MultiCodexTests/AuthSwapServiceTests.swift`

**Proposed Solution:**
- Replace `try?` with `try`.
- If preserving displaced account fails, abort switch before touching target/system auth.
- Add test using unwritable path or invalid previous account name.

**Steps:**
- [ ] Add failing preservation-error test.
- [ ] Replace ignored write with mandatory write.
- [ ] Verify system auth remains unchanged when preservation fails.
- [ ] Run `rtk scripts/swift-safe.sh swift test --filter AuthSwapServiceTests`.

---

### Task 6: Await RPC Shutdown During Account Switch

**Priority:** `P1`

**Issue:** Account switch schedules RPC shutdown in fire-and-forget `Task`.

**Root Cause:** `switchAccountNow` is synchronous and cannot await actor shutdown, so shutdown may race later fetches.

**Failure Mode:**
- Stale persistent RPC reads usage with previous auth.
- Fire-and-forget shutdown can kill a newly initialized session.
- Account switch returns before system is stable.

**Files:**
- Modify: `Sources/MultiCodex/Infrastructure/Codex/Accounts/CodexAccountService.swift`
- Modify: `Sources/MultiCodex/Infrastructure/Codex/Accounts/AccountsRepository.swift`
- Test: `Tests/MultiCodexTests/CodexAccountServiceTests.swift` if practical.

**Proposed Solution:**
- Move shutdown to async `switchAccount(name:)`, after `switchAccountNow` succeeds.
- Remove fire-and-forget task from `switchAccountNow`.

**Steps:**
- [ ] Update async wrapper:

```swift
func switchAccount(name: String) async throws {
    _ = try switchAccountNow(name: name)
    await CodexRPCSession.shared.shutdown()
}
```

- [ ] Remove fire-and-forget shutdown block from `switchAccountNow`.
- [ ] Run `rtk scripts/swift-safe.sh swift test --filter CodexAccountServiceTests`.

---

### Task 7: Fix Persistent RPC Timeout And Shutdown Cleanup

**Priority:** `P0/P1`

**Issue:** Persistent RPC requests can timeout outside actor while actor keeps pending continuations. Shutdown also returns early if process died, leaving pending state.

**Root Cause:** Timeout lives in `RateLimitsFetcher` semaphore wrapper, not in `CodexRPCSession.request`. `shutdown()` only cleans if `process?.isRunning == true`.

**Failure Mode:**
- Memory leak / continuation leak.
- Later response resumes stale continuation.
- Process death leaves pending requests stuck.
- Session becomes poisoned after timeout.

**Files:**
- Modify: `Sources/MultiCodex/Infrastructure/Codex/Runtime/CodexRPCSession.swift`
- Modify: `Tests/MultiCodexTests/CodexRPCSessionTests.swift`

**Proposed Solution:**
- Add actor-owned timeout around each request.
- On timeout: remove pending request, resume throwing `requestTimedOut(method:)`, shutdown/restart process.
- `shutdown()` always clears state and pending requests, regardless of `isRunning`.
- Set `process.terminationHandler` to clear pending on death. Because handler is nonisolated, hop into actor with `Task`.

**Steps:**
- [ ] Add `SessionError.requestTimedOut(String)`.
- [ ] Refactor `shutdown()` to always clear state and resume pending continuations.
- [ ] Add actor-level request timeout cleanup.
- [ ] Add process termination handler.
- [ ] Add focused tests using a small test seam if needed.
- [ ] Run `rtk scripts/swift-safe.sh swift test --filter CodexRPCSessionTests`.
- [ ] Run `rtk just check`.

---

### Task 8: Prevent Main-Thread Blocking During Live Refresh

**Priority:** `P0`

**Issue:** `AccountsRefreshController.performRefresh` is `@MainActor`, but calls synchronous network/token/RPC code.

**Root Cause:** `CodexAccountService.fetchAccounts` and `fetchLimits` async methods call sync implementations directly. `refreshStaleTokens()` is sync and performs HTTP requests.

**Failure Mode:** Menu bar window freezes for up to many seconds during live refresh. With multiple accounts, freeze can compound. User perceives app as buggy/hung.

**Files:**
- Modify: `Sources/MultiCodex/Infrastructure/Codex/Accounts/CodexAccountService.swift`
- Modify: `Sources/MultiCodex/Features/Shared/AccountsRefreshController.swift`
- Modify: `Sources/MultiCodex/Infrastructure/Codex/Accounts/CodexAccountServicing.swift`
- Test: `Tests/MultiCodexTests/AccountsMenuViewModelTests.swift`

**Proposed Solution:**
- Offload sync service methods to detached/background tasks inside service async wrappers.
- Make token refresh async or run in background before returning to main actor.
- Only mutate view model on main actor.

**Steps:**
- [ ] Change heavy async wrappers to background tasks:

```swift
func fetchLimits(refreshLive: Bool) async throws -> LimitsPayload {
    try await Task.detached(priority: .userInitiated) { [self] in
        try fetchLimitsNow(refreshLive: refreshLive)
    }.value
}
```

- [ ] Rename current sync `refreshStaleTokens()` to `refreshStaleTokensNow()`.
- [ ] Add async protocol method `func refreshStaleTokens() async -> [String: Error]`.
- [ ] Await token refresh from controller.
- [ ] Update mocks.
- [ ] Run `rtk scripts/swift-safe.sh swift test --filter AccountsMenuViewModelTests`.
- [ ] Run `rtk just check`.

---

### Task 9: Return Timeout Errors For Managed Parallel Refresh

**Priority:** `P0`

**Issue:** Managed parallel refresh waits 60s and returns partial data without reporting accounts that timed out.

**Root Cause:** `DispatchGroup.wait(timeout:)` return value is ignored. Background workers continue after caller returns.

**Failure Mode:** Accounts silently keep stale usage. Late workers can write cache after refresh completed. Debugging becomes misleading because refresh reports fewer errors than actually happened.

**Files:**
- Modify: `Sources/MultiCodex/Infrastructure/Codex/Usage/RateLimitsFetcher.swift`
- Test: `Tests/MultiCodexTests/CodexAccountServiceTests.swift` or new `Tests/MultiCodexTests/RateLimitsFetcherTests.swift`

**Proposed Solution:**
- Best: replace `DispatchGroup` with async task group and per-account timeout.
- Minimum safe fix: track completed accounts; if wait times out, return `LimitsErrorEntry` for missing accounts and prevent late mutation of returned arrays.

**Steps:**
- [ ] Track completed accounts under lock.
- [ ] Check wait result.
- [ ] Add timeout errors for accounts that did not finish.
- [ ] Add guard preventing late worker append after timeout.
- [ ] Add test with injected slow managed fetch if test seam exists; otherwise create minimal seam.
- [ ] Run `rtk scripts/swift-safe.sh swift test --filter CodexAccountServiceTests`.

---

### Task 10: Persist Account Reconciliation Or Downgrade To Warning

**Priority:** `P1`

**Issue:** Reconciliation changes only local UI current account; config remains unchanged.

**Root Cause:** `performReconciliation` calls `viewModel.applyCurrentAccountLocally(named:)` but does not update `config.currentAccount`.

**Failure Mode:** UI can show detected account, then next refresh reloads old config and flips back. Auto-switch logic may make decisions from inconsistent state.

**Files:**
- Modify: `Sources/MultiCodex/Features/Shared/AccountsRefreshController.swift`
- Maybe modify: `Sources/MultiCodex/Infrastructure/Codex/Accounts/CodexAccountService.swift`
- Maybe modify: `Sources/MultiCodex/Infrastructure/Codex/Accounts/CodexAccountServicing.swift`
- Test: `Tests/MultiCodexTests/AccountsMenuViewModelTests.swift` or `Tests/MultiCodexTests/AccountReconciliationTests.swift`

**Proposed Solution:** Choose one policy:
- Recommended: persist known detected account. If system identity maps to known account, update config `currentAccount`, then call local apply.
- Alternative: warning-only. Do not call local apply; tell user system auth does not match config.

**Steps:**
- [ ] Add service method `persistCurrentAccountIfKnown(_:)`.
- [ ] Expose through protocol if controller needs it.
- [ ] In reconciliation, persist detected known account before local UI update.
- [ ] On persist failure, set `refreshWarningMessage`.
- [ ] Add regression test proving config and UI converge.
- [ ] Run `rtk scripts/swift-safe.sh swift test --filter AccountsMenuViewModelTests`.

---

### Task 11: Pass Known Account Modified Time To Reconciliation

**Priority:** `P1`

**Issue:** External-change detection is disabled because `knownAccountLastModified` is always nil.

**Root Cause:** Controller computes system auth mtime but never computes active account stored auth mtime.

**Failure Mode:** Logs say external modification is unknown/no even when user changed `~/.codex/auth.json` outside app. Useful diagnosis lost.

**Files:**
- Modify: `Sources/MultiCodex/Features/Shared/AccountsRefreshController.swift`
- Maybe modify: `Sources/MultiCodex/Infrastructure/Codex/Auth/AuthSessionCoordinator.swift`
- Test: `Tests/MultiCodexTests/AccountReconciliationTests.swift`

**Proposed Solution:**
- For `accountsPayload.currentAccount`, compute mtime of `managedAuthPath(for:) ?? accountAuthPath`.
- Pass it to `AccountReconciliation.reconcile`.

**Steps:**
- [ ] Add helper `storedAuthModifiedDate(for:paths:)`.
- [ ] Pass helper result as `knownAccountLastModified`.
- [ ] Add pure reconciliation test for newer system auth.
- [ ] Run `rtk scripts/swift-safe.sh swift test --filter AccountReconciliationTests`.

---

### Task 12: Remove Pace Snapshot Race From Merge Service

**Priority:** `P1`

**Issue:** `AccountUsageMergeService.mergeAccounts` creates one `UsagePaceStore` per account and launches fire-and-forget write tasks.

**Root Cause:** Pure merge logic performs side effects. Multiple actors load same file, append independently, and persist over each other.

**Failure Mode:** Historical pace data randomly lost. File writes race. Tests may be flaky. Merge results depend on hidden async work.

**Files:**
- Modify: `Sources/MultiCodex/Core/Accounts/AccountUsageMergeService.swift`
- Modify: `Sources/MultiCodex/Features/Shared/AccountsRefreshController.swift`
- Maybe modify: `Sources/MultiCodex/Core/Usage/UsagePaceStore.swift`
- Test: `Tests/MultiCodexTests/UsagePaceTests.swift` or `Tests/MultiCodexTests/AccountsMenuViewModelTests.swift`

**Proposed Solution:**
- Make merge pure: compute account usage only.
- Move recording to refresh controller after `viewModel.updateAccounts` using one shared `UsagePaceStore` instance.
- Batch record all accounts in one actor call.

**Steps:**
- [ ] Add `UsagePaceStore.record(accounts:)` batch method.
- [ ] Add shared `usagePaceStore` to view model or refresh controller.
- [ ] Remove lines that create `UsagePaceStore()` from merge service.
- [ ] Record once after merged accounts are known.
- [ ] Run `rtk scripts/swift-safe.sh swift test --filter UsagePaceTests`.
- [ ] Run `rtk just check`.

---

### Task 13: Fix Managed Migration Marker Writes

**Priority:** `P2`

**Issue:** Migration marker writes use `try?`, so failure is silently ignored.

**Root Cause:** `ManagedAccountMigrator.migrateIfNeeded` suppresses marker write failures.

**Failure Mode:** Migration can rerun every launch. Users see repeated logs. Managed auth may be repeatedly overwritten from stale legacy auth.

**Files:**
- Modify: `Sources/MultiCodex/Infrastructure/Codex/Accounts/ManagedAccountMigrator.swift`
- Test: `Tests/MultiCodexTests/ManagedAccountMigratorTests.swift`

**Proposed Solution:**
- Ensure `paths.multicodexHome` exists before marker write.
- Use `try` for marker write.
- If marker write fails, surface error; do not pretend migration complete.

**Steps:**
- [ ] Replace `try? Data().write(to: markerURL)` with explicit directory creation and `try`.
- [ ] Replace final marker `try?` with `try`.
- [ ] Add test where config dir initially missing and marker is created.
- [ ] Run `rtk scripts/swift-safe.sh swift test --filter ManagedAccountMigratorTests`.

---

### Task 14: Correct Update Checker Repository

**Priority:** `P2`

**Issue:** Update checker points at `mohamadhosein/multicodex`, while README/About/release links use `momoazn/multicodex`.

**Root Cause:** Roadmap placeholder was copied into implementation without replacing owner.

**Failure Mode:** Update check misses releases, checks wrong repo, or fails silently.

**Files:**
- Modify: `Sources/MultiCodex/Infrastructure/UpdateCheck/UpdateChecker.swift`
- Test: `Tests/MultiCodexTests/UpdateCheckerTests.swift`

**Proposed Solution:**
- Change constant to `momoazn/multicodex`.
- Add test asserting constant.

**Steps:**
- [ ] Add test `testRepositoryMatchesPublicReleaseRepository`.
- [ ] Change `static let repository = "momoazn/multicodex"`.
- [ ] Run `rtk scripts/swift-safe.sh swift test --filter UpdateCheckerTests`.

---

### Task 15: Clean Branch Whitespace And Tooling Gap

**Priority:** `P3`

**Issue:** `git diff --check main...HEAD` reports trailing whitespace in `docs/ROADMAP_IMPLEMENTATION_PLAN.md`. `swiftformat` and `swiftlint` are missing in current PATH.

**Root Cause:** Docs contain markdown hard-break spaces. Tooling installed assumptions not guaranteed.

**Failure Mode:** CI or pre-merge checks can fail. Local developer cannot run advertised format/lint commands.

**Files:**
- Modify: `docs/ROADMAP_IMPLEMENTATION_PLAN.md`
- Maybe modify: `docs/DEVELOPMENT.md` or `justfile` only if project wants bootstrap instructions.

**Proposed Solution:**
- Remove trailing spaces reported by `git diff --check`.
- Do not rewrite entire roadmap doc.
- Document missing local tools in final handoff; install/setup is environment-specific unless user asks.

**Steps:**
- [ ] Remove trailing whitespace only:

```bash
rtk perl -pi -e 's/[ \t]+$//' docs/ROADMAP_IMPLEMENTATION_PLAN.md
```

- [ ] Re-run:

```bash
rtk git diff --check main...HEAD
```

Expected: no output, exit 0.

---

## Verification Gate

After all tasks:

```bash
rtk git status --short
rtk scripts/swift-safe.sh swift build -c debug
rtk scripts/swift-safe.sh swift test
rtk just check
rtk git diff --check main...HEAD
```

If `swiftformat` and `swiftlint` are installed later:

```bash
rtk swiftformat --lint .
rtk swiftlint lint --quiet
```

Manual smoke tests:

- Launch app with two sandbox accounts.
- Switch current account; verify `~/.codex/auth.json` changes only when target auth exists.
- Attempt switch to account missing auth; verify current auth remains intact and UI shows error.
- Run live refresh with several accounts; verify menu remains responsive.
- Export backup; verify file perms are `600`.
- Import backup into empty sandbox; verify accounts and preferences show immediately without restart.
- Externally replace system auth with known account auth; refresh; verify config/current account converge.
- Kill/stall Codex RPC process during refresh; verify refresh returns warning, later refresh recovers.

---

## Execution Notes For Delegation

- Do not combine unrelated tasks in one worker unless files overlap tightly.
- Do not edit real `~/.codex/auth.json` during tests. Use `sandboxHomeDirectory` and `sandboxMulticodexHomeDirectory`.
- Never use destructive git commands.
- Before each worker edits, run:

```bash
rtk git status --short
```

- Every worker final response must list changed files and tests run.
- If a worker sees unexpected dirty changes, stop and ask coordinator.
