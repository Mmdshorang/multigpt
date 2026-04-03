# Plan: Comprehensive Refactor, Reorganization, and Simplification

Status: Finalized plan approved for implementation sequencing. This plan reflects the review answers captured in chat.

## Why do this before multi-agent support

Before adding support for more coding agents like pi, the current codebase would benefit from a cleanup pass.

Right now, the app works and the tests pass, but the code is already showing signs that adding a second agent implementation will make things significantly harder:

- major flows are tightly coupled to **Codex-specific** behavior
- some files are becoming too large and multi-purpose
- view-model and UI logic are carrying too many responsibilities
- implementation details are split across many extension files, which reduces local clarity
- there are a few debug/legacy/compatibility paths that increase mental overhead

A deliberate refactor first should make the later multi-agent work:
- safer
- easier to reason about
- easier to test
- less likely to accrete more conditional complexity

---

## Deep analysis summary

I reviewed the project structure, key runtime/auth/storage flows, and test distribution.

## Current shape of the codebase

### Package structure

The app is a single SwiftPM executable target:

- `Package.swift`
- one target: `MultiCodex`

This is fine at the package level, but inside the target there is already substantial complexity concentrated in a few files.

### Approximate code size

Swift LOC totals from the repo:

- total Swift LOC: **~8.2k**
- `Sources/MultiCodex/Features`: **3277 LOC**
- `Sources/MultiCodex/Infrastructure`: **2311 LOC**
- `Sources/MultiCodex/Core`: **1026 LOC**
- tests total: concentrated heavily in a few files

### Biggest hotspots

Largest files include:

- `Tests/MultiCodexTests/AccountsMenuViewModelTests.swift` — **934 LOC**
- `Sources/MultiCodex/Features/Shared/AccountsMenuViewModel.swift` — **581 LOC**
- `Sources/MultiCodex/Features/Settings/SettingsContentView+DashboardAccounts.swift` — **439 LOC**
- `Sources/MultiCodex/Infrastructure/Accounts/RateLimitsUsageAPI.swift` — **435 LOC**
- `Sources/MultiCodex/Features/MenuBar/AccountsMenuContentView+Sections.swift` — **394 LOC**
- `Sources/MultiCodex/Features/Settings/SettingsContentView+RuntimeAdvanced.swift` — **344 LOC**
- `Sources/MultiCodex/Infrastructure/Accounts/AuthSessionCoordinator.swift` — **315 LOC**
- `Sources/MultiCodex/Infrastructure/Accounts/RateLimitsFetcher.swift` — **264 LOC**
- `Sources/MultiCodex/Features/Shared/AccountActionCoordinator.swift` — **257 LOC**
- `Sources/MultiCodex/Infrastructure/Accounts/CodexAccountService.swift` — **249 LOC**

### Test concentration

Tests are currently dominated by a single class:

- `AccountsMenuViewModelTests.swift` — **934 LOC**
- next largest service test file: `CodexAccountServiceTests.swift` — **295 LOC**

This strongly suggests too much behavior is centralized in the view model.

---

## Key architectural findings

## 1. `AccountsMenuViewModel` is carrying too much responsibility

The view model currently owns a wide range of concerns:

- refresh orchestration
- auto-switch logic triggering
- onboarding flow state
- runtime probe state
- user feedback/toasts
- account CRUD orchestration
- login flow orchestration
- temporary auth sandbox toggling
- settings persistence wiring
- notification triggering
- selected/focused UI state

Even though some behavior is split into extension files like:
- `RefreshCoordinator.swift`
- `SandboxCoordinator.swift`
- `AccountActionCoordinator.swift`

those are still extensions on the same large type and share the same mutable state.

### Why this matters

This makes the view model:
- hard to reason about
- hard to safely extend
- expensive to test
- a bottleneck for future architecture changes

### Strong signal

The fact that the view model has the largest production test file by far is a sign it is doing orchestration plus domain logic plus state shaping.

---

## 2. Codex service boundaries are too broad and blurred

`CodexAccountService` is conceptually one service, but in practice it contains or coordinates all of these concerns:

- account config persistence
- account metadata persistence
- auth lock coordination
- auth swapping between account and default auth location
- runtime detection
- process execution
- terminal login command construction
- login orchestration
- status checks
- limits cache management
- usage API token refresh and parsing
- RPC fallback for rate limits

This behavior is distributed across several files:

- `CodexAccountService.swift`
- `AccountsRepository.swift`
- `AuthSessionCoordinator.swift`
- `RuntimeCommandService.swift`
- `RateLimitsFetcher.swift`
- `RateLimitsUsageAPI.swift`

### Why this matters

The split gives the appearance of separation, but most of the code still revolves around one service type and one mutable state bag. This makes it harder to identify true boundaries.

### Example smell

The protocol `CodexAccountServicing` exposes a Codex-specific API and even returns:
- `CodexAccountService.RuntimeProbe`

So the abstraction boundary is not neutral even within the existing app.

---

## 3. The codebase has both under-modularization and over-fragmentation

This is an important nuance.

### Under-modularized

Large units like the view model and Codex service own too much behavior.

### Over-fragmented

At the same time, there are many small extension files and coordinator marker enums like:
- `private enum RefreshCoordinator {}`
- `private enum SandboxCoordinator {}`
- `private enum AccountActionCoordinator {}`

These files reduce file length, but do not meaningfully reduce coupling because they all mutate the same object.

### Result

The code is split across many files for navigation purposes, but not split along strong architectural seams.

That means:
- you still need to understand the giant object
- but now you have to jump through more files to do it

---

## 4. UI files are also becoming too large and stateful

Several UI files are substantial:

- `SettingsContentView+DashboardAccounts.swift` — 439 LOC
- `SettingsContentView+RuntimeAdvanced.swift` — 344 LOC
- `AccountsMenuContentView+Sections.swift` — 394 LOC

This suggests that some presentation logic, data shaping, and interaction logic is living too close to the views.

### Symptoms

- multiple pages/sections with lots of branching
- heavy dependence on `AccountsMenuViewModel`
- custom binding helpers and UI-specific state synchronization
- feature toggles like advanced mode woven through view and view model

This is workable now, but it will get harder to maintain as more agent types or settings are added.

---

## 5. There is visible duplication in orchestration logic

A few repeated patterns stand out:

### Repeated account remapping after switch

Both manual switch and auto-switch rebuild `accounts` arrays by mapping all entries and toggling `isCurrent`.

### Repeated focus / selection synchronization

Several refresh and account mutation paths repeat:
- clearing invalid focused account
- syncing selected settings account

### Repeated refresh merge flow

`performRefresh()` merges accounts once before limits arrive, then again after limits arrive, with repeated cleanup logic in both places.

### Repeated feedback plumbing

Success and failure feedback handling is repeated across account actions and interactive login paths.

### Why this matters

This duplication is not huge by itself, but it makes behavior drift more likely over time.

---

## 6. Some implementation paths are more complex than their value justifies

A few areas look heavier than necessary for current scope.

### Temporary auth sandbox

There is a debug/test-only temporary auth sandbox flow that touches:
- preferences
- view model state
- service environment
- settings UI
- tests

Relevant areas:
- `SandboxCoordinator.swift`
- advanced settings UI
- `AppPreferencesStore`
- view model toggles and helpers

This may be useful for testing, but it increases production complexity for a feature that is debug-scoped.

### Advanced settings visibility mechanics

The app has state and persistence around whether advanced settings are shown, plus protection around landing on hidden advanced tabs.

This is not wrong, but it is more moving parts for a relatively small feature.

### Onboarding state machine in main view model

Onboarding itself is simple, but its logic currently lives directly in the view model and participates in refresh behavior and settings/dashboard UX.

This is another responsibility that can likely be isolated or simplified.

---

## 7. Some compatibility and legacy concerns still leak into mainline code

I found at least one explicit compatibility note:

- `customCodexPath` is kept for backward compatibility with an existing settings key

Also:
- `AccountConfigStore` deliberately rejects legacy version 1 config and only handles schema version 2

This is not necessarily a problem, but it means the codebase is carrying some migration/compatibility shape already.

### Recommendation

We should explicitly decide what compatibility we still want to preserve and what can be migrated once and simplified.

---

## 8. Usage/rate-limit infrastructure is fairly intricate and should be isolated better

The usage path includes:
- auth payload loading
- token refresh
- HTTP requests
- response parsing
- header parsing
- error code interpretation
- RPC fallback via a spawned Codex app-server process
- cache TTL logic

Files involved:
- `RateLimitsUsageAPI.swift`
- `RateLimitsFetcher.swift`
- `UsageAPIClient.swift`
- `LimitsCacheStore.swift`
- `RateLimitsRPCClient.swift`

This is valid complexity, but it is a lot of protocol-specific machinery to keep adjacent to general account management.

This area should probably become a more clearly isolated subsystem.

---

## 9. Data model naming and layering are not as crisp as they could be

There are many small payload and view-state types:
- `AccountsListPayload`
- `SwitchAccountPayload`
- `ImportAccountPayload`
- `AccountStatusPayload`
- `AccountUsage`
- `AccountRowState`
- `MenuAlertState`
- `OnboardingState`
- etc.

Small types are usually good, but here the line between:
- storage model
- service DTO
- domain model
- view model projection

is sometimes blurry.

### Example
nSome payload wrappers may not be adding much value beyond naming the return value of a service call.

That may be fine, but during refactor we should verify whether all of them are earning their keep.

---

## 10. Async boundaries are sometimes thin wrappers over synchronous internals

Examples:
- service methods are async at the protocol level
- but much of the implementation is synchronous filesystem/process work wrapped for async call sites
- HTTP flows use semaphore-based sync wrappers rather than a more clearly async client boundary

This is not inherently bad in a small macOS app, but it is another sign that boundaries were shaped around usage rather than around clear separations.

---

## What looks healthy already

This is not a “rewrite everything” situation.

There are several strengths worth preserving:

- tests pass today
- the project already has a clean top-level directory split: `App`, `Core`, `Infrastructure`, `Features`
- there is useful domain thinking in:
  - `AccountUsageMergeService`
  - `AccountSwitchRecommendationService`
  - `MenuAlertPolicy`
- the runtime resolution and auth/session coordination problems are understood and covered by tests
- the app is still small enough to refactor safely without a massive migration program

So the right move is **targeted simplification**, not a rewrite.

---

## Preliminary dead / obsolete / prune candidates

I did not find a large obviously dead production subsystem that can be removed blindly.

However, there are some **prune candidates** or **re-evaluate candidates**:

### Candidate A — debug-only temporary auth sandbox path

Question:
- should this remain as a production-facing advanced setting?
- or should it become an internal debug/test-only utility with less UI/state surface?

### Candidate B — advanced settings visibility persistence

Question:
- do we need to persist whether advanced settings are visible?
- or can advanced simply always exist behind a single section?

### Candidate C — compatibility storage keys and migration scaffolding

Question:
- can old preference/config migrations be handled once and then removed from mainline code?

### Candidate D — payload wrappers that add little semantic value

Question:
- do all result payload structs need to exist as separate transport types?
- or can some operations return simpler domain values?

### Candidate E — coordinator extension file pattern

Question:
- does splitting large types into extension files improve maintainability here?
- or would extracting actual collaborator objects be clearer?

---

## Refactor goals

This cleanup should aim to:

1. reduce cognitive load
2. remove or isolate low-value complexity
3. make service and UI boundaries clearer
4. shrink the main view model substantially
5. isolate Codex-specific protocol machinery from generic app state
6. improve navigability without fake modularity
7. preserve behavior where it still earns its keep, while simplifying onboarding and other lower-value UX/code paths
8. prepare obvious neutral seams for later multi-agent support without prematurely generalizing everything now

## Final decisions from review

These decisions are now part of the plan:

- **Refactor depth:** deep cleanup (`C`)
- **Priority:** organization and behavior simplification are equally important (`C`)
- **Temporary auth sandbox:** remove entirely (`C`)
- **Advanced settings visibility:** keep advanced if useful, but do not persist visibility (`C`)
- **Onboarding:** simplify both internally and in UX (`C`)
- **Auto-switching:** preserve behavior, but isolate it better (`B`)
- **Usage/rate-limit subsystem:** keep behavior, but simplify internals where possible (`B`)
- **Compatibility handling:** moderate approach; use one-time migrations where needed, then simplify mainline code (`B`)
- **File/folder reorganization:** strong cleanup is desired (`C`)
- **Protocol/type cleanup:** broad naming cleanup is desired (`C`)
- **View model strategy:** choose the best technical direction, not constrained up front (`C`)star
- **UI refactor appetite:** minimal extraction only where clearly needed (`A`)
- **Test refactor appetite:** minimal; only change tests as needed (`A`)
- **Primary success criterion:** all of the above, with balanced priority
- **Delivery style:** bigger sweeping cleanup is acceptable (`C`)
- **Multi-agent preparation:** Codex-first cleanup, but prepare obvious neutral seams where clearly helpful (`B`)

---

## Non-goals

This refactor plan should **not** aim to:

- redesign the product UX from scratch beyond targeted simplifications such as onboarding and advanced/debug settings cleanup
- add pi support yet
- rewrite all tests from scratch
- split the package into many SwiftPM modules unless clearly justified
- change storage formats unnecessarily unless simplification benefits are strong

---

## Proposed refactor strategy

## Phase 0 — Guardrails and inventory

Goal:
- establish a safe baseline before changing structure

Tasks:
- keep `swift test --parallel` green at every step
- add a short architecture note documenting current major flows:
  - refresh
  - login
  - switch
  - usage fetch
- identify exact must-keep behaviors for current release
- explicitly list features that are debug-only or low-priority

Deliverable:
- a checked-in refactor checklist and baseline behavior notes

---

## Phase 1 — Prune low-value complexity first

Goal:
- reduce complexity before moving code around

Tasks:
- remove the temporary auth sandbox feature and all related production/debug UI, preferences, and plumbing
- simplify advanced settings behavior so visibility is no longer persisted
- simplify onboarding both in UX and implementation
- review compatibility-only settings/config code and replace long-lived branches with one-time migration where appropriate
- remove trivially unused helpers or wrappers discovered during implementation

Deliverable:
- leaner surface area before structural extraction

---

## Phase 2 — Break up `AccountsMenuViewModel` by responsibility

Goal:
- turn the giant view model into a thinner composition root

Recommended extraction targets:

### `RefreshController` or `AccountsRefreshController`
Owns:
- refresh loop
- staged refresh behavior
- refresh warning/error shaping
- runtime probe refresh if appropriate

### `AccountActionsController`
Owns:
- rename/remove/import/check-status/switch action orchestration
- feedback result normalization

### `InteractiveLoginController`
Owns:
- in-app login
- terminal fallback
- pending interactive login session
- resume-on-app-active flow

### `SettingsStateStore` or `PreferencesController`
Owns:
- binding persisted settings to in-memory state
- onboarding / density / bar style / etc.

The exact split does not need to be forced ahead of time. The approved direction is to choose the best technical decomposition during implementation, as long as the end result is a substantially slimmer top-level view model.

The view model should then primarily:
- expose published state for views
- delegate work to smaller collaborators
- compose results into presentation state

Deliverable:
- significantly smaller `AccountsMenuViewModel`
- reduced test pressure on one giant view-model test file, without requiring a broad test rewrite

---

## Phase 3 — Reorganize Codex infrastructure into clearer subsystems

Goal:
- create sharper boundaries inside infrastructure

Suggested subsystem split:

### `CodexProfileStore` / `CodexAccountsRepository`
Owns:
- config file read/write
- account metadata read/write
- account CRUD

### `CodexAuthStore` / `CodexAuthSessionManager`
Owns:
- auth lock acquisition
- auth swapping
- snapshot/restore logic
- default/account auth sync

### `CodexRuntimeService`
Owns:
- runtime resolution
- command building
- environment building
- process execution entry points

### `CodexUsageService`
Owns:
- usage API
- refresh token logic
- RPC fallback
- cache handling

This can still live in one target, but the ownership lines should be explicit.

Deliverable:
- `CodexAccountService` either becomes a thin facade or disappears in favor of a smaller orchestrator

---

## Phase 4 — Simplify service protocols and model boundaries

Goal:
- reduce naming leakage and improve clarity

Tasks:
- revisit `CodexAccountServicing`
- stop exposing service-internal nested types like `CodexAccountService.RuntimeProbe`
- perform broad naming cleanup where it meaningfully improves understanding
- introduce neutral result/value types where helpful, especially where they create obvious future seams for multi-agent support
- evaluate whether all `*Payload` types are needed or whether some can collapse into simpler models
- distinguish clearly between:
  - persistence records
  - service responses
  - domain models
  - presentation models

Deliverable:
- clearer, flatter model boundaries

---

## Phase 5 — Simplify the refresh and switching pipeline

Goal:
- remove orchestration duplication and centralize decision-making

Tasks:
- consolidate staged merge logic in `performRefresh()`
- extract repeated “update local current account state” behavior into a single helper
- centralize focus and selection repair after account changes
- centralize user feedback formatting for account operations
- make auto-switch triggering a single well-defined post-refresh step

Deliverable:
- fewer special cases in refresh and switch flows
- easier to add future agent-specific behavior later

---

## Phase 6 — Minimal UI cleanup where it supports architecture

Goal:
- reduce only the highest-value UI complexity without turning this into a presentation-layer rewrite

Targets:
- `SettingsContentView+DashboardAccounts.swift`
- `SettingsContentView+RuntimeAdvanced.swift`
- `AccountsMenuContentView+Sections.swift`

Approach:
- extract only clearly self-contained subviews or repeated sections
- keep layout tokens and styling in one place
- move business branching out of view bodies when doing so directly supports simpler state ownership
- avoid broad UI churn unless it is needed to support earlier phases

Deliverable:
- modestly smaller, easier-to-scan UI files with minimal unnecessary churn

---

## Phase 7 — Minimal test adjustment

Goal:
- keep confidence high without turning the cleanup into a test-suite redesign

Tasks:
- update existing tests only as needed for structural changes
- add focused tests for extracted collaborators only when coverage would otherwise regress
- keep existing integration-style coverage where it is already providing value

Deliverable:
- tests remain green with minimal churn

---

## Phase 8 — Naming and directory cleanup

Goal:
- make the codebase easier to navigate

Tasks:
- rename files/types whose names no longer reflect responsibilities
- remove “coordinator” extension file patterns where real collaborator types now exist
- group files by actual subsystem rather than by where they happened to start life
- keep folders shallow and obvious

Possible target structure:

```text
Sources/MultiCodex/
  App/
  Core/
  Features/
    MenuBar/
    Settings/
    Shared/
  Infrastructure/
    Codex/
      Accounts/
      Auth/
      Runtime/
      Usage/
    Preferences/
    Notifications/
```

This is illustrative, not mandatory.

---

## Suggested sequencing relative to pi support

Recommended order:

1. complete this deep cleanup first
2. remove low-value features/codepaths (temporary sandbox, advanced visibility persistence, overly heavy onboarding)
3. land the codebase in a clearer Codex-first architecture with better naming and folder boundaries
4. introduce only the most obvious neutral seams needed for future multi-agent work
5. then begin the dedicated multi-agent abstraction work
6. only after that, implement pi support

This should reduce risk substantially while avoiding premature abstraction.

---

## Success criteria

This refactor is successful if, after completion:

- all tests still pass
- the app behavior is unchanged for current Codex users
- `AccountsMenuViewModel` is substantially smaller and mostly presentation-oriented
- Codex auth/runtime/usage logic are isolated into clearer subsystems
- large UI files are noticeably smaller and more compositional
- low-value complexity is removed or quarantined
- the resulting architecture makes multi-agent support clearly easier

---

## Concrete recommendations I would make now

Given the approved direction, I would prioritize these first:

### Priority 1
Remove low-value complexity:
- temporary auth sandbox
- advanced visibility persistence
- overcomplicated onboarding flow/state

### Priority 2
Shrink `AccountsMenuViewModel`

### Priority 3
Split Codex infrastructure into:
- runtime
- auth/session
- usage
- repository/store

### Priority 4
Do a broad naming/folder cleanup so the codebase reads more cleanly

### Priority 5
Apply only minimal UI extraction where it directly supports earlier cleanup

---

## Approval gate

Before implementation starts, this refactor plan should be:

- reviewed
- modified as needed
- explicitly approved

Only after approval should we begin the cleanup work.
