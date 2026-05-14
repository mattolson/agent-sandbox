# Execution Log: m15.8 - Docs And Examples

## 2026-05-13 - Execution complete

Worked the plan as written. All six examples under `docs/policy/examples/` render cleanly through the real
`/opt/proxy-python/bin/python3 images/proxy/render-policy` with `AGENTBOX_POLICY_SOURCE_PATH`. The two
shim-enabled GitHub examples (`github-repos.yaml`, `github-git-push.yaml`) emit the renderer-owned
`credential_shim` block as expected. Test suites: 163 proxy tests OK; `go test ./...` all `ok`.

**Decision (mid-execution):** Initial troubleshooting draft asserted a `"type": "secret_warning"` standalone
log event. Verified against `images/proxy/addons/enforcer.py:382-401` and `images/proxy/addons/enforcer.py:478-483`
that warnings actually ride along inside the successful `"type": "header_injection"` event under `"warnings"`.
Corrected the doc before commit.

**Observation:** The schema doc's "Header and request-body inspection are out of scope" sentence in the
Enforcement Phases section was no longer accurate now that header injection is a first-class feature.
Rewrote it to keep the original "body scanning is not a feature" framing while acknowledging that header
injection is in scope when a rule declares it.

**Observation:** `docs/upgrades/m14-request-aware-rules.md` still references `surfaces` and `readonly: true`
on the GitHub catalog. The task plan explicitly says to leave it; documenting as a follow-up. The schema
doc still links to that page as the m14 feature tour.

**Cross-check:** Confirmed by grep that no user-facing doc under `docs/policy/`, `docs/git.md`,
`docs/troubleshooting.md`, `docs/secrets.md`, or `README.md` still authoritatively documents the rejected
`surfaces` / repo-scoped `readonly` shape after the rewrite. Remaining matches are in `docs/plan/` planning
text and the m14 upgrade doc, both out of scope per CLAUDE.md.

## 2026-05-10 - Dropped the upgrade doc entirely

User feedback: nothing in m15 has shipped, so an in-milestone change like the m15.5 catalog rewrite is not a
breaking change worth a migration guide. The `surfaces` and repo-scoped `readonly` paragraphs in
`docs/policy/schema.md` are stale planning text for an unreleased feature; removing them is a doc correction, not
a release migration.

`docs/upgrades/` should remain reserved for genuine breaking changes against released behavior. m15.8 adds no new
file under `docs/upgrades/`.

**Decision:** Do not move or rename `docs/upgrades/m14-request-aware-rules.md` in this task. It predates m15 and
appears to have been filed under `docs/upgrades/` by mistake (it is a feature tour, not a migration guide), but
cleaning that up is out of scope. Flag it as a follow-up so it does not get treated as the upgrade-doc format
reference.

## 2026-05-10 - Refocused upgrade doc on breaking change only (superseded)

Earlier revision proposed adding `docs/upgrades/m15-github-shorthand.md` as a migration guide for the m15.5
`surfaces`/`readonly` removal. Superseded by the next decision: that syntax never shipped, so there is no
migration to document.

## 2026-05-10 - Initial task plan

Created the M15.8 task plan after reviewing the M15 milestone, all m15.1 through m15.7 task plans, the existing
`docs/policy/schema.md`, the focused examples under `docs/policy/examples/`, `README.md`, `docs/git.md`,
`docs/troubleshooting.md`, the m14 upgrade doc, and the m15.7 integration test files.

**Decision:** Drive every new example from the m15.7 integration scenarios. Private read with auth, readwrite plus
askpass shim, and explicit `domains[].transform.request` map to existing tests, so the docs cannot drift from
tested behavior. The renderer should be exercised against each example as part of the implementation step.

**Decision:** Frame proxy-side credential injection as the default _in-container_ GitHub Git path, but keep "run
git from the host" as the recommended workflow at the README level. The upgrade doc should reflect that ordering
honestly instead of marketing proxy injection as a blanket default.

**Decision:** Put secret storage, permissions, scope direction, freshness, and non-goals in a new
`docs/secrets.md` rather than splicing them into `schema.md` or `git.md`. Schema.md is already 425 lines and
adding storage details would blur the boundary between policy syntax and runtime backend.

**Decision:** Treat `docs/policy/schema.md` as the canonical reference and make every other doc link back to it.
The new docs should not re-derive the secret ID grammar or transform shapes.

**Decision:** Do not document `agentbox secrets` as a CLI surface. No such command exists; documenting it would
promise surface area the milestone is not committing to. Manual provisioning instructions are enough for m15.

**Decision:** Keep an explicit non-goal section in `docs/secrets.md` that says m15 does not scan request or
response content for leaked secret values. The existing milestone language says the same thing, and not making
that boundary plain in user-facing docs is the easy way to overstate the security claim.

**Observation:** The existing `docs/policy/examples/github-repos.yaml` still uses `surfaces` and repo-scoped
`readonly`, both of which the m15.5 catalog rejects. That file must be rewritten in this task or it will block
example-render verification.

**Observation:** `docs/troubleshooting.md` already documents the missing-secret-directory case from m15.3. The
new sections should cover secret-file-level issues (missing file, unsafe permissions, resolver rejection events)
and the compatibility-shim env-not-live limitation, not the directory-level case that m15.3 covered.

**Observation:** `docs/git.md` currently frames credential-store-with-PAT as the default in-container Git
workflow. The m15 model inverts that ordering. The fallback path must remain documented but the framing should
flip so readers find proxy injection first.
