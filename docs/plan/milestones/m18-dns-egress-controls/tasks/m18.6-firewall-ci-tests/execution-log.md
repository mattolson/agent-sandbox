# Execution Log: m18.6 - firewall CI tests

## 2026-09-28 - Planning

Opened as a follow-up after the maintainer asked whether a test could replace keeping IPv6 on in the dev sandbox. The
dev sandbox exercises the IPv6-present firewall path only when rebuilt and restarted, on Colima arm64 only; a CI run
would exercise both IPv6 paths on every relevant PR, on amd64, which no host run has covered.

The base image's entrypoint runs `init-firewall.sh`, installs the proxy CA only if one is mounted, and otherwise needs
nothing but a `proxy` service that serves the sinkhole. The proxy's entrypoint generates its CA and renders its baked
policy when no policy files are mounted. `run-audit.bash` already accepts `--container` and `--skip-vm`, and needs
`agentbox` only when no container is given.

**Decision (proposed):** a hand-written two-service stack in CI, IPv6 on and off, checked through the startup log and
the audit runner with CI-specific expectation files, and seen to fail on a broken firewall before being trusted. Then
IPv6 off in the dev sandbox. Five open questions in `task.md`. Awaiting approval.
