# Plan: Add Support for Pi Coding Agent

Status: Partially implemented. The Codex-first refactor is complete and the multi-agent abstraction / Pi scaffold is underway.

## Current baseline

The prerequisite Codex-first refactor has now been completed:
- Codex infrastructure has been reorganized into clearer subsystems
- `AccountsMenuViewModel` responsibilities have been split into dedicated controllers
- onboarding / advanced-settings / temporary sandbox complexity has been reduced
- the codebase now has cleaner seams for future multi-agent support

This means the project is now ready to move from "refactor first" into "introduce multi-agent abstractions, then add pi".

## Goal

Add support for coding agents beyond Codex CLI, starting with **pi coding agent**, while preserving current Codex behavior.

This phase started as architecture/design work and is now actively being implemented.

Current implementation scope:
- generic agent abstraction
- Codex adapter behind the generic boundary
- Pi runtime/profile/login scaffolding
- capability-aware UI and preferences
- tests and compatibility migrations

---

## What we learned about pi

## Pi state directory

Pi stores its state under an **agent directory**:

- default: `~/.pi/agent`
- overridable with env var: `PI_CODING_AGENT_DIR`
- also configurable in the SDK as `agentDir`

Inside that directory, pi keeps:

- `auth.json`
- `settings.json`
- `models.json`
- `sessions/`
- extensions / prompts / skills / themes

This is important because it gives us a natural unit for account/profile isolation.

## Pi authentication model

Pi supports two broad auth modes:

### 1. API key auth

Credentials can come from:
- environment variables
- `auth.json`

Examples from docs:
- `OPENAI_API_KEY`
- `ANTHROPIC_API_KEY`
- `GEMINI_API_KEY`

### 2. OAuth / subscription auth

Pi supports `/login` for subscription-style providers, including:
- Claude Pro/Max
- ChatGPT Plus/Pro (**Codex**)
- GitHub Copilot
- Gemini CLI
- Antigravity

The docs state:
- credentials are stored in `~/.pi/agent/auth.json`
- tokens auto-refresh when expired
- `/logout` clears credentials

## How pi handles Codex auth

Important finding:

Pi does **not** appear to rely on Codex CLI's native auth file (`~/.codex/auth.json`) as its primary auth source.

Instead, for ChatGPT Plus/Pro (Codex) login, pi manages auth in:

- `~/.pi/agent/auth.json`

So for MultiCodex integration, the right abstraction for pi is probably:
- a **pi profile directory**, or
- at minimum pi's own `auth.json`

not Codex CLI's `~/.codex/auth.json`.

## Auth resolution order in pi

From docs, pi resolves auth roughly in this order:

1. CLI/runtime override
2. `auth.json`
3. environment variables
4. custom provider fallback

For persisted subscription auth, `auth.json` is the key source.

## Constraint / unknown

The docs do **not** clearly specify the exact JSON shape used for pi's built-in Codex OAuth entry inside `auth.json`.

Therefore:
- we should treat `auth.json` contents as mostly opaque
- we should avoid hand-editing provider-specific nested fields unless necessary
- profile-level isolation is safer than schema-dependent mutation

---

## Current app architecture observations

The app is still operationally Codex-first, but it is no longer as tightly entangled as before.

Main Codex-bound areas now live under clearer boundaries:
- `Sources/MultiCodex/Infrastructure/Codex/Accounts/CodexAccountService.swift`
- `Sources/MultiCodex/Infrastructure/Codex/Runtime/RuntimeCommandService.swift`
- `Sources/MultiCodex/Infrastructure/Codex/Runtime/CodexRuntimeResolver.swift`
- `Sources/MultiCodex/Infrastructure/Codex/Usage/RateLimitsFetcher.swift`
- settings/UI copy still contains some `codex`-specific wording
- persisted preference keying still includes `customCodexPath`

Important implication:
- the refactor removed major structural blockers
- but the app model is still single-agent in its domain language
- so pi should still be added through an explicit abstraction layer, not by sprinkling `if agent == pi` branches across Codex services

---

## Recommended architecture

## Core recommendation

Refactor from a **Codex-only service** to a **multi-agent adapter architecture**, then add pi as the first non-Codex implementation.

## Proposed abstractions

### `AgentKind`

Enum of supported agent integrations, initially:
- `codex`
- `pi`

### `CodingAgentServicing`

A protocol representing the operations the app needs from an agent integration.

Likely responsibilities:
- resolve runtime
- probe runtime availability
- open login flow
- perform in-app login if supported
- fetch account/profile list
- switch active account/profile
- remove / rename / import accounts
- fetch basic status
- fetch usage/limits if supported
- expose capability flags

### `AgentCapabilities`

Lets UI and orchestration adapt per integration.

Candidate flags:
- `supportsUsage`
- `supportsInAppLogin`
- `supportsTerminalLogin`
- `supportsStatusCheck`
- `supportsManagedProfiles`
- `supportsLiveAuthValidation`

This avoids forcing pi into Codex-specific flows like rate-limit RPC.

---

## Pi integration model

## Recommended mental model

Treat pi accounts as **managed pi profiles**.

Each profile should have its own isolated pi state directory.

Example storage inside MultiCodex config:

```text
~/.config/multicodex/agents/pi/accounts/<name>/pi-agent/
  auth.json
  settings.json
  models.json
  sessions/
```

This maps naturally to:

- `PI_CODING_AGENT_DIR=<that directory>`

## Why this is the safest approach

Because:
- pi owns its own auth format
- OAuth token schema is not fully documented for built-in Codex login
- pi stores more than just auth in the agent dir
- using isolated agent dirs avoids fragile JSON surgery

---

## Recommended user flows for pi

## 1. Login / add profile

When the user adds a pi profile:

1. Create a managed pi profile directory
2. Launch `pi` with:
   - `PI_CODING_AGENT_DIR=<profile dir>`
3. User completes `/login` inside pi
4. After login, the profile directory contains its own authenticated `auth.json`

Notes:
- This may be terminal-based first
- We should not assume a non-interactive login API

## 2. Switch profile

There are two possible strategies.

### Preferred strategy: profile-aware launch

Whenever MultiCodex launches pi for a profile, pass:

- `PI_CODING_AGENT_DIR=<selected profile dir>`

Pros:
- cleanest
- no copying required
- keeps sessions/settings/auth isolated per profile

Cons:
- only works if the user launches pi through MultiCodex-controlled entry points

### Compatibility strategy: sync active profile into default pi dir

On switch, copy selected profile data into the live/default pi dir:

- source: managed profile `auth.json`
- target: `~/.pi/agent/auth.json`

Optional later:
- `settings.json`
- `models.json`

Pros:
- affects normal `pi` launches outside the app

Cons:
- riskier
- may overwrite user state
- more migration/merge questions

## Recommendation

For v1, choose one of these explicitly:

### Option A
Support **profile-managed launching only**.

### Option B
Support **auth sync into default pi dir**, but initially sync only `auth.json`.

My preference is:
- architecture should support both
- v1 should start with **profile-managed launching** if that fits the app UX
- if your product goal is "switch the globally active pi account", then sync `auth.json` in v1 and document the behavior clearly

---

## Pi feature scope for v1

## Supported in v1

- runtime detection for `pi`
- custom pi executable path
- add/login pi profile using isolated `PI_CODING_AGENT_DIR`
- switch pi profile
- remove/rename managed pi profiles
- import/export pi auth/profile data if desired
- basic runtime/auth presence status

## Explicitly unsupported or deferred in v1

- Codex-style usage/rate-limit fetching
- deep token/account verification beyond available file/runtime checks
- assumptions about pi-internal auth schema
- session migration/merging between pi profiles
- complex per-provider inspection of `auth.json`

## UI behavior for unsupported areas

For pi, usage-related UI should be:
- hidden, or
- replaced with "Not available for this agent"

---

## Status model for pi

Pi does not document a Codex-like `login status` command equivalent.

So pi status in v1 should be lightweight and capability-based.

Possible signals:
- `pi --version` succeeds
- managed profile dir exists
- `auth.json` exists and is non-empty
- optional heuristic: known provider entry appears in `auth.json`

We should avoid promising that pi auth is fully validated unless we find a reliable pi-native command later.

---

## Proposed implementation phases

## Phase 0 — Confirm the remaining product decisions

Goal:
- lock the few decisions that affect data model and UX before coding the abstraction layer

Status:
- prerequisite architecture refactor is complete
- this is now the only planning gate left before implementation

Remaining decisions to confirm:
1. Should pi switching update the global default `~/.pi/agent/auth.json`, or only work via profile-specific launching?
2. Should v1 store only `auth.json`, or full pi profile directories?
3. Should the UI expose both Codex and pi in the same account list, or separate by agent?
4. Confirm again that pi usage metrics remain out of scope for v1.

## Phase 1 — Introduce the neutral multi-agent domain layer

Goal:
- move the app from a Codex-shaped domain model to an agent-shaped domain model without changing user-visible Codex behavior

Tasks:
- define `AgentKind`
- define `AgentCapabilities`
- define a generic agent service protocol, likely replacing direct use of `CodexAccountServicing` at the feature boundary
- introduce shared agent-facing models for runtime status, account/profile summaries, auth state, and supported actions
- keep Codex as the first adapter behind the new interface

Notes:
- this should happen at the feature/domain boundary first
- Codex internals do not need to be fully rewritten immediately if an adapter layer can preserve behavior cleanly

Non-goal:
- no pi behavior yet beyond scaffolding and compile-safe abstraction points

## Phase 2 — Generalize preferences, naming, and settings surface

Goal:
- remove remaining single-agent assumptions from app preferences and visible settings

Tasks:
- add selected agent preference
- replace `customCodexPath` with either per-agent runtime path storage or a generic runtime-path map keyed by agent
- add one-time migration from existing Codex path preference into the new structure
- update settings labels and helper copy from `codex`-specific wording to agent-aware wording where appropriate
- keep any Codex-specific labels only where the functionality is truly Codex-only

Likely outputs:
- generic runtime settings model
- selected-agent persistence
- thinner UI branching through capabilities

## Phase 3 — Add a Codex adapter behind the generic interface

Goal:
- prove the abstraction against the existing implementation before introducing pi

Tasks:
- wrap the current Codex service stack in a generic agent adapter
- map Codex capabilities explicitly
- ensure auto-switching, login, removal, usage, and status behaviors continue to work unchanged
- keep all current tests green, updating only where they now target the generic boundary instead of Codex-only types

Why this phase matters:
- it validates the abstraction with the known integration first
- it reduces the risk that pi design pressures distort the existing working Codex flow

## Phase 4 — Implement pi runtime integration

Goal:
- detect and launch pi reliably through the same generic agent boundary

Tasks:
- create a `PiRuntimeResolver`
- probe runtime via `pi --version`
- support custom path plus PATH lookup
- add a pi runtime descriptor / launcher layer
- reuse process-running infrastructure where possible, but do not force pi into Codex-specific command assumptions

## Phase 5 — Implement pi profile storage

Goal:
- manage isolated pi profiles inside MultiCodex storage in a way that avoids undocumented auth-schema coupling

Tasks:
- define storage layout for pi profiles
- create metadata model for pi profiles
- add repository/service for create/read/update/delete profile data
- use `PI_CODING_AGENT_DIR` for isolated operations

Recommended stored unit:
- full profile directory, not only extracted auth tokens

Recommended storage shape:

```text
<multicodex-home>/agents/pi/accounts/<name>/pi-agent/
  auth.json
  settings.json
  models.json
  sessions/
```

## Phase 6 — Implement pi login and reauthentication flow

Goal:
- allow creating or reconnecting a pi profile safely

Tasks:
- create/login target profile directory
- launch pi with `PI_CODING_AGENT_DIR=<profile dir>`
- guide user to complete `/login`
- treat `auth.json` as opaque provider-managed state
- mark profile as connected when expected profile files appear

Notes:
- v1 should assume interactive login
- we should not depend on undocumented non-interactive OAuth internals

## Phase 7 — Implement pi switching

Goal:
- switch active pi profile according to the selected product strategy

If using profile-managed launch:
- store selected pi profile
- ensure app-launched pi sessions use that profile directory
- make it clear that external terminal launches of `pi` are unaffected unless launched through the app-managed environment

If using auth sync:
- copy selected profile `auth.json` into `~/.pi/agent/auth.json`
- preserve permissions and atomicity
- clearly message that the global pi auth was updated
- consider whether `settings.json` and `models.json` are intentionally excluded in v1

Current recommendation:
- design for both
- implement profile-managed launch first unless product requirements explicitly demand global pi switching

## Phase 8 — UI adaptation

Goal:
- support multi-agent UX cleanly with minimal unnecessary churn

Tasks:
- add agent selector in Settings or another clear top-level location
- make runtime labels and login actions agent-aware
- hide or replace unsupported usage UI for pi with capability-aware messaging
- ensure account/profile rows communicate the active agent clearly
- preserve current Codex UX quality instead of flattening everything into the lowest common denominator

## Phase 9 — Tests, migration, and rollout safety

Goal:
- protect existing Codex behavior while validating the new pi support and compatibility paths

Tasks:
- keep Codex tests passing
- add tests for:
  - selected agent preference
  - runtime resolution for pi
  - pi profile directory creation
  - `PI_CODING_AGENT_DIR` env setup
  - pi switching behavior
  - auth sync behavior if chosen
  - migration from legacy `customCodexPath`
- add focused adapter-level tests around capabilities and generic orchestration
- avoid broad UI snapshot churn unless truly needed

---

## Suggested file/module direction

Recommended future organization:

```text
Sources/MultiCodex/Core/Agents/
  AgentKind.swift
  AgentCapabilities.swift
  AgentRuntimeModels.swift
  AgentAccountModels.swift
  CodingAgentServicing.swift

Sources/MultiCodex/Infrastructure/Codex/
  ...existing codex-specific implementations...
  CodexAgentAdapter.swift

Sources/MultiCodex/Infrastructure/Pi/
  PiAgentService.swift
  PiRuntimeResolver.swift
  PiProfileRepository.swift
  PiProfileStorage.swift
```

Why this direction fits the current refactor state:
- shared agent contracts belong in `Core`, not inside a specific integration folder
- existing Codex code already lives under `Infrastructure/Codex/`
- pi can be introduced as a parallel integration instead of an invasive rewrite

---

## Risks and tradeoffs

## Risk 1: Treating pi like Codex CLI

Bad assumption:
- pi can be integrated by reusing `~/.codex/auth.json`

Why risky:
- pi stores auth in its own `auth.json`
- built-in Codex login is managed by pi, not Codex CLI

## Risk 2: Mutating undocumented auth schema

Bad assumption:
- we can safely rewrite provider-specific pieces inside pi `auth.json`

Why risky:
- schema for built-in OAuth entries is not fully documented
- future pi updates may break assumptions

Mitigation:
- prefer whole-profile isolation
- copy opaque files rather than re-encoding provider-specific entries

## Risk 3: Over-designing around usage

Bad assumption:
- every agent must support Codex-like usage reporting

Why risky:
- pi does not expose the same rate-limit flow
- this would distort the abstraction

Mitigation:
- capability-driven UI and services

---

## Recommended decisions to make before implementation

Please review and confirm:

1. **Pi switch strategy**
   - A: profile-managed launching only
   - B: sync selected profile auth into default `~/.pi/agent/auth.json`

   Recommendation: **A** for v1.

2. **Pi storage granularity**
   - A: full isolated pi profile directory
   - B: only managed `auth.json`

   Recommendation: **A** for v1.

3. **UI model**
   - A: one app with selectable active agent
   - B: keep Codex and pi sections visually separate

   Recommendation: **A**, while allowing capability-based differences within the shared experience.

4. **v1 scope**
   - confirm that pi usage metrics are out of scope for initial release

   Recommendation: **confirmed out of scope**.

---

## Recommendation summary

My recommendation is:

- now that the refactor is complete, begin the multi-agent work in two stages:
  1. introduce the neutral agent abstraction and migrate Codex behind it
  2. add pi as the first non-Codex adapter
- implement pi as a **profile-based integration**
- use `PI_CODING_AGENT_DIR` as the isolation mechanism
- treat pi `auth.json` as opaque managed state
- do **not** attempt usage/rate-limit support in v1
- keep Codex behavior fully backward compatible
- prefer profile-managed launch over global auth syncing for the first release unless product requirements say otherwise

---

## Approval gate

Before pi implementation starts, this plan should be:

- reviewed
- modified as needed
- explicitly approved on the remaining product decisions

The prerequisite refactor gate is complete. The next implementation step, once approved, is:
- introduce the generic multi-agent abstraction layer
- migrate Codex onto it
- then implement pi behind that boundary
