# Agent Sandbox Host Sleep Inhibition

Status: Draft implementation specification

Target: `agent-sandbox` / `agentbox`

Primary platform: macOS host with Colima-hosted Linux containers

Last updated: 2026-09-06

## 1. Summary

Add a narrow host capability that prevents macOS idle system sleep while at least one sandboxed agent is doing useful work. Release that inhibition when every agent is waiting for user input or has exited.

The container does not receive general host access. Agent lifecycle adapters send authenticated activity events to a host-side sleep broker. The broker aggregates renewable leases from all sandboxes and owns one macOS `caffeinate` process:

```text
Claude/Codex lifecycle hook
        |
        v
in-container activity bridge -- authenticated local RPC --> host sleep broker
                                                            |
                                  one or more live leases ---+
                                                            |
                                                            v
                                             /usr/bin/caffeinate -i
```

Core rule:

```text
one or more valid activity leases  -> idle system sleep inhibited
zero valid activity leases         -> normal host sleep policy restored
```

Display sleep and screen locking remain unaffected.

## 2. Problem statement

Locking a Mac does not itself stop Unix processes. The Mac may later enter idle system sleep after the display turns off. At that point the Colima VM, containers, agent process, subprocesses, and networking stop executing until the host wakes.

Wrapping `agentbox` itself in `caffeinate -i` is too broad. An interactive Claude or Codex process may remain open for hours while waiting at a prompt. The desired lifetime is an active agent turn, including relevant background work, rather than the lifetime of the terminal or sandbox.

An in-container `caffeinate` or Linux inhibitor cannot create a macOS power assertion across the VM boundary. The assertion must be owned on the host.

## 3. Goals

- Prevent macOS idle system sleep while a supported agent is actively reasoning, invoking tools, or supervising relevant background work.
- Allow display sleep and screen locking at all times.
- Restore normal system sleep after all supported agents become idle, fail, are interrupted, or exit.
- Support multiple concurrent sessions in one sandbox and multiple concurrent sandboxes.
- Expose only the ability to request a temporary activity lease. Do not expose host command execution or a general RPC mechanism.
- Make duplicate, delayed, and missing lifecycle messages safe through idempotency, generations, heartbeats, expiration, and teardown cleanup.
- Keep agent work running if the integration fails by default, while making the loss of sleep protection visible.
- Keep the host/backend interface agent-neutral so Codex and other agents can be added without changing the broker.

## 4. Non-goals

- Preventing display sleep, screen locking, manual sleep, lid-close sleep, shutdown, restart, or power loss.
- Waking a sleeping Mac for scheduled work.
- Keeping a cloud VM, remote machine, or container platform alive against provider suspension or termination.
- Replacing macOS power settings.
- Giving a container the Docker socket, a host shell, IOKit access, or a generic privileged sidecar.
- Proving whether an agent's work is useful. The feature trusts supported lifecycle adapters within the limits of the lease.
- Guaranteeing uninterrupted work after the host broker or `agentbox` itself crashes.
- Managing unrelated long-running user processes. Only registered agent sessions are in scope.

## 5. Terminology

- **Broker**: Host-side component that authenticates requests, tracks leases, and controls the platform backend.
- **Backend**: Platform implementation that acquires or releases the actual host sleep assertion.
- **Activity bridge**: Small, long-lived process in a sandbox that receives local adapter events and renews host leases.
- **Adapter**: Agent-specific translation from lifecycle events to `ACTIVE`, `QUIESCENT`, or `RELEASED`.
- **Lease**: Renewable, expiring claim that useful work is active.
- **Sandbox identity**: Random per-sandbox token and broker-side owner record.
- **Session key**: Privacy-preserving hash of the adapter name and agent session ID.

## 6. Required behavior

### 6.1 Functional requirements

1. An active turn must acquire host sleep protection before agent processing proceeds.
2. A turn may continue for any duration while the activity bridge remains healthy and renews its lease.
3. A completed turn with no relevant background work must become releasable without closing the agent process.
4. Waiting at an input prompt must not retain a lease beyond the configured quiescent timeout.
5. The broker must hold exactly one host assertion regardless of the number of valid leases.
6. Releasing one sandbox or session must not affect any other sandbox or session.
7. Sandbox teardown must revoke its token and remove all leases it owns.
8. If an activity bridge dies or loses contact, its leases must expire automatically.
9. A stale client must not be able to release a newer incarnation of the same logical lease.
10. Unsupported platforms must have explicit no-op or startup-failure behavior based on configuration.

### 6.2 Quality requirements

- Acquiring an already-running assertion should add less than 20 ms of host-side processing, excluding VM networking.
- Hooks must use short bounded timeouts. They must not hang an agent indefinitely.
- Lease expiry must use a monotonic clock.
- The broker must not persist tokens or leases to disk.
- Logs must never contain bearer tokens, prompt text, transcript contents, or raw agent session IDs.
- The endpoint must not bind to a LAN-reachable wildcard address by default.

## 7. Architecture

### 7.1 Components

```text
macOS host
+------------------------------------------------------------------+
| agentbox                                                         |
|                                                                  |
|  sandbox registry ---- token/owner lifecycle                     |
|          |                                                       |
|          +------> host activity broker ------> Darwin backend    |
|                         |                       (`caffeinate`)     |
|                         |                                        |
|                         +-- lease A: active                       |
|                         +-- lease B: quiescent                    |
|                         +-- lease C: expired                      |
+-----------------------------^------------------------------------+
                              | narrow authenticated HTTP RPC
                              | via runtime-provided host gateway
Colima VM                     |
+-----------------------------|------------------------------------+
| sandbox container           |                                    |
|  Claude hooks --> activity bridge --> renewal loop               |
|  future Codex adapter ------+                                    |
+------------------------------------------------------------------+
```

### 7.2 Host sleep broker

The broker should run inside the host-side `agentbox` process unless the current process model requires a dedicated child. It must:

- Register and revoke sandbox identities.
- Listen on an ephemeral, VM-reachable endpoint.
- Authenticate every lease operation.
- Scope every lease to the authenticated sandbox.
- Maintain the in-memory lease table and expiry timers.
- Serialize backend transitions so concurrent requests cannot start or stop competing `caffeinate` processes.
- Start the backend before acknowledging the first acquisition.
- Stop the backend after the final lease is released or expires.
- Retry an unexpectedly failed backend while leases remain valid.
- Expose host-local diagnostic status without exposing tokens or raw session identifiers.

The broker is not a network daemon intended to survive `agentbox`. Its state is deliberately ephemeral.

### 7.3 In-container activity bridge

The bridge is required because one-shot hooks cannot safely implement expiring leases for arbitrarily long turns.

The bridge should:

- Start before the supported agent process.
- Listen on a sandbox-local Unix socket such as `/run/agentbox/activity.sock`.
- Receive normalized lifecycle events from small hook commands.
- Keep one local state record per agent session.
- Acquire synchronously for `ACTIVE` transitions.
- Renew `ACTIVE` and retained `QUIESCENT` leases at the broker-specified interval.
- Release leases on definitive idle or termination events.
- Reacquire after `404`, generation conflict, or a transient broker restart when possible.
- Stop renewing when the bridge shuts down so TTL cleanup remains effective.

The hook executable and bridge may be modes of the same binary.

### 7.4 Adapter boundary

Agent adapters emit only normalized events:

```text
Active(session, reason)
Quiescent(session, reason, metadata)
Idle(session, reason)
Release(session, reason)
ReleaseAll(reason)
```

Agent-specific payloads must not cross the host RPC boundary. In particular, prompts, assistant messages, transcript paths, commands, task descriptions, and error details stay in the container.

## 8. Capability and trust boundary

The sleep endpoint is a capability, not an administrative API.

The authenticated client may only:

- Create or renew a lease owned by its sandbox.
- Release a lease owned by its sandbox.
- Learn whether its requested lease is protected and when it must renew.

It may not:

- Execute a host command.
- Select a backend command or command-line arguments.
- Release or enumerate another sandbox's leases.
- Request display wakefulness or stronger assertion types.
- Choose an unbounded server TTL.
- Read host process, power, path, user, or sandbox data.

The accepted residual risk is a local denial of sleep: a compromised sandbox holding a valid token can keep the host awake until its token is revoked, the sandbox exits, the configured hard limit is reached, or the broker stops. The token must not confer any broader authority.

## 9. Lease model

### 9.1 Identity

The broker keys a lease by:

```text
(sandbox_owner_id, session_key)
```

The bridge computes:

```text
session_key = base64url(SHA-256(adapter_name || NUL || raw_session_id))
```

This prevents raw session IDs from entering host logs or metrics. A collision is not a practical concern.

### 9.2 Expiration and renewal

- Default server TTL: 120 seconds.
- Default renewal interval: 30 seconds plus up to 10% jitter.
- Each successful acquire or renew sets `expires_at = monotonic_now + TTL`.
- The client must follow the server-returned TTL and renewal interval rather than assuming defaults.
- The broker sweeps expired leases at least every 5 seconds and also evaluates expiry before every aggregate-state decision.
- Wall-clock changes must not extend or shorten leases. A wall-clock expiry may be returned for display only.
- The client should retry transient renewal errors with bounded exponential backoff, never later than 75% of the current TTL.
- If a lease expires, the next activity or renewal attempt must reacquire it.

### 9.3 Idempotency and generations

- Repeated acquire for the same owner and session key is idempotent and renews the existing lease.
- A new lease incarnation receives a random `lease_id` and monotonically increasing in-memory `generation` for that key.
- Renew and release require both values.
- A request from an older generation must not modify a newer lease.
- Release is idempotent. Releasing an already-absent lease returns success with `released: false`.

### 9.4 Aggregate behavior

The broker uses set semantics, not an increment/decrement reference count. Duplicate events cannot inflate a count.

```text
valid lease set becomes non-empty -> ensure backend assertion is active
valid lease set remains non-empty -> keep the same assertion process
valid lease set becomes empty     -> stop backend assertion
```

The broker must never rotate or periodically replace a healthy assertion while leases remain. That would create an avoidable sleep race.

### 9.5 Multiple sandboxes and sessions

- Each sandbox receives a unique owner ID and token.
- The same Claude session ID in two sandboxes produces independent leases because owner identity is part of the key.
- One sandbox may own multiple simultaneous agent sessions.
- Token revocation removes all leases for that owner in one atomic broker operation.
- The backend remains active until the last lease across all owners disappears.

Example:

```text
sandbox A / session 1 active       lease A1
sandbox B / session 9 active       lease B9
sandbox C waiting                  no lease

release A1                         backend remains active for B9
destroy sandbox B                  B9 removed; backend stops
```

## 10. Lifecycle and state machine

### 10.1 Per-session bridge state

```text
                    Active
       +--------------------------------+
       |                                v
   RELEASED <---- Release ---------- ACTIVE
       ^                                |
       |                                | Quiescent
       |                                v
       +---- idle/max timeout ------ QUIESCENT
                                        |
                                        +---- Active ----> ACTIVE
```

State meanings:

- `RELEASED`: No host lease and no renewal loop.
- `ACTIVE`: Host lease required and renewed.
- `QUIESCENT`: The foreground response ended, but protection is temporarily retained because another stop hook may continue the turn or the definitive idle signal has not arrived.

### 10.2 Transition rules

| Event | Current state | Next state | Required action |
|---|---|---|---|
| User prompt submitted | any | `ACTIVE` | Acquire and wait for broker confirmation before agent processing continues |
| Repeated activity event | `ACTIVE` | `ACTIVE` | Idempotent renew/no-op |
| Stop with live background tasks | any leased state | `ACTIVE` | Retain and renew lease |
| Stop with no live background tasks | `ACTIVE` | `QUIESCENT` | Retain lease pending definitive idle or timeout |
| `idle_prompt` | `QUIESCENT` | `RELEASED` | Release immediately |
| Late/unmatched `idle_prompt` | `ACTIVE` | `ACTIVE` | Ignore because it is not correlated with the current active turn |
| Stop failure/API error | any | `RELEASED` | Release immediately |
| Launcher-observed `Ctrl-C` | `ACTIVE` | `QUIESCENT` | Start short interrupt grace; release unless new activity arrives |
| Session end | any | `RELEASED` | Release immediately |
| Sandbox teardown | any sessions | `RELEASED` | Revoke owner and remove all leases |
| Bridge death/network loss | any leased state | eventually `RELEASED` | Stop renewals; host TTL expires lease |

### 10.3 Quiescent timing

- Normal `Stop` does not release immediately. Claude can be continued by another `Stop` hook.
- The bridge retains and renews the lease until `idle_prompt` confirms sustained idleness for a session already in `QUIESCENT`.
- Default maximum time in `QUIESCENT`: 5 minutes. This prevents a missing `idle_prompt` from holding a lease indefinitely, including when typing suppresses the notification.
- Any new `Active` event cancels quiescent timers.
- Default interrupt grace: 5 seconds. `Ctrl-C` normally returns control to the prompt, so this path should release faster than ordinary stop handling.

## 11. RPC protocol

### 11.1 Transport

- HTTP/1.1 with JSON request bodies.
- Versioned path prefix: `/v1`.
- Endpoint injected as `AGENTBOX_HOST_ACTIVITY_ENDPOINT`, normally using `host.docker.internal:<ephemeral-port>`.
- Bearer token read from a mounted secret file. Environment-variable token injection is a compatibility fallback, not the default.
- Maximum body size: 8 KiB.
- Request timeout: 2 seconds by default; acquisition may use up to 5 seconds during backend startup.
- No redirects, cookies, compression, uploads, streaming, or user-controlled paths.

The listener must use the narrowest runtime-provided VM-to-host path available. Preferred order:

1. A Colima/Lima forwarding mechanism that exposes a host-loopback listener only to the VM.
2. A listener bound to the dedicated VM-facing host interface.
3. A wildcard listener only when the user explicitly enables `allow_wildcard_bind`.

Sandbox startup must probe the selected route. Do not assume that `host.docker.internal` can reach a loopback-only listener on every Colima version and network mode.

TLS is not required for a host-local VM transport that is not LAN-routable. If the only workable transport is LAN-routable, wildcard binding remains opt-in and must be called out in diagnostics.

### 11.2 Authentication header

```http
Authorization: Bearer <per-sandbox-token>
Content-Type: application/json
```

### 11.3 Acquire

```http
POST /v1/activity-leases/acquire
```

```json
{
  "protocol": 1,
  "session_key": "<base64url-sha256>",
  "adapter": "claude-code",
  "reason": "user_prompt_submit",
  "client_instance_id": "<random bridge instance id>"
}
```

Success:

```json
{
  "lease_id": "<random 128-bit id>",
  "generation": 3,
  "ttl_ms": 120000,
  "renew_after_ms": 30000,
  "backend": "darwin-caffeinate",
  "assertion_active": true
}
```

The broker must not return `assertion_active: true` until the backend process has started and survived an immediate startup check.

### 11.4 Renew

```http
POST /v1/activity-leases/renew
```

```json
{
  "protocol": 1,
  "lease_id": "<lease id>",
  "generation": 3
}
```

Success returns the current `ttl_ms`, `renew_after_ms`, backend name, and protection status.

### 11.5 Release

```http
POST /v1/activity-leases/release
```

```json
{
  "protocol": 1,
  "lease_id": "<lease id>",
  "generation": 3,
  "reason": "idle_prompt"
}
```

Success:

```json
{
  "released": true,
  "assertion_active": false
}
```

`assertion_active` reflects aggregate broker state. It may remain `true` because another lease exists.

### 11.6 Status and error handling

| Status | Meaning | Client action |
|---|---|---|
| `200` | Operation accepted | Update local lease state |
| `400` | Invalid version or body | Log adapter defect; do not retry unchanged request |
| `401` | Missing, revoked, or invalid token | Stop retries; surface configuration error |
| `404` | Lease expired or absent | Reacquire only if local state is still `ACTIVE`/retained `QUIESCENT` |
| `409` | Stale generation/client incarnation | Reacquire if still needed |
| `429` | Owner rate limit exceeded | Retry within TTL using server hint |
| `503` | Backend unavailable | Follow configured failure policy and retry while useful work remains active |

Error responses contain only a stable code and safe message. They must not echo authorization data or full request bodies.

## 12. Authentication and token model

- Generate 32 random bytes with the operating system cryptographic RNG for every sandbox launch.
- Encode tokens with unpadded base64url.
- Store only a cryptographic hash of the token in the broker registry if practical.
- Compare token hashes in constant time.
- Map each token to exactly one sandbox owner ID and its creation time.
- Never reuse a token after sandbox teardown.
- Revoke the token before or atomically with container destruction.
- Mount the token read-only at `/run/secrets/agentbox-host-activity-token` with mode `0400` for the sandbox user.
- Set `AGENTBOX_HOST_ACTIVITY_TOKEN_FILE` to that path.
- Never place the token in command-line arguments, URLs, logs, metrics, crash reports, or generated hook configuration.
- Redact the `Authorization` header at the first logging boundary.

Processes running as the same sandbox user can use the token. That is intentional: the capability boundary limits the result to temporary sleep inhibition. Stronger isolation between processes inside one sandbox is out of scope.

## 13. macOS backend

### 13.1 Command

Start `caffeinate` without a shell:

```text
/usr/bin/caffeinate -i -w <broker-pid>
```

- `-i` requests prevention of idle system sleep.
- Do not use `-d`; the display must remain free to sleep and lock.
- Do not use `-u`; it can wake or keep the display active.
- Do not use `-s`; it is AC-power-specific and stronger than required.
- `-w <broker-pid>` makes the assertion end when the broker exits, reducing orphan risk.
- Do not use a short `-t` process that must be periodically replaced. Keep one continuous process while the aggregate lease set is non-empty.

### 13.2 Backend state machine

```text
INACTIVE -> STARTING -> ACTIVE -> STOPPING -> INACTIVE
                 |        |
                 v        v
              DEGRADED <- unexpected child exit
```

- All transitions run through one serialized controller.
- First lease: spawn `caffeinate`, attach an exit watcher, perform an immediate liveness check, then acknowledge acquisition.
- Additional leases: reuse the existing healthy process.
- Final lease removed: send `SIGTERM`, wait up to 2 seconds, then force termination only if still necessary.
- Unexpected exit with live leases: mark protection degraded, retry immediately, then use exponential backoff capped at 5 seconds.
- New acquisitions while degraded return `503` unless a restart succeeds within the acquisition timeout.
- Broker exit: `-w` must cause the assertion to disappear even if normal child cleanup does not run.

### 13.3 Verification

Tests may use `pmset -g assertions` and process inspection to verify behavior, but production correctness must not depend on parsing human-readable `pmset` output.

An eventual native IOKit backend may replace `caffeinate`. It must preserve the same broker contract and assertion strength.

## 14. Claude Code adapter

### 14.1 Hook installation

Agent Sandbox should merge managed hooks into the sandbox's Claude settings without overwriting user hooks. Use synchronous command hooks for acquisition and short local bridge operations.

Illustrative configuration:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/usr/local/bin/agentbox-host-activity",
            "args": ["claude-hook"],
            "timeout": 5
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/usr/local/bin/agentbox-host-activity",
            "args": ["claude-hook"],
            "timeout": 2
          }
        ]
      }
    ],
    "StopFailure": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/usr/local/bin/agentbox-host-activity",
            "args": ["claude-hook"],
            "timeout": 2
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "/usr/local/bin/agentbox-host-activity",
            "args": ["claude-hook"],
            "timeout": 2
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/usr/local/bin/agentbox-host-activity",
            "args": ["claude-hook"],
            "timeout": 1
          }
        ]
      }
    ]
  }
}
```

The implementation must validate the schema against the minimum supported Claude Code version. If `args` is unavailable in that version, generate an equivalent fixed command string with no event-derived interpolation.

### 14.2 Event translation

The hook command reads one bounded JSON object from stdin and sends a normalized event over the sandbox-local Unix socket.

| Claude event | Translation |
|---|---|
| `UserPromptSubmit` | `Active(session_id, user_prompt_submit)` |
| `Stop` with non-empty `background_tasks` | `Active(session_id, background_tasks)` |
| `Stop` with empty/missing live background work | `Quiescent(session_id, stop)` |
| `StopFailure` | `Release(session_id, stop_failure)` |
| `Notification` where `notification_type == idle_prompt` | `Idle(session_id, idle_prompt)`; release only if currently `QUIESCENT` |
| `SessionEnd` | `Release(session_id, session_end)` |

`UserPromptSubmit` must wait until the bridge confirms a protected host lease, subject to the acquisition timeout and failure policy. Other events should complete after the bridge durably updates its in-memory state; they need not wait for a host release response because TTL is the fallback.

### 14.3 Version-sensitive assumptions

The implementation currently relies on these documented Claude Code behaviors:

- `UserPromptSubmit` runs before Claude processes the submitted prompt.
- `Stop` runs after the main agent finishes responding, except for user interruption.
- `Stop` includes `background_tasks` when the task registry is reachable.
- API failures use `StopFailure` instead of `Stop`.
- `idle_prompt` normally occurs about 60 seconds after Claude finishes responding if the user has not typed.
- `SessionEnd` is available for definitive cleanup and has a short execution budget.

These must be covered by adapter contract tests and rechecked when raising the minimum Claude version.

## 15. Edge cases

### 15.1 `Ctrl-C`

Claude's `Stop` hook does not run when the user interrupts a turn. Therefore hooks alone cannot provide correct cleanup.

The process that launches or attaches to Claude must observe the interrupt before forwarding it to Claude and notify the activity bridge. The bridge moves the current session to `QUIESCENT`, retains the assertion for the interrupt grace period, and releases unless a new activity event arrives.

If the current launcher architecture cannot observe interrupts reliably, the initial rollout must document this as a known limitation and add a conservative emergency cutoff. It must not claim complete stale-lease cleanup from hooks alone.

### 15.2 `StopFailure`

`StopFailure` means the foreground agent loop ended because of an API error. Release immediately. Current payloads do not provide the same background-task snapshot as `Stop`; preserving an unknown background task would risk an indefinite stale lease. If a future payload exposes live background work, the adapter may retain only when that list is explicitly non-empty.

### 15.3 `idle_prompt`

Treat `idle_prompt` as a definitive release signal for a session already in `QUIESCENT`, not the only cleanup mechanism. It may be delayed or suppressed while the user types. The quiescent maximum provides a backstop.

A late `idle_prompt` racing with a newly submitted prompt must not release the active turn. The bridge must ignore `idle_prompt` while its current state is `ACTIVE`. Broker generations separately prevent an old bridge or old host request from releasing a newer lease incarnation; they cannot correlate Claude events that lack a turn ID.

### 15.4 Stop hooks that continue the agent

Another `Stop` hook may block stopping and cause Claude to continue without a new `UserPromptSubmit`. For that reason, ordinary `Stop` enters `QUIESCENT` and retains renewal rather than releasing immediately. A later activity event returns the session to `ACTIVE`; `idle_prompt` or the quiescent maximum releases it.

### 15.5 Background tasks

- If `background_tasks` contains any entry whose status is live or unknown, retain `ACTIVE` by default.
- Ignore entries explicitly known to be terminal.
- Do not send descriptions, commands, server names, or other task data to the host.
- A later `Stop` with no live background tasks follows the normal quiescent path.
- If Claude never emits a later lifecycle event for a never-ending background task, the lease remains active while the bridge is healthy. Emit a long-lease warning; do not silently expire known active work.
- `session_crons` alone do not retain a lease. Scheduled future work is not current execution, and this feature does not wake a sleeping Mac.
- Provide an opt-out policy to ignore background tasks for users who prefer battery conservation over continuity.

### 15.6 Permission and elicitation prompts

Waiting for user approval during an active turn is still part of the turn. Keep the lease active. Otherwise the Mac could sleep while waiting and never receive the user's response or resume work. A future policy may release on long waits, but that is not the default.

### 15.7 Session switching and exit

`/clear`, `/resume`, logout, prompt-input exit, and container shutdown should reach `SessionEnd` when supported. Regardless, sandbox teardown revocation and lease TTL are authoritative cleanup paths.

### 15.8 Duplicate and reordered events

- Duplicate events are harmless because acquire and release are idempotent.
- The bridge serializes transitions per session.
- A release carries the generation it observed and cannot release a newer generation.
- If adapter events can include a stable turn/event sequence in the future, the bridge should reject older sequence numbers.
- In the absence of source sequence numbers, quiescent grace reduces risk but cannot prove ordering across an agent bug. Contract tests should verify ordering for every supported agent version.

## 16. Linux and cloud behavior

### 16.1 Platform interface

```text
HostActivityBackend
  Start() -> protected/error
  Healthy() -> boolean
  Stop() -> error
  Name() -> string
```

The broker and adapters must not contain Darwin-specific process logic.

### 16.2 macOS desktop

`auto` mode selects the `darwin-caffeinate` backend and enables the feature when the VM-to-host control path is available.

### 16.3 Linux desktop

Initial behavior is no-op unless a tested Linux backend is explicitly enabled. A future backend may use the systemd/logind inhibitor API, preferably through D-Bus rather than a shell wrapper. It must be tested against desktop idle sleep and must not claim support merely because `systemd-inhibit` exists.

In `required` mode, absence of a supported inhibitor fails sandbox startup.

### 16.4 Cloud and headless hosts

Cloud/headless mode is a declared no-op. Do not start an RPC listener, inject a token, or install agent hooks solely for this feature. Log one debug-level message explaining that provider lifecycle is outside the feature's scope.

Platform mode should come from Agent Sandbox runtime context, not only `GOOS`; a headless Darwin/Linux machine may still need explicit configuration.

## 17. Stale lease cleanup

Cleanup mechanisms, from fastest to slowest:

1. Definitive adapter release (`idle_prompt`, `StopFailure`, `SessionEnd`).
2. Launcher-observed interrupt.
3. Sandbox teardown owner revocation.
4. Activity bridge shutdown, followed by TTL expiry.
5. Lost network or killed container, followed by TTL expiry.
6. Broker exit, which ends the broker-bound `caffeinate` assertion.

Additional rules:

- The host lease table is never restored after broker restart.
- A sweep must remove all expired entries before deciding whether the backend is still needed.
- Owner revocation and aggregate backend reevaluation must be atomic with respect to lease operations.
- Long-lived leases should emit a warning at a configurable age, default 8 hours, and then no more than once per hour.
- A configurable hard continuous-duration limit may be offered but should default to disabled. Enabling it trades task continuity for battery/thermal protection and must be explicit.

## 18. Failure handling

### 18.1 Default policy: warn and continue

Loss of sleep protection should not block agent work by default.

- Acquisition failure: show one concise warning in the terminal, record a structured event, and allow the agent turn to continue.
- Renewal failure: retry within the TTL and warn only when protection is actually at risk or lost.
- Release failure: update local state to released, retry briefly, then rely on TTL.
- Logging failure: never affect the agent or broker.
- Malformed hook input: ignore safely, emit a rate-limited adapter error, and do not send payload contents to the host.

### 18.2 Required policy

For users who require the guarantee, `failure_policy = "block"` makes a failed initial acquisition prevent a new turn from starting. This mode must be opt-in. It still cannot protect against host process death after acquisition.

### 18.3 Broker/backend failure

- If `caffeinate` cannot start, do not report the lease as protected.
- Keep valid leases in memory while retrying the backend.
- If `caffeinate` exits unexpectedly, mark all leases temporarily unprotected and restart without deliberately dropping or recreating healthy leases.
- Rate-limit warnings to avoid flooding all attached terminals.
- A broker panic/exit must not leave an orphan assertion.

## 19. Security considerations

- Use direct process execution with fixed `/usr/bin/caffeinate` arguments. Never interpolate request data into a shell command.
- Bind only to the runtime-specific VM control path by default.
- Require authentication on every container-reachable endpoint, including status endpoints.
- Keep host-only diagnostics on a Unix socket or existing `agentbox` control channel.
- Apply per-owner rate limits, such as 10 requests/second sustained with a small burst. Normal renewal traffic is far below this.
- Bound body size, field lengths, JSON depth, connection count, header size, and request duration.
- Accept only known protocol versions, adapter names, reasons, and base64url identifiers.
- Do not accept client-selected commands, PIDs, assertion flags, bind addresses, TTLs, or owner IDs.
- Prevent token A from observing or modifying token B's leases.
- Clear token material from in-memory request objects when practical and always redact it from diagnostics.
- Keep endpoint discovery and token distribution separate; knowing the port is not authorization.
- Treat wildcard binding as a security downgrade requiring explicit user consent.
- Threat-model battery depletion as the principal intentional abuse case.

## 20. Observability and logging

### 20.1 Structured events

Emit structured records for:

- Broker started/stopped and selected backend.
- Sandbox owner registered/revoked.
- Lease acquired, renewed after recovery, quiescent, released, or expired.
- Aggregate lease count transitions.
- Backend started, stopped, unexpectedly exited, restarted, or degraded.
- Authentication failure, rate limiting, malformed request, and unsupported protocol.
- Hook/bridge acquisition failure and protection restoration.
- Long-lived leases.

Safe fields:

```text
timestamp
level
event
backend
owner_id_hash
session_key_prefix (8-12 characters only)
adapter
reason enum
lease_age_ms
lease_count
protected boolean
error_code
```

Unsafe fields that must never be logged:

```text
bearer token or token hash in full
raw session ID
prompt or response text
transcript path/content
background command or task description
HTTP Authorization header
full request body
```

### 20.2 User diagnostics

Add a host-local diagnostic command, for example:

```text
agentbox sleep-status
```

It should report:

- Feature mode and backend.
- Whether the host is currently protected.
- Number of active/quiescent leases and owning sandboxes.
- Oldest lease age.
- Last backend error.
- Whether the listener uses a runtime-private or wildcard bind.

Do not show tokens or raw agent session IDs.

### 20.3 Metrics

If metrics already exist, add counters/gauges for current leases, assertion-active state, acquisitions, expirations, backend failures, authentication failures, and total protected duration. Avoid unbounded labels such as sandbox or session IDs.

## 21. Configuration

Suggested configuration:

```toml
[host_sleep]
mode = "auto"                    # off | auto | required
failure_policy = "warn"          # warn | block
power_source = "always"          # always | ac_only
lease_ttl = "120s"
renew_interval = "30s"
quiescent_timeout = "5m"
interrupt_grace = "5s"
background_tasks = "inhibit"     # inhibit | ignore
long_lease_warning = "8h"
max_continuous_lease = "0s"      # 0 disables the hard limit
allow_wildcard_bind = false
```

Validation:

- `renew_interval` must be less than half of `lease_ttl`.
- `lease_ttl` must be at least 30 seconds and no more than 10 minutes.
- `interrupt_grace` must not exceed `quiescent_timeout`.
- A nonzero hard limit must be greater than `lease_ttl`.
- `required` plus an unsupported backend or unreachable control path fails before launching the agent.
- `ac_only` must release protection promptly after switching to battery and reacquire on AC if work remains active. This can suspend active work and should produce a one-time warning.

CLI flags may override configuration for one invocation, but secrets and endpoint addresses must not be user-settable through untrusted project configuration.

## 22. Testing plan

### 22.1 Unit tests

- Per-session state transitions, including duplicate events.
- Ordinary stop, stop-hook continuation, idle timeout, and interrupt grace.
- Background-task and session-cron policy.
- Lease idempotency, TTL renewal, expiration, and generation conflicts.
- Multiple sessions and owner isolation.
- Atomic owner revocation.
- Monotonic timing under wall-clock jumps.
- Backend start/stop serialization under concurrent acquire/release.
- Unexpected backend exit and retry backoff.
- Token creation, hashing, constant-time validation, and revocation.
- Payload limits, enum validation, and redaction.
- Configuration defaults and invalid combinations.

Use a fake monotonic clock and fake backend. State-machine tests should be table-driven.

### 22.2 Protocol tests

- Valid acquire/renew/release lifecycle.
- Duplicate acquire and release.
- Expired and stale-generation renewals.
- Wrong, missing, revoked, and cross-sandbox tokens.
- Oversized/malformed JSON and unsupported protocol version.
- Rate limiting and bounded timeouts.
- Confirm that request bodies and authorization data never appear in logs.

### 22.3 Bridge and adapter tests

- Feed recorded/synthetic Claude payloads for every supported hook event.
- Verify prompt text, transcript paths, commands, and error details are discarded.
- Verify synchronous acquisition acknowledgement for `UserPromptSubmit`.
- Verify `Stop` with live `background_tasks` remains active.
- Verify `Stop` with no live tasks enters quiescence.
- Verify `idle_prompt`, `StopFailure`, and `SessionEnd` release.
- Verify bridge renewal across a turn longer than several TTLs.
- Kill the bridge and verify host expiry.
- Simulate late release from an old generation after reacquisition.
- Validate generated hook configuration alongside existing user hooks.
- Run contract tests against the minimum and latest supported Claude Code versions.

### 22.4 Host integration tests

On macOS:

- Acquire the first lease and verify exactly one `caffeinate` process exists.
- Add multiple leases and verify the same process remains.
- Release all but one and verify the assertion remains.
- Release/expire the final lease and verify the process exits.
- Kill `caffeinate` with live leases and verify restart plus degraded telemetry.
- Kill the broker and verify `caffeinate -w` exits.
- Use `pmset -g assertions` in tests to confirm a `PreventUserIdleSystemSleep` assertion while protected.
- Confirm no display-sleep assertion is created.

With Colima:

- Probe the selected `host.docker.internal` path from a real container.
- Test default, changed gateway, and supported network modes.
- Confirm the listener is not reachable over the LAN in the default configuration.
- Destroy a container without cleanup and verify TTL expiration.
- Run two sandboxes concurrently and verify aggregation.

### 22.5 End-to-end agent tests

- Start Claude, submit a turn longer than one TTL, and verify continuous assertion coverage.
- Let Claude finish, do not type, and verify release after `idle_prompt`.
- Type without submitting after completion and verify release by quiescent timeout.
- Interrupt an active turn with `Ctrl-C` and verify release after interrupt grace.
- Trigger a simulated API error and verify `StopFailure` release.
- Run a background task reported by `Stop`; verify protection remains until a later terminal event.
- Leave Claude open at its prompt and verify the Mac is eligible for idle sleep.

A gated hardware test may use a dedicated lab Mac to confirm that a VM/container continues making progress after display lock and beyond the configured idle-sleep interval. Do not run disruptive sleep tests on ordinary developer or CI machines.

## 23. Rollout plan

### Phase 0: compatibility spike

- Confirm the repository's host/container process boundaries.
- Confirm a non-LAN-routable Colima VM-to-host listener strategy across supported Colima versions.
- Validate Claude hook payloads and ordering against the minimum supported version.
- Demonstrate `caffeinate -i -w <broker-pid>` lifecycle and assertion type.
- Prove launcher-level `Ctrl-C` observation or explicitly record the limitation.

Exit criterion: a written compatibility matrix and a passing vertical prototype.

### Phase 1: internal, disabled by default

- Implement broker, fake backend, activity bridge, token lifecycle, and Claude adapter.
- Ship behind `host_sleep.mode = "off"` by default.
- Add status diagnostics and structured logs.
- Run automated unit/protocol tests and manual macOS/Colima tests.

Exit criterion: no leaked tokens/content, correct multi-sandbox aggregation, and reliable cleanup in fault injection.

### Phase 2: opt-in macOS beta

- Enable with `mode = "auto"` only for explicit beta users.
- Collect counts and error codes, not session content.
- Track acquisition latency, unexpected backend exits, stale expirations, long leases, and wildcard-bind requests.
- Publish known limitations, especially interrupt handling if incomplete.

Exit criterion: low failure rate, no orphan assertions, and verified idle release in real workflows.

### Phase 3: default-on macOS

- Make `auto` the default for interactive local macOS sandboxes.
- Preserve `off`, `required`, power-source, and background-task controls.
- Add upgrade notes explaining that display lock still works and battery use may increase during active work.

Exit criterion: support readiness and regression coverage across supported macOS and Colima versions.

### Phase 4: additional adapters/backends

- Add Codex adapter after lifecycle-event contract testing.
- Evaluate a native IOKit backend.
- Evaluate a Linux systemd/logind backend.
- Keep cloud behavior explicit and no-op.

## 24. Future Codex adapter

The host broker requires no Codex-specific changes. Add only an adapter that maps Codex lifecycle signals to the normalized bridge events.

Preferred event mapping:

```text
turn/user-prompt start -> Active
turn complete          -> Quiescent
interrupt              -> Release or short interrupt grace
session end            -> Release
known background work  -> Active until terminal
```

Current Codex configuration documentation exposes lifecycle hooks including `UserPromptSubmit`, `Stop`, `Interrupt`, and `SessionEnd`. Exact payload, ordering, background-work visibility, and CLI-version support must be verified before implementation. Do not build the adapter from notification-only events if those events cannot prove turn start.

Codex may also have its own sleep-inhibition behavior on a native macOS client. That does not eliminate this feature for a Linux container inside Colima, where a guest assertion cannot control host power. Duplicate native assertions are safe but should be observable so redundant integration can be disabled if appropriate.

If Agent Sandbox launches Codex through an SDK or app-server protocol, prefer authoritative turn-start/turn-terminal events from that protocol over file watching or terminal-output heuristics.

## 25. General agent adapter requirements

A new adapter is acceptable only if it can answer:

- What event occurs before useful work starts?
- What event proves the foreground turn is finished?
- How are user interrupts reported?
- How are API/tool failures reported?
- Can background work outlive the foreground response, and how is it observed?
- What definitive session-exit event exists?
- Are events ordered and uniquely identified?
- Can the start event synchronously wait for acquisition?

If an agent lacks reliable start and terminal signals, support must be marked best-effort. Do not use CPU utilization, terminal output silence, or transcript modification time as the primary lifecycle detector; all can be quiet during legitimate long-running work.

## 26. Acceptance criteria

The feature is complete for the macOS/Claude milestone when all of the following hold:

- An active Claude turn keeps a continuous `PreventUserIdleSystemSleep` assertion across multiple lease TTLs.
- The display can still sleep and the screen can still lock.
- An open Claude session waiting for input releases protection within the documented idle/quiescent window.
- `Ctrl-C`, `StopFailure`, `SessionEnd`, bridge death, container death, and sandbox teardown all have verified cleanup paths.
- Reported live background tasks retain protection; scheduled future cron work alone does not.
- Multiple sandboxes share one `caffeinate` process, and removing one does not affect the others.
- A stale generation cannot release a newer lease.
- An invalid or cross-sandbox token cannot observe or modify leases.
- `agentbox sleep-status` accurately reports aggregate state without sensitive data.
- Default listener configuration is not LAN-reachable.
- No token, prompt, response, transcript, or background command appears in logs.
- Failure behavior matches `warn` and `block` policies.
- Unsupported Linux/cloud behavior is explicit and tested.

## 27. References

- [Claude Code hooks reference](https://code.claude.com/docs/en/hooks)
- [Codex configuration reference](https://developers.openai.com/codex/config-reference/)
- [Colima default networking configuration](https://github.com/abiosoft/colima/blob/main/embedded/defaults/colima.yaml)
- Local macOS manual pages: `man caffeinate` and `man pmset`

These interfaces are version-sensitive. Revalidate them during Phase 0 and whenever the minimum supported Claude Code, Codex, Colima, or macOS version changes.
