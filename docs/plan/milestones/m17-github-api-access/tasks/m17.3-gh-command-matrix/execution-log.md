# Execution Log: m17.3 - gh command matrix

## 2026-09-06 - Re-run complete on host-rebuilt images

Ran the matrix against GitHub with the rebuilt proxy and base images. 17 of 17 read and negative checks passed, the
write phase passed, and merge on the real PR #187 was refused by the proxy.

**Issue:** The first proxy rebuild predated the https-only commit by two minutes; the rendered git rules still
listed `http`. Diagnosed from the sanitized policy view rather than by sending a plaintext request, since on the old
code that request would have forwarded the real token in the clear.
**Solution:** Host rebuilt the proxy from the branch head and recreated it with `compose up -d proxy`.

**Issue:** This session's shell predates the policy reload, so `GH_TOKEN` was not exported.
**Solution:** The script sources `/run/agentbox/credential-shims/init.zsh` when the variable is unset, which is what
a fresh shell does. Confirms the documented fresh-shell caveat.

**Issue:** Plaintext `http://` probes returned curl error 000, not a proxy 403.
**Solution:** `curl` ignores uppercase `HTTP_PROXY` for `http://` URLs, went direct, and hit the firewall. Re-sent
with `-x http://proxy:8080`: 403 from the proxy for both hosts, nothing forwarded.

## 2026-09-06 - Planned; blocked on a host build

The re-run needs rebuilt base and proxy images and a proxy reload, none of which can happen from inside the sandbox.
Everything that could be proven without Docker was proven in `m17.2`: the renderer emits the intended rules, and the
integration test drives the real enforcer with the placeholder header and the excluded-family negatives.

**Decision:** Do not mark the milestone's command matrix as re-validated on the strength of the unit and integration
tests. The first-pass artifact stays labelled as run against a prefix catch-all. The table in `docs/github.md` is
written from the allowlist definition and the first pass, and this task's job is to confirm it against GitHub.
