# Security Policy

## Reporting A Vulnerability

Use a private report for security issues.

Preferred path:

- [Open a GitHub Security Advisory](https://github.com/mattolson/agent-sandbox/security/advisories/new) for this repository

If you cannot use GitHub Security Advisories:

- Open a public issue with minimal detail and clearly note that you need private follow-up

Do not publish full reproduction details for:

- Sandbox escapes
- Proxy or firewall bypasses
- Credential exposure
- Privilege escalation
- Policy enforcement gaps that materially weaken the security model

## What To Include

Include as much of the following as you can:

- A clear description of the issue
- Impact and attack preconditions
- Reproduction steps
- A proof of concept, if you have one
- Affected environment details
- Suggested mitigations, if known

## Scope

This project is a local sandbox, not a hard isolation boundary. Even so, vulnerabilities that weaken the documented security model are in scope.

Examples of in-scope issues:

- Escaping the intended filesystem boundary
- Reaching outbound network destinations that should be blocked
- Bypassing the proxy or firewall enforcement model
- Gaining privileges beyond the intended container setup
- Exposing host or repository credentials unexpectedly

Examples of lower-signal reports:

- Behavior that matches a documented limitation
- Missing hardening for a platform that the project does not claim to support
- Purely theoretical attacks without a plausible path in the documented setup

## Coordination

- Please avoid public disclosure until maintainers have had a reasonable chance to assess and address the issue.
- Report against the latest `main` branch or latest released version when possible.
- If a report is borderline between a public bug and a security issue, treat it as a security issue first.
