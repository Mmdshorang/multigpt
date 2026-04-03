# Plan: Add Support for Pi Coding Agent

Status: Draft for review only. No implementation yet.

## Goal

Add support for coding agents beyond Codex CLI, starting with **pi coding agent**, while preserving current Codex behavior.

This phase is for:
- understanding pi auth/runtime behavior
- defining the architecture
- agreeing on an implementation plan

This phase is **not** for writing production code yet.

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

The current app is heavily Codex-specific.

Main Codex-bound areas:
- `Sources/MultiCodexMenu/Infrastructure/Accounts/CodexAccountService.swift`
- `Sources/MultiCodexMenu/Infrastructure/Accounts/RuntimeCommandService.swift`
- `Sources/MultiCodexMenu/Infrastructure/Runtime/CodexRuntimeResolver.swift`
- `Sources/MultiCodexMenu/Infrastructure/Accounts/RateLimitsFetcher.swift`
- settings/UI copy referring directly to `codex`
- persisted preference key `customCodexPath`

This means adding pi cleanly should start with an abstraction layer, not ad hoc branching inside existing Codex-only services.

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

## Phase 0 — Finalize design

Goal:
- align on architecture and scope before code changes

Deliverables:
- approved plan
- decisions on v1 switch strategy

Open decisions:
1. Should pi switching update the global default `~/.pi/agent/auth.json`, or only work via profile-specific launching?
2. Should v1 store only `auth.json`, or full pi profile directories?
3. Should the UI expose both Codex and pi in the same account list, or separate by agent?

## Phase 1 — Introduce generic agent abstraction

Goal:
- decouple app logic from Codex-specific services

Tasks:
- define `AgentKind`
- define `CodingAgentServicing`
- define `AgentCapabilities`
- adapt orchestration/view model to capabilities rather than Codex assumptions
- preserve existing Codex behavior behind the new interface

Non-goal:
- no pi behavior yet beyond scaffolding

## Phase 2 — Generalize preferences and runtime settings

Goal:
- persist selected agent and runtime path cleanly

Tasks:
- add selected agent preference
- replace single `customCodexPath` concept with either:
  - per-agent runtime path, or
  - generic runtime path keyed by agent
- update settings UI copy from `codex`-specific to generic agent wording
- maintain backward compatibility for existing Codex path preference

## Phase 3 — Implement pi runtime integration

Goal:
- detect and launch pi reliably

Tasks:
- create `PiRuntimeResolver`
- runtime probe via `pi --version`
- support custom path + PATH lookup
- reuse process runner infrastructure where possible

## Phase 4 — Implement pi profile storage

Goal:
- manage isolated pi profiles inside MultiCodex storage

Tasks:
- define storage layout for pi profiles
- create metadata model for pi profiles
- add repository/service for create/read/update/delete profile data
- use `PI_CODING_AGENT_DIR` for isolated operations

Recommended stored unit:
- full profile directory, not only extracted auth tokens

## Phase 5 — Implement pi login flow

Goal:
- allow creating or reauthenticating a pi profile

Tasks:
- create/login target profile directory
- launch pi with `PI_CODING_AGENT_DIR=<profile dir>`
- guide user to complete `/login`
- mark profile as connected when `auth.json` appears

## Phase 6 — Implement pi switching

Goal:
- switch active pi profile according to chosen strategy

If using profile-managed launch:
- store selected pi profile
- ensure app-launched pi sessions use that profile dir

If using auth sync:
- copy selected profile `auth.json` into `~/.pi/agent/auth.json`
- preserve permissions and atomicity
- clearly message that the global pi auth was updated

## Phase 7 — UI adaptation

Goal:
- support multi-agent UX cleanly

Tasks:
- add agent selector in Settings or top-level UI
- make runtime labels agent-aware
- hide/disable unsupported usage UI for pi
- make button labels agent-aware:
  - Login with Codex
  - Login with Pi
- present capability-aware status messaging

## Phase 8 — Tests and migration

Goal:
- protect current behavior and validate pi integration

Tasks:
- keep Codex tests passing
- add tests for:
  - selected agent preference
  - runtime resolution for pi
  - pi profile directory creation
  - `PI_CODING_AGENT_DIR` env setup
  - switch behavior
  - auth sync behavior if chosen
- add migration test for old `customCodexPath`

---

## Suggested file/module direction

Possible future organization:

```text
Sources/MultiCodexMenu/Infrastructure/Agents/
  AgentKind.swift
  AgentCapabilities.swift
  CodingAgentServicing.swift

Sources/MultiCodexMenu/Infrastructure/Codex/
  ...existing codex-specific implementations...

Sources/MultiCodexMenu/Infrastructure/Pi/
  PiAgentService.swift
  PiRuntimeResolver.swift
  PiProfileRepository.swift
```

This is not mandatory, but the separation is recommended.

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

Please review and decide:

1. **Pi switch strategy**
   - A: profile-managed launching only
   - B: sync selected profile auth into default `~/.pi/agent/auth.json`

2. **Pi storage granularity**
   - A: full isolated pi profile directory
   - B: only managed `auth.json`

3. **UI model**
   - A: one app with selectable active agent
   - B: keep Codex and pi sections visually separate

4. **v1 scope**
   - confirm that pi usage metrics are out of scope for initial release

---

## Recommendation summary

My recommendation is:

- introduce a multi-agent abstraction first
- implement pi as a **profile-based integration**
- use `PI_CODING_AGENT_DIR` as the isolation mechanism
- treat pi `auth.json` as opaque managed state
- do **not** attempt usage/rate-limit support in v1
- keep Codex fully backward compatible

---

## Approval gate

Before implementation starts, this plan should be:

- reviewed
- modified as needed
- explicitly approved

Only after approval should we move to code changes.
