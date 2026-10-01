# Execution Log: m18.6 - firewall CI tests

## 2026-09-30 - Test, expectation files, and workflow written

Approved as recommended. Docker is not reachable from the sandbox, so the logic lives in a driver,
`images/base/tests/firewall-e2e.bash`, that the workflow calls and that also runs on the maintainer's Mac. That turns
"seen to fail on a broken firewall" into a local run rather than a series of CI round trips.

**Decision:** The test stack mounts a policy that allows `proxy` and `localhost`, so the audit's D3 and D4 run and the
address guard is exercised inside the real proxy image, which the proxy suite, running outside a container, does not
do. D2 stays recorded rather than compared, because it needs `dns.google` reachable; H1 and H2 need the Colima VM.

**Issue:** Found while reading `run-audit.bash`: `die()` already exited 2, so the exit 2 that 61c8a57 gave an
incomplete audit was ambiguous. Fixed on the #204 branch (192a439): an incomplete audit now exits 3. This branch was
rebased onto it before its first push.

**Decision:** The spike step was folded into the workflow. It prints the engine and Compose versions, and the driver
declares an IPv6 subnet on engines before 27, which do not assign one. The first CI run is the spike.

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
