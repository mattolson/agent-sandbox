# Task: m15.2 - Secret Source and Transforms

## Summary

Add backend-neutral secret resolution with the first file-backed resolver and generic `basic` / `bearer` header
transforms.

## Scope

- Resolve logical secret IDs from `AGENTBOX_SECRET_SOURCE=file:/run/agentbox/secrets`
- Map each logical secret ID to one path-safe file below the mounted secret directory
- Keep the resolver boundary context-aware enough to add project or target scoped overlays later without changing policy
  syntax
- Define whether file secret changes are visible on the next request or only after proxy reload
- Validate missing sources, missing secret files, invalid IDs, and unsafe file permissions with actionable errors or
  warnings
- Implement transform helpers for `basic` and `bearer`
- Exclude compose/scaffold changes and request injection

## Acceptance Criteria

- [ ] Unit tests cover successful file resolution, missing secrets, path traversal attempts, permission validation, and
      both transforms
- [ ] Secret values never appear in errors unless a test deliberately asserts internal helper behavior with redacted
      output
- [ ] Secret value freshness is documented and covered by a resolver test

## Applicable Learnings

- `/opt/proxy-python/bin/python3` is the canonical interpreter for proxy test runs.
- Shared proxy helper modules used by both `render-policy` and addons must account for the image layout. Renderer
  helpers live under `/usr/local/lib/agent-sandbox/proxy`, while addons run from `/home/mitmproxy/addons`.
- Rule-scoped policy metadata should be attached before host-record merge and dedupe; m15.2 should preserve that
  boundary by resolving values separately from policy rendering.
- The proxy sidecar is the enforcement boundary. Secret resolution belongs in proxy-owned helper code, not in the agent
  container or workspace.
- Permission checks on bind-mounted files can vary across macOS, Linux, and CI. Treat unsafe mode bits as actionable
  warnings unless they are the only thing protecting the agent from reading the secret.

## Plan

### Files Involved

- `images/proxy/secret_resolver.py` - new backend-neutral resolver API, file-backed resolver, permission checks,
  freshness behavior, redaction-safe errors, and header transform helpers
- `images/proxy/policy_injection.py` - reuse existing secret ID and transform normalization helpers; only adjust if
  implementation ergonomics require a small shared helper
- `images/proxy/Dockerfile` - package the new resolver helper into `/usr/local/lib/agent-sandbox/proxy`
- `images/proxy/tests/test_secret_resolver.py` - unit coverage for source parsing, file resolution, permissions,
  freshness, redaction, path safety, and transforms

### Approach

Add a small resolver module that is generic at the boundary but only implements `file:` sources in this task. The public
shape should be narrow:

- `SecretResolver.from_env(env=os.environ)` parses `AGENTBOX_SECRET_SOURCE`
- `resolve(secret_id, context=None)` returns a redaction-safe secret value object plus any permission warnings
- `render_header_value(secret_value, transform)` applies the canonical m15.1 `basic` or `bearer` transform

Use the m15.1 secret ID validation so policy rendering and runtime resolution reject the same IDs. The file resolver
should map `secret_id` directly to `root / secret_id`, reject non-direct children, reject symlinks and non-regular files,
and fail cleanly for missing roots or missing secret files.

Define freshness as request-time reads: each `resolve()` call stats and reads the secret file. That means creating or
modifying a file inside an already-mounted source becomes visible on the next resolve without proxy reload or container
rebuild. This avoids in-memory secret caching and gives m15.4 a simple per-request contract.

Read file contents as raw bytes, accept one trailing newline or CRLF as authoring convenience, and reject remaining CR,
LF, or NUL characters before producing a header value. Keep the returned value out of `repr()`, exceptions, warnings,
and test failure helper output.

Permission checks should warn, not hard fail, for group/other-readable or writable source directories and secret files.
Hard failures should be reserved for conditions that make resolution invalid: missing source config, unsupported source
scheme, missing root, root not a directory, invalid ID, missing secret file, symlink, non-regular file, unreadable file,
or invalid secret bytes. This avoids breaking common bind-mount setups while still surfacing unsafe host-side setup.

Do not wire the resolver into `PolicyMatcher` or `PolicyEnforcer` yet. m15.2 should produce tested primitives for m15.4
to call when request header mutation is implemented.

### Implementation Steps

- [ ] Create `images/proxy/secret_resolver.py` with redaction-safe error, warning, context, and result types
- [ ] Add `AGENTBOX_SECRET_SOURCE` parsing for `file:<absolute-root>` and clear errors for missing or unsupported
      sources
- [ ] Implement file resolver root validation and per-secret path mapping
- [ ] Reuse m15.1 secret ID validation for runtime resolution
- [ ] Reject path traversal attempts, symlink secret files, non-regular files, and missing secret files
- [ ] Implement request-time file reads and document that file changes are visible on the next resolve
- [ ] Add permission warning checks for source directory and secret file mode bits
- [ ] Implement `bearer` and `basic` header transform helpers
- [ ] Ensure secret values are redacted from exceptions, warnings, and object representations
- [ ] Package `secret_resolver.py` in the proxy image
- [ ] Add `test_secret_resolver.py` coverage for acceptance criteria and edge cases
- [ ] Run `/opt/proxy-python/bin/python3 -m unittest discover -s images/proxy/tests -p 'test_*.py'`

### Open Questions

- Confirm permission findings should be non-fatal warnings. Recommended default: warnings, because the proxy-only mount
  is the security boundary and bind-mounted POSIX modes are not uniformly reliable across target platforms.

## Outcome

### Acceptance Verification

Pending implementation.

### Learnings

Pending implementation.

### Follow-up Items

Pending implementation.
