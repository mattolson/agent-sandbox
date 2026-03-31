# Contributing

We accept documentation improvements, tests, bug fixes, and roadmap-aligned feature work.

This project is security-sensitive. Process matters because design, roadmap alignment, and security boundaries matter.

## Before You Start

- Read the [README](./README.md), [roadmap](./docs/roadmap.md), and [project plan](./docs/plan/project.md).
- Run `./build-dev-image.sh` to build `Dockerfile.dev` for the active agent from
  `.agent-sandbox/active-target.env`.
- Search existing issues and pull requests before opening a new one.
- Keep changes agent-agnostic when possible.
- Do not start substantive feature implementation before maintainer review.

## Ways To Contribute

### Small changes

You can open a pull request directly for:

- Typo fixes
- Documentation clarifications
- Test additions or improvements
- Small bug fixes that do not change architecture, security boundaries, or public behavior in a broad way

Keep these PRs focused. If a review reveals broader design impact, maintainers may ask you to open or link an issue first.

### Bugs

Use the GitHub bug report form for reproducible, non-security bugs.

Include:

- What happened
- How to reproduce it
- What you expected
- Relevant environment details
- Logs, screenshots, or policy snippets when useful

Small bug fixes can still go straight to a PR, but an issue is preferred when the problem is ambiguous, cross-cutting, or likely to need discussion.

### Features

Start substantive feature work with a feature request issue.

Examples:

- New commands or workflows
- New runtime modes
- New policy model or enforcement behavior
- New authentication flows
- New agent support
- Cross-cutting or security-sensitive behavior changes

After maintainer review, accepted feature issues may move through these stages:

- `stage:proposal` - initial idea under discussion
- `stage:needs-plan` - direction looks good and a planning doc is requested
- `stage:planned` - planning doc is accepted and implementation can proceed

Do not open a substantive implementation PR before the feature issue has maintainer buy-in.

## Planning Docs

Maintainers may ask for a planning artifact before code review begins.

Use:

- `docs/plan/issues/` for a shorter proposal document when the work is relatively contained
- `docs/plan/milestones/` for milestone-scale planning when the work changes roadmap scope

If you are using the repo's agent workflow, the `plan` skill is the recommended way to produce planning artifacts. The required artifact is the document, not the tool.

Planning up front helps avoid spending time on a PR that does not fit the roadmap, mission, or security posture of the project.

## New Agent Support

New agent support should start with a feature request issue.

If maintainers want to pursue it, they may ask for a planning doc and then an implementation PR.

If you are using Claude or Codex in this repo, the recommended workflow is the [`add-agent` skill](./.agents/skills/add-agent/SKILL.md). You do not have to use that skill, but your contribution should still match the same quality bar and output shape.

## Security Issues

Do not use the public bug form for sandbox escapes, proxy or firewall bypasses, credential exposure, privilege escalation, or similar security issues.

Use the process in [SECURITY.md](./SECURITY.md).

## Pull Requests

Keep pull requests small and reviewable.

Every PR should:

- Explain the change clearly
- Link the relevant issue when one exists
- Link the planning doc when one was required
- Include tests when the change affects behavior
- Update documentation when the behavior or workflow changes

For changes in security-sensitive areas, explain the security impact and tradeoffs in the PR description.

## Issue Labels

Issue labels are intentionally small and orthogonal.

Type labels:

- `type:bug`
- `type:feature`

Feature stage labels:

- `stage:proposal`
- `stage:needs-plan`
- `stage:planned`

General status labels:

- `status:needs-info`
- `status:blocked`

Contribution visibility labels:

- `good first issue`
- `help wanted`

Rules:

- Every issue should have one `type:` label.
- Only feature issues should use `stage:` labels.
- Feature issues should have at most one `stage:` label at a time.
- Issues are closed when work is merged or explicitly declined. There is no separate `merged` label.

## Validation

Run the checks that match your change before asking for review.

Examples:

- `cli/run-tests.bash` for CLI changes
- `./images/build.sh` for image changes
- Focused manual verification for template, proxy, and documentation changes

If you could not run a relevant check, say so in the PR.
