---
name: operating-in-agent-sandbox
description: Read this when you are an AI coding agent running inside an Agent Sandbox container. Explains the network proxy, allowlist policy, filesystem/git constraints, how to discover your own limits from the read-only .agent-sandbox directory, and what to do when a request fails with "Blocked by proxy policy" (HTTP 403) or a direct connection is refused. Use it before fighting a network/permission error or concluding a tool is broken.
---

# Operating Inside an Agent Sandbox

Agent Sandbox runs AI coding agents inside a locked-down local container. If you are
reading this from inside one, your network is restricted and your filesystem is partly
read-only **by design**. This is not a bug. Knowing the rules lets you work with the
sandbox instead of wasting turns fighting it.

This skill is generic. The **authoritative, current** constraints for your specific
sandbox always live in the read-only `.agent-sandbox/` directory in your project root.
Read those files; do not rely on memory or assumptions.

## Am I in a sandbox?

You are almost certainly inside an Agent Sandbox if any of these hold:

- `HTTP_PROXY` / `HTTPS_PROXY` are set to `http://proxy:8080`.
- A read-only `.agent-sandbox/` directory exists at the workspace root.
- You are the non-root user `dev` (uid 501) and lack general `sudo`.
- A proxy CA certificate is mounted at `/etc/mitmproxy`.

## The network model (two enforcement layers)

1. **Firewall (in your container).** All direct outbound traffic is dropped. Only the
   Docker host network — which includes the proxy sidecar — is reachable. A direct
   connection that bypasses the proxy is rejected immediately (ICMP admin-prohibited),
   so it fails fast rather than hanging. SSH outbound is disabled.

2. **Proxy (the `proxy` sidecar).** All HTTP/HTTPS must go through `http://proxy:8080`.
   The standard proxy env vars are already set, so most tools (curl, git, package
   managers, language toolchains) use it automatically. The proxy enforces a
   **domain/service allowlist**. Anything not on the allowlist is blocked.

   - A blocked request returns **HTTP 403** with body `Blocked by proxy policy: <host>`.
   - For HTTPS, the blocking CONNECT is refused before the tunnel opens.

The proxy is a TLS-terminating man-in-the-middle. Its CA cert is installed in the
container's system trust store. Tools that use the system store just work. A tool that
ships its own CA bundle (some Node, Python, Go setups) may report a certificate error —
point it at the proxy CA file `/etc/mitmproxy/ca.crt` (e.g. `NODE_EXTRA_CA_CERTS`,
`REQUESTS_CA_BUNDLE`, `SSL_CERT_FILE`) rather than disabling verification.

## Discover your actual limits

The single most useful file is the **effective allowlist**, written by the proxy:

- `/run/agentbox/policy.yaml` — the complete, sanitized list of hosts
  reachable through the proxy, with their allowed schemes/methods/paths. This is the
  merged result of every policy layer (agent baseline + user policy), rewritten on proxy
  startup and on each successful policy reload (`SIGHUP`). If a host is not in this file, requests
  to it return HTTP 403. Credentials and request-rewriting rules are intentionally
  omitted. (Older sandboxes may not export this file yet; if it is missing, fall back to
  the `.agent-sandbox/` files below and to probing.)

For the editable inputs and your runtime config, read these under the read-only
`.agent-sandbox/` mount:

- `active-target.env` — which agent is active and the project name.
- `policy/user.policy.yaml` — shared user-owned allowlist (applies to every agent).
- `policy/user.agent.<agent>.policy.yaml` — extra allowlist for the active agent only.
- `compose/base.yml` and `compose/agent.<agent>.yml` — mounts, volumes, and env you run with.

Note: the `.agent-sandbox/policy/*.yaml` files show only the **user-editable** layer.
Each agent also has a **baseline** allowlist (its own API, auth, and CDN endpoints) that
is merged in but is not authored in these files. The baseline *is* reflected in
`/run/agentbox/policy.yaml`. When unsure whether a host is allowed, check
that file, or just try the request and read the result.

Allowlist entries take two forms:

```yaml
services:          # symbolic bundles, e.g. github, claude — expand to known host sets
  - github
domains:           # explicit hosts; wildcards like "*.example.com" are allowed
  - raw.githubusercontent.com
```

## Quick checks you can run

```bash
# Should succeed only if api.github.com is on the allowlist:
curl -sS -o /dev/null -w '%{http_code}\n' https://api.github.com

# A 403 body of "Blocked by proxy policy: <host>" means the host is not allowed.
# A direct (non-proxy) attempt is refused by the firewall, not the proxy:
curl --noproxy '*' --connect-timeout 3 https://example.com   # expected to fail
```

## What you cannot do (stop and don't retry)

- **You cannot change network policy from inside the container.** `.agent-sandbox/` is
  mounted read-only, and policy only takes effect after a proxy reload or restart, which
  is a host-side action. Editing those files from inside will fail or have no effect.
- **The `agentbox` CLI is not yours to run** — it runs on the host, not in this
  container.
- **You cannot bypass the firewall or proxy.** No SSH, no direct sockets, no alternate
  egress. Retrying a blocked request, disabling TLS verification, or hunting for another
  route wastes turns and won't work.

## What to do when something is blocked

1. Confirm the cause. `Blocked by proxy policy: <host>` = host not on the allowlist.
   A connection refused/admin-prohibited on a direct attempt = firewall; route it
   through the proxy instead (usually automatic via the env vars).
2. Check whether the host is already allowed in `/run/agentbox/policy.yaml`
   (or, failing that, `.agent-sandbox/policy/*.yaml`).
3. Prefer an allowlisted alternative if one exists (e.g. a mirror or registry that is
   already permitted).
4. If you genuinely need a blocked host, **ask the human** rather than working around
   it. Give them the exact host(s) and a ready-to-paste snippet, e.g.:

   > I need outbound access to `pypi.org` and `files.pythonhosted.org`. Add to
   > `.agent-sandbox/policy/user.policy.yaml`:
   > ```yaml
   > domains:
   >   - pypi.org
   >   - files.pythonhosted.org
   > ```
   > Then on the host run `agentbox proxy reload` to apply it (or
   > `agentbox compose restart proxy`).
   > (`agentbox policy config` shows the effective allowlist.)

## Filesystem and git

- `/workspace` is your project and is writable. `.agent-sandbox/` is read-only.
- Git remotes are rewritten from SSH to HTTPS, and outbound git goes through the proxy.
  Push/pull works only for repos the policy allows.
- Credentials are injected at the proxy via credential shims; you generally will not see
  raw tokens as env vars, and you do not need them — authenticated requests to allowed
  services are handled for you.

## Bottom line

Treat blocks as guardrails carrying information, not obstacles to defeat. Read
`.agent-sandbox/` to learn the rules, prefer what's already allowed, and when you truly
need more access, hand the human a precise, minimal request they can apply on the host.
