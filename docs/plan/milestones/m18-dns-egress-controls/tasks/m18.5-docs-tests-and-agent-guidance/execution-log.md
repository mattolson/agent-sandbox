# Execution Log: m18.5 - docs, tests, and agent guidance

## 2026-09-28 - Planning

No user doc mentions DNS, so no doc describes it as unrestricted; the gap is that nothing explains the new
behaviour. The README and the baked `operating-in-agent-sandbox` skill both describe two enforcement layers, and the
skill's quick check, `curl --noproxy '*' https://example.com`, now fails at name resolution while the skill says the
firewall refuses it. An agent following the skill would see `NXDOMAIN` and draw the wrong conclusion.

`m18.2` through `m18.4` handed forward the repair path after a proxy recreation, `AGENTBOX_DNS_ALLOW`, the DoH
residual, the version-skew banner, the IPv6 banner lines, the guard's 403 and event, the IP-literal exemption,
`NO_PROXY` for sidecars, the guard's residuals, sidecars as trusted egress, and the unmeasured tool inventory. All are
in the scope.

**Decision (proposed):** one new `docs/network.md` as the canonical description, two decision records, and a coverage
table in the bypass matrix. Five open questions in `task.md`. Awaiting approval.
