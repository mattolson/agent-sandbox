# 002: Block SSH, Require HTTPS for Git

## Status

Accepted

## Context

The original firewall rules allowed outbound SSH (port 22) to any destination:

```bash
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
```

This was intended to support `git clone git@github.com:...` and similar SSH-based git operations.

With the shift to proxy-based enforcement (decision 001), HTTP/HTTPS traffic routes through the proxy where it can be logged and filtered. SSH traffic bypasses the proxy entirely.

## Decision

Block all outbound SSH. Git operations must use HTTPS.

Configure git in the container image to automatically rewrite SSH URLs:

```bash
git config --global url."https://github.com/".insteadOf git@github.com:
git config --global url."https://github.com/".insteadOf ssh://git@github.com/
```

## Rationale

**Security concerns with SSH:**

1. SSH to arbitrary hosts is a data exfiltration channel
2. SSH tunneling (-D, -L, -R flags) can bypass all other restrictions
3. Cannot inspect or log SSH traffic without MITM (complex key management)
4. Allowlisting SSH endpoints by IP is fragile (same issues as HTTP)

**HTTPS git is viable:**

- All major git hosts support HTTPS (GitHub, GitLab, Bitbucket)
- Credential helpers (`git credential-cache`, `gh auth`) handle authentication
- Performance is comparable
- Most CI/CD systems use HTTPS anyway

**Why not allowlist GitHub SSH IPs specifically?**

- GitHub publishes SSH IPs in their meta API, so technically possible
- But SSH tunneling would still work to those IPs
- Adds complexity for marginal benefit
- HTTPS-only is simpler and sufficient

## Consequences

**Positive:**
- Closes a significant security gap
- All git traffic goes through proxy (logged, filterable)
- Simpler firewall rules

**Negative:**
- Users with SSH-based git workflows need to adjust
- Need to document credential setup (one-time)
- Some muscle memory retraining for `git@` URLs

**Migration:**
- Add git URL rewrite config to base image
- Document credential helper setup in README
- Test clone/push/pull through proxy
