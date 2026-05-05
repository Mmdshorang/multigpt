# MultiCodex API Proxy Account Rotation — Implementation Plan

## Goal

Run a loopback API proxy that MultiCodex-managed Codex sessions can use for ChatGPT-backed Codex requests. Proxy selects account auth per request, rotates away from exhausted accounts, and keeps Codex config changes scoped to managed homes.

This plan depends on completing the spike in [proxy-account-rotation-spike-plan.md](proxy-account-rotation-spike-plan.md). Do not implement Phase 1 until spike acceptance criteria pass.

## Non-Goals

- Do not mutate user global `~/.codex/config.toml` by default.
- Do not proxy terminal-launched Codex sessions unless launched by MultiCodex with managed `CODEX_HOME`.
- Do not guarantee seamless mid-stream rotation for active `/responses` streams.
- Do not proxy arbitrary user tool network traffic.
- Do not expose proxy off-loopback.
- Do not support remote proxy mode in first implementation.

## Verified Codex CLI Facts

Source tree: `.third_party/codex`.

### Responses Provider URL

`ModelProviderInfo.to_api_provider()` defaults ChatGPT auth to:

```text
https://chatgpt.com/backend-api/codex
```

Codex endpoint clients append relative paths with `Provider.url_for_path()`.

Expected final URLs:

| Codex path                                       | Final upstream with ChatGPT auth                                 |
| ------------------------------------------------ | ---------------------------------------------------------------- |
| `responses`                                      | `https://chatgpt.com/backend-api/codex/responses`                |
| `models`                                         | `https://chatgpt.com/backend-api/codex/models`                   |
| `responses/compact` if used by current API crate | `https://chatgpt.com/backend-api/codex/responses/compact`        |
| `memories/trace_summarize` if used               | `https://chatgpt.com/backend-api/codex/memories/trace_summarize` |

Implementation implication: local provider `base_url` should normally be `http://127.0.0.1:<port>`, and proxy maps incoming `/responses` to upstream `/backend-api/codex/responses`.

### ChatGPT Backend URL Is Separate

Codex also has top-level `chatgpt_base_url`, default:

```text
https://chatgpt.com/backend-api/
```

This is used by backend services such as `wham`, apps/connectors, plugin share/install flows, and OpenAI file upload for apps. It is not controlled by `model_providers.openai.base_url`.

Implementation implication: first release may leave `chatgpt_base_url` direct. If proxying those calls is required, config bridge must also set `chatgpt_base_url = "http://127.0.0.1:<port>/backend-api/"` and proxy must route `/backend-api/...` separately.

### Realtime Is Separate

Realtime conversation starts with `provider.to_api_provider(Some(AuthMode::ApiKey))`; default is OpenAI `/v1`, not ChatGPT Codex backend. It can be overridden only by `experimental_realtime_ws_base_url`.

Implementation implication: do not claim realtime is covered by provider `base_url`. Leave realtime direct in v1, or explicitly configure `experimental_realtime_ws_base_url` in a later phase after spike proof.

### Token Refresh

Codex refresh:

- POSTs JSON to `https://auth.openai.com/oauth/token`.
- Sends fixed `client_id = "app_EMoamEEZ73f0CkXaXp7hrann"`.
- Body shape: `{"client_id": "...", "grant_type": "refresh_token", "refresh_token": "..."}`
- Response fields are optional: `id_token`, `access_token`, `refresh_token`.
- Guarded refresh reloads auth first and avoids overwriting auth if another process refreshed same account.

Implementation implication: proxy token refresh must copy Codex-compatible JSON flow and guarded write semantics, not form encoding.

## Architecture

```text
Codex process with managed CODEX_HOME
  config.toml:
    [model_providers.openai]
    base_url = "http://127.0.0.1:<port>"
  auth.json:
    current account auth, or stale bootstrap auth

        POST /responses
              |
              v
MultiCodex loopback proxy
  - validates Host/loopback
  - classifies route
  - selects account
  - injects Bearer token
  - forwards to https://chatgpt.com/backend-api/codex/responses
  - streams SSE back
```

## Route Matrix

| Incoming route              | Upstream route                                                   | Auth source      | Rotation                                          |
| --------------------------- | ---------------------------------------------------------------- | ---------------- | ------------------------------------------------- |
| `/responses`                | `https://chatgpt.com/backend-api/codex/responses`                | selected account | pre-request only                                  |
| `/models`                   | `https://chatgpt.com/backend-api/codex/models`                   | selected account | safe retry on 429                                 |
| `/responses/compact`        | `https://chatgpt.com/backend-api/codex/responses/compact`        | selected account | no replay unless spike proves unary/idempotent    |
| `/memories/trace_summarize` | `https://chatgpt.com/backend-api/codex/memories/trace_summarize` | selected account | no replay unless spike proves safe                |
| `/backend-api/*`            | `https://chatgpt.com/backend-api/*`                              | selected account | disabled in v1 unless chatgpt proxy phase enabled |
| `/health`                   | local status JSON                                                | none             | none                                              |
| WebSocket                   | direct in v1                                                     | n/a              | none                                              |

Unknown routes return `502` with concise proxy error unless passthrough mode is explicitly enabled.

`GET /health` is loopback-only and must not expose account names or tokens. Return counts, health state, uptime, version, request count, rotation count, and optionally a non-reversible active account hash.

## Rotation Model

### Core Rule

Rotate at request boundaries. Never replace account after any upstream response bytes have been delivered to Codex.

### Account Selection

`ProxyAccountRotator` actor owns:

- `activeAccount`
- `exhaustedUntilByAccount`
- latest `AccountUsage` snapshot from existing refresh pipeline
- per-session rotation counters
- in-flight stream count per account

Selection order:

1. Exclude accounts without readable ChatGPT auth.
2. Exclude accounts in cooldown.
3. Prefer accounts with most remaining 5h usage.
4. Tie-break by weekly remaining.
5. Tie-break by name ascending.
6. Sticky current account if healthy and not rate-limited.

### 429 Handling

`/models`:

- Safe to replay once per candidate.
- Mark account exhausted when upstream status `429`.
- Retry with next selected account until max rotations reached.

`/responses`:

- If upstream returns `429` before SSE body starts, mark exhausted and retry only if spike proves Codex/upstream returns 429 before work starts.
- If any stream bytes arrived, pass through and rotate next request.
- If stream fails mid-turn with rate-limit-looking error, mark account cooldown for next request, but do not replay current body.

### 401 Handling

- Attempt guarded token refresh for same account once.
- Retry same request only if no response body was delivered.
- If refresh fails permanently, mark account auth invalid and choose another account for next safe request.

## Config Strategy

### Scope

Only write config in MultiCodex-managed `CODEX_HOME` directories.

Targets:

- active managed home for selected account
- optional shared proxy home if MultiCodex launches Codex in a dedicated proxy home

Never edit real user `~/.codex/config.toml` unless user enables explicit global mode in future.

### Config Keys

Initial v1:

```toml
[model_providers.openai]
base_url = "http://127.0.0.1:<port>"
```

Optional later phase:

```toml
chatgpt_base_url = "http://127.0.0.1:<port>/backend-api/"
```

Realtime later phase only:

```toml
experimental_realtime_ws_base_url = "ws://127.0.0.1:<port>/v1/realtime"
```

### Safety

`ProxyConfigBridge` must:

- use narrow managed-home TOML patching for `[model_providers.openai]`
- store backup metadata under MultiCodex config dir
- include marker comments for proxy-managed values
- refuse restore if file changed externally since proxy write
- make all writes atomic

Patch guardrails:

- read UTF-8 only
- refuse BOM or CRLF
- match exactly one `[model_providers.openai]` block
- update only simple `base_url = "..."` string before next section
- insert `base_url` if missing
- refuse inline-table provider definitions or escaped/complex string values
- refuse complex TOML with clear UI error instead of attempting broad rewrite

## Implementation Phases

### Phase 0: Spike

Implement [proxy-account-rotation-spike-plan.md](proxy-account-rotation-spike-plan.md).

Exit criteria:

- verified Codex requests hit local proxy
- captured exact paths/methods/headers for `/responses` and `/models`
- verified config keys needed for managed `CODEX_HOME`
- verified 429 behavior for HTTP Responses path
- documented whether safe pre-body `/responses` replay is possible

## Delegation Plan

Use this split after Phase 0 is complete and route decisions are copied into this plan. Workers are not alone in the codebase: do not revert others' edits; keep write scopes disjoint and adapt to existing changes.

| Task                       | Owner scope | Files                                                                                                      | Depends on                   | Done when                                                                        |
| -------------------------- | ----------- | ---------------------------------------------------------------------------------------------------------- | ---------------------------- | -------------------------------------------------------------------------------- |
| Proxy core models + parser | Worker A    | `ProxyModels.swift`, `ProxyRequestParser.swift`, `ProxyRequestRewriter.swift`, parser/rewriter tests       | Phase 0                      | routes parse/rewrite per final matrix                                            |
| Upstream/SSE transport     | Worker B    | `ProxyUpstreamClient.swift`, `ProxySSEBridge.swift`, integration SSE test                                  | core model interfaces        | upstream request + raw SSE passthrough tested                                    |
| Server/connection handling | Worker C    | `ProxyServer.swift`, `ProxyConnectionHandler.swift`, connection tests                                      | parser + upstream interfaces | loopback server handles `/health`, `/models`, `/responses` in tests              |
| Auth store + provider      | Worker D    | `ProxyAuthStore.swift`, `ProxyAuthProvider.swift`, auth tests                                              | Phase 0 auth path decisions  | managed-home and legacy auth lookup tested                                       |
| Rotation engine            | Worker E    | `ProxyAccountRotator.swift`, `ProxyRotationPolicy.swift`, `ProxyUsageSnapshotBridge.swift`, rotation tests | auth provider interfaces     | cooldown/ranking/exhaustion tests pass                                           |
| Config bridge              | Worker F    | `ProxyConfigBridge.swift`, config tests                                                                    | Phase 0 config key decision  | managed `config.toml` writes/restores safely                                     |
| Token refresh              | Worker G    | `ProxyTokenRefresher.swift`, token refresh tests                                                           | auth store                   | Codex-compatible refresh semantics tested                                        |
| App lifecycle + UI         | Worker H    | `MultiCodexApp.swift`, `AccountsMenuViewModel.swift`, preferences, Settings/Menu views                     | core proxy status APIs       | prefs persist, lifecycle starts/stops, UI status shown                           |
| Integration + QA           | Integrator  | cross-cutting tests/docs only                                                                              | all workers                  | `rtk swift test --filter Proxy` and `rtk just check` pass or failures documented |

## Implementation Order

1. Copy final Phase 0 route/auth/config decisions into this plan.
2. Implement parser/rewriter/models first.
3. Implement upstream + SSE bridge against local mock upstream.
4. Implement server + `/health` using fake auth provider.
5. Implement auth provider/store.
6. Implement rotation engine.
7. Implement config bridge.
8. Implement token refresh.
9. Wire lifecycle, prefs, and UI.
10. Run integration tests and manual QA.

### Phase 1: Single-Account HTTP/SSE Proxy

Files:

- `Sources/MultiCodex/Features/Proxy/ProxyModels.swift`
- `ProxyServer.swift`
- `ProxyConnectionHandler.swift`
- `ProxyRequestParser.swift`
- `ProxyRequestRewriter.swift`
- `ProxyUpstreamClient.swift`
- `ProxySSEBridge.swift`
- `ProxyAuthProvider.swift`

Behavior:

- bind to `127.0.0.1`, preferred port from prefs
- accept HTTP/1.1 requests
- support `Content-Length`; reject chunked request bodies in v1 unless spike shows Codex uses them
- route `/responses` and `/models`
- route `GET /health` locally with privacy-minimized JSON
- stream upstream SSE without buffering full body
- pass SSE raw bytes; do not parse, split, coalesce, or reframe events
- propagate cancellation when downstream closes
- inject selected account Bearer token
- strip hop-by-hop headers
- set upstream `Host: chatgpt.com`
- honor downstream `Connection: close`; keep-alive support depends on spike results

Tests use pre-baked `config.toml` fixtures in temp managed homes. Production config writing starts in Phase 2.

Tests:

- parser tests for headers/body/keep-alive close
- rewriter tests for `/responses`, `/models`, unknown path
- health endpoint test with no account names/tokens in response
- auth provider tests for managed auth path, corrupt auth, missing token
- integration test with local upstream SSE server

### Phase 2: Config Bridge For Managed Homes

Files:

- `ProxyConfigBridge.swift`
- tests in `ProxyConfigBridgeTests.swift`

Behavior:

- write provider `base_url` into managed `config.toml`
- preserve existing unrelated config
- backup original value
- restore only if proxy-managed marker still present
- support port change by updating managed config

Tests:

- no config -> create config
- existing provider block -> update only `base_url`
- existing user custom provider keys preserved
- external edit after proxy write -> refuse blind restore

### Phase 3: Rotation Engine

Files:

- `ProxyAccountRotator.swift`
- `ProxyUsageSnapshotBridge.swift`
- `ProxyRotationPolicy.swift`

Behavior:

- use existing `AccountUsage` snapshots
- rotate safe routes on 429
- mark exhausted with cooldown
- expose status for UI
- never replay unsafe streaming route unless Phase 0 allowed it

Tests:

- ranking with missing usage
- cooldown expiry
- all accounts exhausted
- current account sticky
- concurrent requests serialize account state

### Phase 4: Token Refresh

Files:

- `ProxyTokenRefresher.swift`
- `ProxyAuthStore.swift`

Behavior:

- implement Codex-compatible JSON refresh
- parse optional refresh response fields
- preserve existing id token/access/refresh when omitted
- guarded write: reload auth first, compare account id/token, avoid overwriting newer disk auth
- invalidate auth cache after write

Tests:

- successful refresh updates auth
- omitted fields preserve old values
- unauthorized refresh marks permanent auth failure
- concurrent refresh single-flight per account
- newer disk auth prevents stale overwrite

### Phase 5: Preferences + UI

Files:

- `AppPreferencesStore.swift`
- `AccountsMenuViewModel.swift`
- `SettingsContentView` extensions
- `AccountsMenuContentView` status

Prefs:

- `proxyEnabled: Bool`
- `proxyPort: UInt16`
- `proxyRotationMode: ProxyRotationMode`
- `proxyCooldownSeconds5h: TimeInterval`
- `proxyCooldownSecondsWeekly: TimeInterval`
- `proxyMaxRotationsPerSession: Int`

UI:

- Settings section: Proxy
- Toggle enable/disable
- Port field
- Rotation mode segmented picker
- Cooldown controls
- status line: running/stopped, actual port, active account, exhausted count
- note: `Proxy routing applies only to MultiCodex-managed sessions. Terminal-launched Codex sessions connect directly unless opened through MultiCodex.`
- optional later button: open Terminal with managed `CODEX_HOME` and proxy config active
- menu status dot

### Phase 6: Optional ChatGPT Backend Proxy

Only implement if Phase 0 proves value.

Add:

- `chatgpt_base_url` config bridge
- route `/backend-api/wham/*`
- route `/backend-api/files` upload flow if needed
- route plugin/app endpoints only after endpoint inventory

### Phase 7: Optional Realtime Proxy

Only implement after separate websocket spike.

Add:

- `experimental_realtime_ws_base_url`
- websocket relay
- no mid-session rotation
- rotate only before session creation

## Test Commands

```bash
rtk just test
rtk just check
```

Add targeted SwiftPM tests if `just test` too broad during development:

```bash
rtk swift test --filter Proxy
```

## Manual QA

1. Create temp `MULTICODEX_HOME` and two managed accounts with fake upstream token fixtures.
2. Start proxy enabled.
3. Launch Codex with managed `CODEX_HOME`.
4. Verify `/models` reaches proxy and upstream mock.
5. Verify `/responses` streams token deltas without buffering.
6. Mock account A 429 on `/models`; verify proxy retries account B.
7. Mock all accounts exhausted; verify Codex receives upstream 429.
8. Stop MultiCodex; verify managed config restored or left with clear stopped-state warning.

## Risk Register

| Risk                                       | Impact | Mitigation                                                                         |
| ------------------------------------------ | ------ | ---------------------------------------------------------------------------------- |
| Path assumptions drift with Codex updates  | high   | Phase 0 path capture + unit tests against vendored Codex                           |
| Unsafe `/responses` replay duplicates turn | high   | request-boundary-only rotation                                                     |
| Global config corruption                   | high   | managed homes only                                                                 |
| Token refresh diverges from Codex          | high   | copy Codex JSON shape + guarded semantics                                          |
| Fake auth blocks spike                     | high   | fallback ladder; use real sandbox auth only with current-turn approval; scrub logs |
| Missing usage headers                      | medium | rely on existing usage refresh snapshots                                           |
| Proxy HTTP parser bugs                     | medium | narrow accepted request shapes; reject unknown/chunked initially                   |
| Multiple MultiCodex instances              | medium | loopback port lock + status warning                                                |
| Managed-home scope confuses users          | low    | explicit Settings copy and proxy-terminal option later                             |
| SSE chunk assumptions break streaming      | low    | raw byte passthrough; spike verifies merged chunks                                 |
| New Codex endpoint appears                 | medium | unknown route 502 with logged path; add route explicitly                           |

## File Manifest

New:

```text
Sources/MultiCodex/Features/Proxy/
  ProxyModels.swift
  ProxyServer.swift
  ProxyConnectionHandler.swift
  ProxyRequestParser.swift
  ProxyRequestRewriter.swift
  ProxyUpstreamClient.swift
  ProxySSEBridge.swift
  ProxyAuthProvider.swift
  ProxyAuthStore.swift
  ProxyTokenRefresher.swift
  ProxyAccountRotator.swift
  ProxyRotationPolicy.swift
  ProxyUsageSnapshotBridge.swift
  ProxyConfigBridge.swift
```

Tests:

```text
Tests/MultiCodexTests/ProxyRequestParserTests.swift
Tests/MultiCodexTests/ProxyRequestRewriterTests.swift
Tests/MultiCodexTests/ProxyAuthProviderTests.swift
Tests/MultiCodexTests/ProxyTokenRefresherTests.swift
Tests/MultiCodexTests/ProxyAccountRotatorTests.swift
Tests/MultiCodexTests/ProxyConfigBridgeTests.swift
Tests/MultiCodexTests/ProxyIntegrationTests.swift
```

Modified:

```text
Sources/MultiCodex/App/MultiCodexApp.swift
Sources/MultiCodex/Features/Shared/AccountsMenuViewModel.swift
Sources/MultiCodex/Infrastructure/Preferences/AppPreferencesStore.swift
Sources/MultiCodex/Features/Settings/SettingsContentView.swift
Sources/MultiCodex/Features/MenuBar/AccountsMenuContentView.swift
```

## Implementation Readiness Checklist

- [ ] Phase 0 spike complete.
- [ ] Route matrix updated from spike logs.
- [ ] Decision recorded for `/responses` replay: disabled or safe-pre-body only.
- [ ] Config target path confirmed: managed `CODEX_HOME/config.toml`.
- [ ] ChatGPT backend proxy decision recorded: v1 no or v1 yes.
- [ ] Realtime proxy decision recorded: v1 no unless websocket spike complete.
- [ ] Health endpoint response confirmed privacy-minimized.
