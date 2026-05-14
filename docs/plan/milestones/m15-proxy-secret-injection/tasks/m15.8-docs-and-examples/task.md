# Task: m15.8 - Docs And Examples

## Summary

Document the m15 credential model end-to-end: explicit `domains[].transform.request`, secret IDs and transforms,
GitHub service shorthand with `git`/`api` and `access`/`auth`, the optional `client_shim: kind: git-askpass`, secret
storage layout, freshness and reload semantics, and the explicit non-goals. Refresh `README.md`, `docs/policy/`,
`docs/git.md`, and `docs/troubleshooting.md`; add a focused secrets reference and an `m15` feature-tour upgrade page.

## Scope

- Rewrite the GitHub services section of `docs/policy/schema.md`: drop the unshipped `surfaces` and repo-scoped
  `readonly` syntax, document the new `git.access`/`git.auth` and `api.access` shape, and link to the m15.5
  rejection rules for legacy fields
- Document the explicit `domains[].transform.request` shape in `docs/policy/schema.md`: secret ID grammar
  (`[A-Za-z0-9._-]+`), `basic`/`bearer` transforms, `on_existing_header: fail | replace`, the renderer-owned
  rejection of authored top-level `credential_shim`, and the reserved-but-unsupported `transform.response`
- Refresh `docs/policy/examples/github-repos.yaml` to use the m15.5 syntax and add focused examples for the three
  canonical m15 flows: private read with auth, readwrite with `client_shim: git-askpass`, and explicit `domains`
  request-header injection
- Update `README.md` so the GitHub policy snippet uses the m15.5 syntax and a new short subsection points users to
  the proxy-side credential injection flow as the recommended way to push to private GitHub repos from inside the
  container
- Update `docs/git.md` to describe proxy-side credential injection as the default GitHub Git path and keep the
  `git credential-store` fallback labeled as a trade-off (plaintext on disk inside the container)
- Add `docs/secrets.md` covering the host secret directory layout (`~/.config/agent-sandbox/secrets`, `0700`
  directory, `0600` files), secret ID rules, manual provisioning steps, the global-scope-only first pass with the
  resolver context room for project/target scope later, freshness/reload semantics, the future Keychain direction,
  and the explicit non-goal that m15 does not scan request or response content for leaked secrets
- No new `docs/upgrades/` entry. Nothing in m15 has shipped, so there is no released syntax for users to migrate
  from. Stale planning text in `docs/policy/schema.md` (the repo-scoped `surfaces` and `readonly` paragraphs) is a
  schema-doc rewrite, not a migration guide
- Update `docs/troubleshooting.md` with sections for missing or unreadable secret files, unsafe permissions,
  resolver-rejection events, and the documented limitation that compatibility-shim env exports are not visible to
  already-running agent processes
- Verify every committed example renders cleanly through `/usr/local/lib/agent-sandbox/proxy/render-policy` (or
  `images/proxy/render-policy` via the proxy Python interpreter) without modification
- Exclude implementation changes, exclude new CLI commands such as `agentbox secrets`, exclude project/target
  scope work, exclude any rename of `git.access: read` semantics in renderer error messages, and exclude any
  promise of generic credential scanning

## Acceptance Criteria

- [x] `docs/policy/schema.md` documents the m15.5 GitHub shape (`git`/`api` with `access` plus optional `auth`),
      the m15.1 `transform.request` shape with secret IDs and transforms, and the m15.6 `client_shim` opt-in
- [x] `docs/policy/schema.md` removes documentation of repo-scoped `surfaces` and repo-scoped `readonly` as
      supported authoring surfaces and lists them as rejected fields
- [x] `docs/policy/schema.md` documents that authored top-level `credential_shim` is rejected and that the
      rendered output may include a renderer-owned `credential_shim` block for shimmed services
- [x] `docs/policy/schema.md` documents `transform.response` as reserved and rejected when non-empty
- [x] `docs/policy/examples/github-repos.yaml` uses the m15.5 syntax and matches a scenario covered by renderer or
      integration tests
- [x] `docs/policy/examples/github-private-git.yaml`, `docs/policy/examples/github-git-push.yaml`, and
      `docs/policy/examples/request-transform.yaml` each render cleanly and demonstrate one canonical m15 flow
- [x] `README.md` shows the new GitHub repo-scoped snippet and links to a brief subsection that points at the
      proxy-side credential injection flow plus the new `docs/secrets.md` reference
- [x] `docs/git.md` describes proxy-side injection as the default GitHub Git path; the plaintext credential-store
      path remains documented as a trade-off
- [x] `docs/secrets.md` covers the host secret directory layout, permission expectations, secret ID rules, manual
      provisioning, scope direction (global today; project/target later), freshness/reload, the Keychain direction,
      and the explicit non-goal of request/response content scanning
- [x] No new file under `docs/upgrades/`. The `surfaces` and repo-scoped `readonly` removal is a schema-doc
      correction, not a release migration, because that syntax never shipped
- [x] `docs/troubleshooting.md` adds at least sections for missing/unreadable secret files, unsafe permissions,
      and compatibility-shim env exports not being live in existing shells
- [x] Every committed example under `docs/policy/examples/` renders without error through `render-policy`
- [x] Docs explain the security boundary without claiming exfiltration detection, body scanning, or credential
      leak prevention
- [x] `/opt/proxy-python/bin/python3 -m unittest discover -s images/proxy/tests -p 'test_*.py'`
- [x] `go test ./...`

## Applicable Learnings

- Documentation artifacts (schema docs, examples) belong in `docs/`, not in task execution directories.
- Keep CLI stderr concise and point users at a dedicated upgrade guide rather than explaining the full layout change
  inline.
- Agent-visible credential shim metadata is renderer- and catalog-owned, not arbitrary author-facing environment
  surfaces; docs should mirror that boundary so future readers do not look for a generic env-var injection knob.
- Stable internal identifiers should not collide with rejected author-facing fields; the docs should be just as
  explicit about which authoring keys are rejected so users do not adopt syntax that the renderer will fail.
- `m15.7` is the source of truth for what the catalog renders end-to-end. New examples should map to the scenarios
  pinned by `test_github_git_injection.py` and `test_credential_shim_replace.py` so the docs cannot silently drift.
- The renderer never resolves secret values today, but the docs should still describe the freshness contract
  defined by m15.2's resolver so future backend swaps stay coherent.
- Already-running agent processes do not see updated credential-shim env exports; docs must keep that limitation
  explicit instead of implying a hot-update path.

## Plan

### Files Involved

- `docs/policy/schema.md` - rewrite GitHub services subsection, add `transform.request` reference, add
  `credential_shim` and `transform.response` reservation paragraphs, update the rejected-fields list
- `docs/policy/examples/github-repos.yaml` - rewrite into the m15.5 shape, mirroring the m15.7 readwrite scenario
- `docs/policy/examples/github-private-git.yaml` - new; private read with auth using `git.access: read` plus
  `git.auth.secret`
- `docs/policy/examples/github-git-push.yaml` - new; readwrite Git with `client_shim: kind: git-askpass`, pointing
  the reader at the askpass behavior described in `docs/secrets.md`
- `docs/policy/examples/request-transform.yaml` - new; explicit `domains[].transform.request.headers` with a
  `bearer` transform, demonstrating the authoring shape independent of the GitHub catalog
- `README.md` - update the GitHub policy snippet, add a short "GitHub Git from inside the container" subsection
  pointing at `docs/git.md` and `docs/secrets.md`, and refresh the credentials guidance under "Security"
- `docs/git.md` - replace the credential-store-as-default framing with a proxy-injection-as-default framing; keep
  the plaintext fallback documented and labeled as a trade-off
- `docs/secrets.md` - new; storage location, permissions, secret ID grammar, manual provisioning, scope direction,
  freshness/reload contract, Keychain direction, non-goals
- (no `docs/upgrades/` change) - m15 has not shipped, so removing the unreleased `surfaces` and repo-scoped
  `readonly` paragraphs from `docs/policy/schema.md` is a doc correction, not a migration
- `docs/troubleshooting.md` - add sections for missing/unreadable secret files, unsafe permissions, resolver
  rejection events, and shim-env-not-live-in-running-shells
- (Optional) `docs/policy/examples/*` - any example file whose syntax overlaps with the new examples should also be
  cross-checked once

### Approach

Treat `docs/policy/schema.md` as the canonical reference and make every other doc link back to it. The schema doc
should be the single place that defines the secret ID grammar, the supported transform types, the
`on_existing_header` values, the rejected legacy fields, and the renderer-owned nature of `credential_shim`. Every
other doc (`README.md`, `docs/git.md`, `docs/secrets.md`, the upgrade page) should reference the schema doc rather
than re-deriving the grammar.

Drive the new examples from the m15.7 integration scenarios so docs cannot drift from tested behavior. The three
canonical example flows are:

1. **Private read** - `git.access: read` plus `git.auth.secret: <id>`. Renders with `on_existing_header: fail`,
   matches `test_private_read_with_auth_injects_authorization_on_upload_pack_rules`.
2. **Readwrite with askpass shim** - `git.access: readwrite`, `git.auth.secret`, and
   `git.auth.client_shim.kind: git-askpass`. Renders with `on_existing_header: replace` and a non-empty
   `credential_shim` block. Matches `test_client_shim_replaces_fake_authorization_with_real_secret`.
3. **Explicit `domains[].transform.request`** - host-scoped injection of an `Authorization: Bearer <secret>` header,
   no catalog involved. Mirrors the test pattern in
   `test_proxy_enforcement.py::test_header_injection_reaches_upstream_for_matched_rule`.

The `github-repos.yaml` example should keep the same name but switch to the m15.5 shape, with a comment block
explaining that the file demonstrates the readwrite-with-shim flow and pointing readers at the focused private-read
file when they only need clone/fetch. The current example's `surfaces` and `readonly` keys should be removed since
the renderer rejects them as of m15.5.

Verify every example by running it through the real renderer before the docs commit lands. The simplest way: invoke
`AGENTBOX_POLICY_SOURCE_PATH=<example> /opt/proxy-python/bin/python3 images/proxy/render-policy` and confirm the
exit code is zero and the rendered output includes the expected `host` records and (where applicable)
`credential_shim` block.

`docs/secrets.md` should keep the doc small and high-signal. The structure should be:

1. Where secrets live on the host
2. Permission expectations and why they matter
3. Secret ID rules
4. How to add a secret (plain `printf '%s' "$value" > path`)
5. How to reference a secret from policy (link to schema.md)
6. Freshness and reload contract: the proxy reads each secret on demand at request time via the file backend, so a
   replaced secret file is visible to the next matching request without a `SIGHUP`
7. Scope direction: m15 ships global storage only; the resolver carries enough context to add project/target
   overlays later without changing policy syntax
8. Future Keychain direction: same logical secret IDs, different backend
9. Non-goals: m15 does not scan request bodies, response bodies, or arbitrary URLs for leaked secret values

For `docs/git.md`, replace the existing "Credential setup" section's framing without deleting the fallback. The
preferred path becomes: define a policy entry with `git.auth.secret`, add the secret to the host secret directory,
restart the container or open a new shell so the compatibility-shim env exports are visible. The fallback path
remains: `git credential-store` with a fine-grained PAT, with the same plaintext-on-disk warning.

For the upgrade doc, mirror the format of `m14-request-aware-rules.md`: a top section listing what is new, a
backward-compatibility statement, then short example snippets for each surface. Keep tone matter-of-fact, no
marketing.

For `README.md`, do not move the existing Security section; just update the GitHub snippet and add one short
"GitHub Git from inside the container" subsection above or beside the existing "Git credentials" subsection that
points at `docs/git.md` and `docs/secrets.md` and the focused example.

For `docs/troubleshooting.md`, three short sections are enough:

- "Proxy fails to inject a header" - the resolver could not read the secret file; check existence and permissions.
- "Secret file rejected with unsafe-permissions error" - the resolver's `lstat`/`O_NOFOLLOW` checks failed; tighten
  to `0600` or remove a symlink.
- "Compatibility-shim env vars not visible inside the container" - the agent process started before the policy
  reload; open a new shell or restart the container.

### Implementation Steps

- [x] Read the m15.7 integration test files and pin the example YAML shapes to those scenarios
- [x] Rewrite `docs/policy/schema.md` GitHub section, add the `transform.request` section, add the
      `credential_shim` rejection paragraph, and update the rejected-fields list
- [x] Rewrite `docs/policy/examples/github-repos.yaml` to the m15.5 shape
- [x] Add `docs/policy/examples/github-private-git.yaml`
- [x] Add `docs/policy/examples/github-git-push.yaml`
- [x] Add `docs/policy/examples/request-transform.yaml`
- [x] Verify each example renders cleanly through the real `render-policy`
- [x] Update `README.md`: snippet plus short subsection plus security-section pointer
- [x] Update `docs/git.md` to frame proxy injection as the default GitHub Git path
- [x] Add `docs/secrets.md`
- [x] Update `docs/troubleshooting.md` with the three new sections
- [x] Run `/opt/proxy-python/bin/python3 -m unittest discover -s images/proxy/tests -p 'test_*.py'`
- [x] Run `go test ./...`

### Open Questions

- Should the new examples live under `docs/policy/examples/` (current) or under a new `docs/policy/examples/m15/`
  subdirectory to make the m15 surfaces easy to find? Recommended default: keep one flat directory and name files
  descriptively. A subfolder would imply a versioning convention the project does not currently follow.
- `docs/upgrades/m14-request-aware-rules.md` is a feature tour rather than a migration guide and sits under
  `docs/upgrades/` by mistake. Should m15.8 move or rename it? Recommended default: no — it predates this
  milestone and is out of scope. Flag it as a follow-up so it does not get treated as the upgrade-doc format
  reference.
- Should `agentbox secrets` get a stub doc page even though no command exists yet? Recommended default: no. Adding
  a doc for an unshipped CLI promises surface area the milestone is not committing to.
- Should the m15 upgrade doc include a `git.access: read with auth -> private read` terminology callout?
  Recommended default: yes, in one short paragraph. The renderer error messages do not name the case, but readers
  will look for that exact phrase after the m15.7 plan and follow-ups mentioned it.

## Outcome

### Acceptance Verification

- [x] Each acceptance-criteria checkbox is satisfied by the corresponding doc surface:
  - Schema rewrite: `docs/policy/schema.md` GitHub section (`### GitHub service`), `## Request transforms`
    section (including secret ID grammar, `bearer`/`basic`, `on_existing_header`, reserved
    `transform.response`), and `### Renderer-owned fields` paragraph for the `credential_shim` rejection.
  - Examples: `docs/policy/examples/github-repos.yaml` (readwrite plus shim, `api: read`),
    `github-private-git.yaml` (private read), `github-git-push.yaml` (readwrite with askpass shim, mirrors
    `test_client_shim_replaces_fake_authorization_with_real_secret`), `request-transform.yaml` (host-scoped
    `transform.request` with `bearer`, mirrors `test_header_injection_reaches_upstream_for_matched_rule`).
  - README: GitHub policy snippet uses the m15.5 shape; "GitHub Git from inside the container" subsection
    appears after the policy reference; "Git credentials" under Security adds proxy-injection as a defense
    bullet; Customization list adds `docs/secrets.md`.
  - `docs/git.md`: "Credential setup (preferred): proxy-side injection" precedes "Credential setup
    (fallback): credential-store with a PAT".
  - `docs/secrets.md`: storage layout table, permission expectations, secret ID grammar, `printf` provisioning
    steps, scope direction with `SecretResolutionContext` reference, freshness contract, Keychain direction,
    explicit non-goals.
  - `docs/troubleshooting.md`: three new sections — "Proxy fails to inject a header", "Secret file has unsafe
    permissions", "Credential-shim env vars not visible inside the container".
- [x] Example-render verification: all six committed examples under `docs/policy/examples/` render with
      exit code 0 under `AGENTBOX_POLICY_SOURCE_PATH=<example> /opt/proxy-python/bin/python3 images/proxy/render-policy`.
      `github-repos.yaml` and `github-git-push.yaml` emit the renderer-owned `credential_shim` block with the
      `git-askpass` hint as expected.
- [x] Test suites: `163 tests in 13.486s OK` for proxy Python tests; `go test ./...` all `ok`.

### Learnings

- Pinning user-facing example YAML to existing integration tests (`test_github_git_injection.py`,
  `test_credential_shim_replace.py`, `test_proxy_enforcement.py::test_header_injection_reaches_upstream_for_matched_rule`)
  is a stronger guarantee than re-deriving "canonical" shapes from the schema. Each example then has a tested
  scenario that breaks loudly if the renderer ever changes, instead of drifting silently.
- Structured log shapes that show up in troubleshooting docs need to be verified against the actual enforcer
  emit sites before publishing. The initial draft asserted a standalone `"type": "secret_warning"` event that
  does not exist; the real shape rides `unsafe_permissions` warnings inside `"type": "header_injection"`. Doc
  fidelity here matters because users will grep proxy logs for the literal strings the doc shows.
- Keeping the schema doc as the single source of truth for the secret ID grammar, transform types, and
  rejected fields keeps the other docs short. `docs/secrets.md`, `docs/git.md`, and the troubleshooting
  sections all link back to schema.md rather than re-stating the grammar.
- The renderer's `credential_shim` rejection is for *authored* top-level blocks; the rendered output still
  emits a `credential_shim` block when a service entry opts in. Docs need both halves: "authored = rejected"
  and "rendered = expected for shimmed services".

### Follow-up Items

- A future task should add an `agentbox secrets` CLI for managing the host secret directory; m15.8 documents the
  manual path only.
- A future task should add project/target scope overlays once a concrete need exists; m15.8 documents the
  direction without committing to a layout.
- A future task should add a macOS Keychain resolver backend; m15.8 documents the constraint that logical secret
  IDs stay backend-neutral so the policy shape does not change.
- `docs/upgrades/m14-request-aware-rules.md` is a feature tour misfiled under `docs/upgrades/`. A future cleanup
  task should move or rename it; m15.8 leaves it in place. The schema doc still links to it as the m14 tour.
