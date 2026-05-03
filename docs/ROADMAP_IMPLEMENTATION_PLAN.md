# MultiCodex Roadmap Implementation Plan

This plan turns `docs/ROADMAP.md` into an execution-ready backlog with dependencies, acceptance criteria, verification gates, and recommended sequencing.

## Goals

- Deliver roadmap features safely in small, reviewable increments.
- Preserve current UX while improving reliability, observability, and refresh performance.
- Keep each phase releasable independently.
- Add tests alongside each feature.

## Non-Goals for Initial Execution

- No broad architecture rewrite before Phase 1–3 foundations are in place.
- No removal of legacy auth-swap behavior until managed homes are migrated and verified.
- No commits, pushes, or release tagging unless explicitly requested.

## Execution Strategy

Use one branch or working series per phase, with smaller internal checkpoints. Each checkpoint should build and pass tests before continuing.

Recommended command gate after each checkpoint:

```bash
just check
```

If full `just check` is too slow during iteration, use:
r
```bash
swift test
scripts/swift-safe.sh build
```

## Phase 1 — Foundation

**Target effort:** ~14 hours
**Release readiness:** Safe for v0.5.0-alpha or patch/minor release.
**Primary value:** Debuggability, better usage recovery, reliable identity parsing, user notifications.

### 1.1 Structured Logging

#### Files

Create:

- `Sources/MultiCodex/Infrastructure/Logging/MultiCodexLog.swift`
- `Sources/MultiCodex/Infrastructure/Logging/LogRedactor.swift`
- `Sources/MultiCodex/Infrastructure/Logging/LogCategories.swift`

Add tests:

- `Tests/MultiCodexTests/LogRedactorTests.swift`

#### Implementation Steps

1. Add `MultiCodexLog.Category` enum.
2. Add `MultiCodexLog.logger(_:)` and `MultiCodexLog.log(...)`.
3. Add rotating `FileLogHandler` writing to `~/Library/Logs/MultiCodex/multicodex.log`.
4. Add PII redaction for:
   - emails
   - bearer tokens
   - `access_token`-like fields
5. Integrate low-risk log calls in:
   - refresh start/end/errors
   - account switch start/end/errors
   - usage fetch errors
   - recommendation decisions

#### Acceptance Criteria

- Logs are written to OSLog and file.
- Log file directory is created automatically.
- File log rotates near 1 MB.
- Emails and bearer/access tokens are redacted.
- Logging never crashes the app.

#### Verification

- `swift test --filter LogRedactorTests`
- Manual: trigger refresh and confirm log file exists.

---

### 1.2 Error Body Recovery from RPC

#### Files

Modify:

- `Sources/MultiCodex/Infrastructure/Codex/Usage/RateLimitsFetcher.swift`

Add tests:

- `Tests/MultiCodexTests/ErrorRecoveryTests.swift`

#### Implementation Steps

1. Locate current RPC error handling path.
2. Add JSON object extraction helper for `body=` payloads.
3. Add recovery parser that converts error-body rate limit JSON into `RateLimitSnapshot`.
4. On RPC error:
   - attempt recovery first
   - return recovered snapshot when available
   - otherwise throw existing error
5. Log successful recovery with redacted metadata.

#### Acceptance Criteria

- Rate limit snapshot can be recovered from a representative RPC error body.
- Nested JSON and escaped strings are handled.
- Existing error behavior remains unchanged when recovery fails.
- No PII leaks to logs.

#### Verification

- `swift test --filter ErrorRecoveryTests`
- Manual: simulate/mocked RPC error body with `rate_limit` payload.

---

### 1.3 Session Quota Transition Notifications

#### Files

Create:

- `Sources/MultiCodex/Core/Accounts/QuotaTransitionDetector.swift`
- `Sources/MultiCodex/Infrastructure/Notifications/QuotaTransitionNotificationCenter.swift`

Modify:

- `Sources/MultiCodex/Features/Shared/AccountsRefreshController.swift`
- `Sources/MultiCodex/Infrastructure/Preferences/AppPreferencesStore.swift`
- Settings UI if adding a separate toggle from auto-switch notifications

Add tests:

- `Tests/MultiCodexTests/QuotaTransitionDetectorTests.swift`

#### Implementation Steps

1. Implement detector comparing previous/current `AccountUsage` arrays.
2. Track transitions for:
   - 5h depleted
   - 5h restored
   - weekly depleted
   - weekly restored
3. Add notification poster using `UNUserNotificationCenter`.
4. Hook into refresh after account usage merge.
5. Gate notifications behind preference:
   - either reuse `autoSwitchNotificationsEnabled`
   - or add `quotaTransitionNotificationsEnabled`
6. Add settings text/toggle if using a dedicated preference.

#### Acceptance Criteria

- No notification on first refresh with no previous state.
- Notification fires only on transition, not repeatedly while still depleted/restored.
- Works per account and per quota window.
- Disabled when notification preference is off.

#### Verification

- `swift test --filter QuotaTransitionDetectorTests`
- Manual: use mocked account state or tests to validate transitions.

---

### 1.4 JWT-Based Account Identity

#### Files

Modify:

- `Sources/MultiCodex/Infrastructure/Codex/Accounts/AccountIdentityResolver.swift`

Possibly create if useful:

- `Sources/MultiCodex/Core/Accounts/ResolvedAccountIdentity.swift`

Add tests:

- `Tests/MultiCodexTests/JWTIdentityTests.swift`

#### Implementation Steps

1. Inspect existing `AccountIdentityResolver` API and models.
2. Add JWT payload parser with Base64URL decoding.
3. Extract:
   - email
   - plan type
   - provider/account ID
   - auth method (`oauth` or `apiKey`)
4. Integrate into current resolution path without breaking existing behavior.
5. Log only non-sensitive booleans/plan metadata.

#### Acceptance Criteria

- Parses standard JWT payloads.
- Handles missing/invalid JWT gracefully.
- API-key auth is recognized.
- Existing account flows still work.

#### Verification

- `swift test --filter JWTIdentityTests`
- Manual: import/read a sample `auth.json` and confirm identity fields.

---

## Phase 1 Delivery Gate

Before moving to Phase 2:

```bash
just check
```

Required outcomes:

- New tests pass.
- Existing tests pass.
- App builds.
- Manual refresh still works.
- No auth switching behavior changed except safer logging/recovery.

---

## Phase 2 — Usage Intelligence

**Target effort:** ~12 hours
**Depends on:** Phase 1 logging.
**Primary value:** Predictive auto-switching based on burn rate.

### 2.1 Usage Pace Prediction

#### Files

Create:

- `Sources/MultiCodex/Core/Usage/UsagePace.swift`
- `Sources/MultiCodex/Core/Usage/UsagePaceStore.swift`
- `Sources/MultiCodex/Core/Usage/UsageFormatter+Pace.swift`

Modify:

- `Sources/MultiCodex/Core/Usage/UsageModels.swift`
- refresh/merge path where `AccountUsage` is constructed

Add tests:

- `Tests/MultiCodexTests/UsagePaceTests.swift`

#### Implementation Steps

1. Add pure `UsagePace.compute(...)` logic first.
2. Add formatter/display helpers.
3. Add optional pace fields to `AccountUsage`.
4. Compute pace during merge/refresh.
5. Add `UsagePaceStore` actor after pure computation tests pass.
6. Record snapshots during refresh when usage data is valid.

#### Acceptance Criteria

- Pace classification is deterministic and tested.
- Handles missing reset/usage data with `nil`.
- Does not block refresh on store write errors.
- Does not create unbounded history.

---

### 2.2 Pace-Aware Auto-Switching

#### Files

Modify:

- `Sources/MultiCodex/Core/Accounts/AccountUIStateModels.swift` or wherever `AccountSwitchingStrategy` lives
- `Sources/MultiCodex/Core/Accounts/AccountSwitchRecommendationService.swift`
- `Sources/MultiCodex/Infrastructure/Preferences/AppPreferencesStore.swift`
- `Sources/MultiCodex/Features/Settings/...` strategy picker views

Add tests:

- `Tests/MultiCodexTests/PaceAwareRecommendationTests.swift`

#### Implementation Steps

1. Add `.paceAware` strategy case.
2. Add title/description and settings bindings.
3. Extend scoring with pace bonuses/penalties.
4. Generate human-readable recommendation reasons.
5. Keep existing `.expiryAware` behavior unchanged.

#### Acceptance Criteria

- Existing strategies preserve test behavior.
- `.paceAware` switches only when candidate margin is meaningful.
- Accounts without pace data still score safely using fallback logic.

---

## Phase 3 — Resilience

**Target effort:** ~9 hours
**Depends on:** Phase 1 JWT identity.
**Primary value:** Stay logged in and detect external auth changes.

### 3.1 Token Auto-Refresh

#### Files

Modify:

- `Sources/MultiCodex/Infrastructure/Codex/Usage/RateLimitsUsageAPI.swift`
- `Sources/MultiCodex/Features/Shared/AccountsRefreshController.swift`

Add tests:

- `Tests/MultiCodexTests/TokenRefreshTests.swift`

#### Implementation Steps

1. Inspect existing token refresh helpers.
2. Add `refreshStaleTokens()` service method.
3. Use conservative threshold matching roadmap (8 days) or existing token expiry data.
4. Call before live refresh only.
5. Log refresh success/failure per account.

#### Acceptance Criteria

- Cached refreshes do not trigger token refresh.
- Failed token refresh is non-fatal for other accounts.
- Errors are surfaced/logged without exposing tokens.

---

### 3.2 Account Reconciliation

#### Files

Create:

- `Sources/MultiCodex/Core/Accounts/AccountReconciliation.swift`

Modify:

- refresh/app activation path in `AccountsRefreshController` or app delegate
- account service if additional metadata access is needed

Add tests:

- `Tests/MultiCodexTests/AccountReconciliationTests.swift`

#### Implementation Steps

1. Add pure reconciliation model and tests.
2. Resolve live system auth identity via JWT parser.
3. Compare config current account with detected live account.
4. If known account: update local current marker safely.
5. If unknown account: surface non-blocking warning.
6. Avoid destructive writes in first implementation.

#### Acceptance Criteria

- External login to known account is detected.
- Unknown external login is reported but not overwritten.
- No account auth data is deleted or replaced.

---

## Phase 4 — Managed Homes Architecture

**Target effort:** ~40 hours
**Depends on:** Phase 3 preferred.
**Primary value:** Crash-safe auth, parallel fetches, faster refresh, future persistent RPC.

### Recommended Sub-Phases

#### 4A — Managed Home Scaffolding and Migration

Create:

- `ManagedCodexHomeFactory.swift`
- `ManagedAccountStore.swift` if needed by actual config model
- `ManagedAccountMigrator.swift`

Acceptance:

- Legacy accounts copied into managed homes non-destructively.
- Migration is idempotent.
- No behavior switch yet.

#### 4B — Atomic Auth Switch Service

Create:

- `AuthSwapService.swift`

Acceptance:

- Switch uses staged file + POSIX rename.
- Previous auth preservation works.
- Existing switch UI uses new atomic implementation.

#### 4C — Managed Reads for Usage Fetch

Modify usage fetcher to read/fetch through account managed home where possible.

Acceptance:

- Usage fetch no longer requires replacing system auth for migrated accounts.
- Legacy fallback still works.

#### 4D — Parallel Fetching

Modify:

- `RateLimitsFetcher.swift`

Acceptance:

- Multiple accounts fetch concurrently using scoped `CODEX_HOME`.
- One account failure does not fail entire payload.
- Cache semantics unchanged.

#### 4E — Robust Identity Model

Create:

- `Sources/MultiCodex/Core/Accounts/AccountIdentity.swift`

Acceptance:

- Provider account ID stored/matched where available.
- Email fallback remains supported.

#### 4F — Persistent RPC Session

Create:

- `Sources/MultiCodex/Infrastructure/Codex/Runtime/CodexRPCSession.swift`

Acceptance:

- Current account refresh can reuse persistent process.
- Process restarts when scoped home changes or process dies.
- Fallback one-shot RPC remains available.

### Phase 4 Risk Controls

- Keep legacy auth directories until at least one release after migration.
- Add feature flag/preference or internal fallback for managed homes if practical.
- Never delete auth data as part of migration.
- Add extensive tests for path safety and atomic switch behavior.

---

## Phase 5 — Value Add

**Target effort:** ~36 hours
**Depends on:** Phase 2 for pace-related UI; Phase 4 preferred for export/import managed-home support.

Recommended order:

1. **5.3 Credits Balance Tracking** — small, useful, low-risk.
2. **5.4 Account Health Summary** — pure UI/model, moderate impact.
3. **5.2 Dynamic Menu Bar Icon** — user-visible polish.
4. **5.5 Version Check** — isolated infrastructure.
5. **5.6 Export/Import** — important but sensitive; do after managed homes are stable.
6. **5.1 Cost Tracking** — larger parser/scanner feature.

### Phase 5 Acceptance Gate

- Export/import has clear warning that auth tokens are included.
- Cost scanner never blocks UI refresh.
- Update check is timeout-bounded and failure-silent.

---

## Phase 6 — UI Polish

**Target effort:** ~8 hours

Implement after backing data exists:

- Pace display in expanded account rows.
- Cost display in expanded account rows.
- Health summary section in menu.
- Optional settings refinements for notification/strategy toggles.

Acceptance:

- No layout regressions in compact/comfortable densities.
- Missing data is hidden gracefully.
- Existing row interactions are unchanged.

---

## Testing Plan

Add tests incrementally:

| Feature | Test File |
|---|---|
| Logging redaction | `LogRedactorTests.swift` |
| RPC error recovery | `ErrorRecoveryTests.swift` |
| Quota transitions | `QuotaTransitionDetectorTests.swift` |
| JWT identity | `JWTIdentityTests.swift` |
| Pace computation | `UsagePaceTests.swift` |
| Pace-aware switching | `PaceAwareRecommendationTests.swift` |
| Token refresh | `TokenRefreshTests.swift` |
| Reconciliation | `AccountReconciliationTests.swift` |
| Managed homes | `ManagedHomeFactoryTests.swift` |
| Atomic auth swap | `AuthSwapServiceTests.swift` |
| Migration | `ManagedAccountMigratorTests.swift` |
| Account identity model | `AccountIdentityTests.swift` |
| RPC session | `CodexRPCSessionTests.swift` |
| Cost pricing/scanning | `CostPricingTests.swift`, `CostScannerTests.swift` |
| Export/import | `AccountExportServiceTests.swift` |
| Update checker | `UpdateCheckerTests.swift` |

## Manual QA Checklist

Run after each phase:

- App launches as menu-bar-only app.
- Accounts list loads.
- Current account is pinned first.
- Refresh works with cached and live data.
- Account switch works.
- Login/relogin actions still work.
- Settings open via menu and `⌘,`.
- Refresh via `⌘R` works.
- Preferences persist after app restart.
- Notifications request/use authorization correctly.

## Release Milestones

### Milestone A — Foundation Release

Includes Phase 1.

Version suggestion: `v0.5.0-alpha.1` or `v0.5.0` if stable.

### Milestone B — Intelligence Release

Includes Phase 2 and Phase 3.

Version suggestion: `v0.5.0` or `v0.6.0` depending on semver policy.

### Milestone C — Architecture Release

Includes Phase 4 managed homes and parallel fetch.

Version suggestion: minor release due to behavior/storage changes.

### Milestone D — Value/UI Release

Includes Phase 5 and 6.

Version suggestion: minor release.

## Immediate Next Actions

1. Implement Phase 1.1 logging infrastructure.
2. Add `LogRedactorTests`.
3. Integrate minimal logging into refresh and account switch paths.
4. Run `just check`.
5. Continue to Phase 1.2 RPC error recovery.

## Ready Criteria

This plan is ready for implementation when:

- [x] Roadmap has been reviewed.
- [x] Dependencies are identified.
- [x] Phase order is defined.
- [x] Acceptance criteria are listed.
- [x] Tests are mapped to features.
- [x] Verification gates are defined.
- [ ] Implementation begins with Phase 1.1.
