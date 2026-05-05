# Proxy Account Rotation Spike Plan

## Goal

Build a standalone FastAPI-based Codex proxy prototype that runs outside the macOS app, reuses existing MultiCodex accounts, and proves exact Codex CLI integration points before Swift/native implementation.

This spike answers:

- Which config keys route Codex requests through loopback?
- Which exact paths/methods/headers does Codex send for `/responses` and `/models`?
- Does `/responses` 429 arrive before any SSE bytes, making retry possibly safe?
- Does Codex use chunked request bodies or fixed `Content-Length`?
- Does Codex request keep-alive, and does it reuse sockets?
- Does managed `CODEX_HOME/config.toml` fully isolate proxy config from global user Codex?
- Can a standalone Python proxy select and rotate real MultiCodex account auth without mutating stored accounts?

## Deliverable

Implement prototype on a real working branch, not a throwaway branch.

Branch:

```bash
rtk git switch -c spike/fastapi-codex-proxy
```

Persist files in repo:

```text
tools/codex-proxy/
  pyproject.toml
  uv.lock
  README.md
  codex_proxy/
    __init__.py
    main.py
    accounts.py
    auth.py
    config_writer.py
    proxy.py
    rotation.py
    telemetry.py
  tests/
    test_accounts.py
    test_config_writer.py
    test_rotation.py
```

Add notes to sibling result file:

```text
docs/proxy-account-rotation-spike-results.md
```

Include:

- command used
- branch name and commit hash
- `MULTICODEX_HOME` used, with user-identifying paths redacted if needed
- captured request logs
- final route matrix
- account loading result: account count, current account, auth source kind only
- implementation decision list

## Prototype Server

Use FastAPI + Uvicorn + HTTPX.

Use `uv` for Python setup, dependency locking, and command execution.

Dependencies:

- `fastapi`
- `uvicorn[standard]`
- `httpx`
- `pydantic`
- `pytest`
- `pytest-asyncio`

`main.py` requirements:

- listen on `127.0.0.1:<port>` only
- log request method, path, headers, body length, first body bytes
- log `Connection` header and socket id for reuse tracking
- read MultiCodex account registry from `MULTICODEX_HOME`
- select account auth from managed homes first, legacy account auth second
- route `GET /health` with privacy-minimized JSON
- route `GET /models` to upstream `https://chatgpt.com/backend-api/codex/models`
- route `POST /responses` to upstream `https://chatgpt.com/backend-api/codex/responses`
- stream SSE bytes back without parsing/reframing
- support mock upstream mode for deterministic 429/SSE tests
- support live upstream mode for real Codex smoke test

Do not log tokens, full auth JSON, email, or account names by default. Logs may include account index, auth source kind, and stable redacted hash.

## MultiCodex Account Reuse

Default account root:

```text
MULTICODEX_HOME or ~/.config/multicodex
```

Load:

```text
<MULTICODEX_HOME>/config.json
```

Expected schema:

```json
{
    "version": 2,
    "currentAccount": "name",
    "accounts": {
        "name": {}
    }
}
```

Auth lookup for each account:

1. If `<MULTICODEX_HOME>/.managed-migration-complete` exists, check:

    ```text
    <MULTICODEX_HOME>/managed-homes/<sanitized-account>/auth.json
    ```

2. Fallback:

    ```text
    <MULTICODEX_HOME>/accounts/<account>/auth.json
    ```

Sanitize account names exactly like Swift `ManagedCodexHomeFactory.sanitize`: remove `/\:*?"<>|`.

Rules:

- read auth only
- never write account auth during spike except optional token-refresh test behind explicit flag
- skip account if auth missing/corrupt/no access token
- initial active account = `currentAccount` when usable, else first usable account sorted by name
- expose `/debug/accounts` only behind `--debug` and with redacted values

## Test Configs

### Config A: Provider Base URL Only

Dedicated prototype Codex home:

```text
tools/codex-proxy/.run/codex-home/config.toml
```

```toml
[model_providers.openai]
base_url = "http://127.0.0.1:<port>"
```

Expected:

- `/models` hits proxy as `GET /models?...`
- `/responses` hits proxy as `POST /responses`

### Config B: OpenAI Base URL

```toml
openai_base_url = "http://127.0.0.1:<port>"
```

Expected:

- verify whether it affects built-in `openai` provider in current Codex build
- record if it is better/worse than provider block

### Config C: ChatGPT Backend URL

```toml
chatgpt_base_url = "http://127.0.0.1:<port>/backend-api/"
```

Expected:

- app/backend endpoints hit proxy only when exercising features that use apps/files/wham
- normal `/responses` unchanged unless provider base URL also set

### Config D: Combined Provider + ChatGPT Backend URL

```toml
chatgpt_base_url = "http://127.0.0.1:<port>/backend-api/"

[model_providers.openai]
base_url = "http://127.0.0.1:<port>"
```

Expected:

- `/responses` hits proxy as `/responses`
- app/backend endpoints, if exercised, hit proxy under `/backend-api/...`
- config keys do not interfere with each other

## Auth Fixture

Primary path: reuse existing MultiCodex account auth from `MULTICODEX_HOME`.

Fake auth is only for unit tests of parsers/config. Do not use fake auth for live Codex routing unless explicitly testing startup validation failure.

Preferred first fixture:

```json
{
    "OPENAI_API_KEY": null,
    "tokens": {
        "id_token": {},
        "access_token": "fake-access-token",
        "refresh_token": "fake-refresh-token"
    },
    "last_refresh": "2026-05-05T00:00:00Z"
}
```

If this fails before HTTP:

1. Record exact error:

    ```bash
    rtk env CODEX_HOME="$PWD/tools/codex-proxy/.run/codex-home" HOME="$PWD/tools/codex-proxy/.run/home" codex exec "say hi" 2>&1 | rtk tee tools/codex-proxy/.run/auth-failure.log
    ```

2. Check for useful auth/debug flags:

    ```bash
    rtk codex --help 2>&1 | rtk grep -i "no-auth\\|skip-auth\\|debug"
    ```

3. Try `CODEX_ACCESS_TOKEN` bypass:

    ```bash
    rtk env CODEX_HOME="$PWD/tools/codex-proxy/.run/codex-home" HOME="$PWD/tools/codex-proxy/.run/home" CODEX_ACCESS_TOKEN="fake-token" codex exec "say hi"
    ```

    Record exact auth mode and final route. Do not assume env-token path equals normal ChatGPT auth.

4. Inspect Codex test helpers for accepted auth fixture.

5. If all fail with real MultiCodex account auth, document blocker. Scrub all tokens from logs and results before saving.

## Commands

Run all shell commands with `rtk`.

Setup:

```bash
rtk uv sync --project tools/codex-proxy
```

Start proxy in mock upstream mode:

```bash
rtk env CODEX_PROXY_UPSTREAM_MODE=mock uv run --project tools/codex-proxy uvicorn codex_proxy.main:app --host 127.0.0.1 --port 18099
```

Start proxy in live upstream mode:

```bash
rtk env CODEX_PROXY_UPSTREAM_MODE=live MULTICODEX_HOME="${MULTICODEX_HOME:-$HOME/.config/multicodex}" uv run --project tools/codex-proxy uvicorn codex_proxy.main:app --host 127.0.0.1 --port 18099
```

Write dedicated Codex home config:

```bash
rtk uv run --project tools/codex-proxy python -m codex_proxy.config_writer --codex-home "$PWD/tools/codex-proxy/.run/codex-home" --base-url "http://127.0.0.1:18099"
```

Run Codex with dedicated home:

```bash
rtk env CODEX_HOME="$PWD/tools/codex-proxy/.run/codex-home" HOME="$PWD/tools/codex-proxy/.run/home" codex --version
```

Then run minimal request path.

Preferred if app-server can trigger request:

```bash
rtk env CODEX_HOME="$PWD/tools/codex-proxy/.run/codex-home" HOME="$PWD/tools/codex-proxy/.run/home" codex -s read-only -a untrusted app-server
```

Use app-server RPC to trigger:

- `account/read`
- `account/rateLimits/read`
- a minimal thread/turn request if documented locally

Fallback:

```bash
rtk env CODEX_HOME="$PWD/tools/codex-proxy/.run/codex-home" HOME="$PWD/tools/codex-proxy/.run/home" codex exec "say hi"
```

Record exact command that actually triggers `/responses`.

## Delegation Plan

Use separate workers with disjoint write scopes. Workers are not alone in the codebase: do not revert others' edits; adapt to existing changes.

| Task                    | Owner scope | Files                                                                                 | Depends on                           | Done when                                                                             |
| ----------------------- | ----------- | ------------------------------------------------------------------------------------- | ------------------------------------ | ------------------------------------------------------------------------------------- |
| Python package scaffold | Worker A    | `tools/codex-proxy/pyproject.toml`, `uv.lock`, `README.md`, `codex_proxy/__init__.py` | branch created                       | `rtk uv sync --project tools/codex-proxy` works                                       |
| Account loader          | Worker B    | `codex_proxy/accounts.py`, `tests/test_accounts.py`                                   | scaffold                             | reads `config.json`, managed auth, legacy auth; redacted account summaries pass tests |
| Config writer           | Worker C    | `codex_proxy/config_writer.py`, `tests/test_config_writer.py`                         | scaffold                             | writes dedicated `CODEX_HOME/config.toml` for Config A/D without touching `~/.codex`  |
| Rotation state          | Worker D    | `codex_proxy/rotation.py`, `tests/test_rotation.py`                                   | account loader API shape             | current account selection, fallback order, 429 exhaustion pass tests                  |
| FastAPI proxy routes    | Worker E    | `codex_proxy/main.py`, `codex_proxy/proxy.py`, `codex_proxy/telemetry.py`             | account loader + rotation interfaces | `/health`, `/models`, `/responses` mock mode works                                    |
| Live smoke + results    | Integrator  | `docs/proxy-account-rotation-spike-results.md`                                        | all workers                          | route matrix, decisions, commands, sanitized logs recorded                            |

## Implementation Order

1. Create/switch to `spike/fastapi-codex-proxy`.
2. Scaffold `tools/codex-proxy` with `uv`.
3. Implement account loader and tests.
4. Implement config writer and tests.
5. Implement rotation state and tests.
6. Implement FastAPI mock upstream mode.
7. Add live upstream mode.
8. Run Codex smoke against dedicated `CODEX_HOME`.
9. Fill `docs/proxy-account-rotation-spike-results.md`.
10. Update main implementation plan route matrix if spike proves different behavior.

## Acceptance Criteria

- [ ] Changes exist on branch `spike/fastapi-codex-proxy`.
- [ ] Standalone FastAPI proxy runs from `tools/codex-proxy`.
- [ ] Python env and lockfile managed by `uv`.
- [ ] Proxy loads existing MultiCodex accounts from `MULTICODEX_HOME`.
- [ ] Proxy selects usable current account auth without copying tokens into Codex home.
- [ ] Proxy captures `GET /models` or documented why not called.
- [ ] Proxy captures `POST /responses`.
- [ ] Captured `/responses` request body transfer style: content-length or chunked.
- [ ] Captured `Connection` header from Codex requests.
- [ ] Captured whether Codex reuses same socket across `/models` and `/responses`.
- [ ] Captured important headers:
    - `Authorization`
    - `Accept`
    - `Content-Type`
    - `OpenAI-Beta`
    - `x-codex-*`
    - `x-openai-*`
- [ ] 429 mode shows Codex behavior:
    - no internal retry, or exact retry count
    - error surfaced to user/app-server
    - whether proxy could safely rotate before body bytes
- [ ] SSE prefix failure modes tested:
    - SSE error event after two events
    - connection drop after two events
    - no claim of HTTP 429 after headers, because that is not valid HTTP/1.1
- [ ] SSE chunk behavior documented:
    - event delimiter handling
    - whether merged chunks parse correctly
- [ ] Managed `CODEX_HOME/config.toml` works without editing real `~/.codex/config.toml`.
- [ ] `GET /health` works and does not include account names/tokens.
- [ ] Unit tests cover account loading, auth path precedence, config writer, rotation.
- [ ] Final route matrix written into results.

## Verification Commands

```bash
rtk uv sync --project tools/codex-proxy
rtk uv run --project tools/codex-proxy pytest
rtk uv run --project tools/codex-proxy python -m codex_proxy.config_writer --codex-home "$PWD/tools/codex-proxy/.run/codex-home" --base-url "http://127.0.0.1:18099"
rtk env CODEX_PROXY_UPSTREAM_MODE=mock uv run --project tools/codex-proxy uvicorn codex_proxy.main:app --host 127.0.0.1 --port 18099
```

## Implementation Decisions To Record

```text
provider_base_url_key = ?
chatgpt_base_url_needed_in_v1 = yes/no
responses_incoming_path = ?
models_incoming_path = ?
responses_body_transfer = content-length/chunked/other
responses_429_replay = disabled/safe-before-body
unknown_routes = reject/passthrough
auth_fixture_viable = fake/real/env-var/none
auth_fixture_method = ?
codex_auth_mode = ?
codex_connection_header = keep-alive/close/both
codex_reuses_connections = yes/no
health_endpoint_included = yes/no
toml_bridge_approach = strict-regex/manual-fixture
prototype_branch = ?
prototype_commit = ?
multicodex_home_source = env/default/flag
accounts_loaded = ?
usable_accounts = ?
auth_path_precedence = managed-home/legacy/mixed
standalone_proxy_viable = yes/no
uv_package_manager = yes/no
```

## Cleanup

Do not remove prototype files. They are persistent spike output.

Runtime-only cleanup:

```bash
rtk rm -rf tools/codex-proxy/.run
```

Do not delete real `~/.codex` files.

## FastAPI Prototype Details

Prototype should include:

```python
# 1. Connection tracking
#    Log socket id, Connection header, and whether Codex reuses socket.

# 2. Health endpoint
#    GET /health -> {"status": "ok", "requests_seen": N}

# 3. Request body logging
#    Log body length + first 200 bytes for POST /responses.
#    Log Transfer-Encoding and Content-Length.

# 4. SSE failure modes
#    sse-error-after-prefix: send two SSE events, then an SSE error event.
#    drop-after-sse-prefix: send two SSE events, then close socket.
#    Do not attempt "429 after SSE prefix"; HTTP status cannot change after headers.

# 5. Header capture
#    Log all request headers, including x-codex-*, x-openai-*, user-agent, accept-encoding.

# 6. MultiCodex account loader
#    Read config.json, managed-homes auth, legacy auth fallback.

# 7. Rotation
#    First pass: current account, then sorted usable accounts.
#    On mock/live 429 for /models, retry next account.
#    For /responses, no replay unless pre-body safety is proven.
```
