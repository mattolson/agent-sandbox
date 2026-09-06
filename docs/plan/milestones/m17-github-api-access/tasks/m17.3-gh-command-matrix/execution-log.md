# Execution Log: m17.3 - gh command matrix

## 2026-09-06 - Planned; blocked on a host build

The re-run needs rebuilt base and proxy images and a proxy reload, none of which can happen from inside the sandbox.
Everything that could be proven without Docker was proven in `m17.2`: the renderer emits the intended rules, and the
integration test drives the real enforcer with the placeholder header and the excluded-family negatives.

**Decision:** Do not mark the milestone's command matrix as re-validated on the strength of the unit and integration
tests. The first-pass artifact stays labelled as run against a prefix catch-all. The table in `docs/github.md` is
written from the allowlist definition and the first pass, and this task's job is to confirm it against GitHub.
