# Milestone: m16 - GitHub REST Wrapper

Provide an officially supported GitHub wrapper that uses REST-only endpoints so repo identity stays visible in request
URLs and can be constrained by `m14` policies. The goal is not to replace stock `gh` wholesale; it is to provide a
practical, repo-scoped GitHub tool surface that works with the fine-grained proxy model.

## Problem

Stock `gh` is not a good fit for `m14`-style single-repo policy enforcement in the general case because many common
operations use GraphQL, where repo identity lives in the request body rather than the URL. `m14` intentionally treats a
matched URL as a trusted endpoint and does not inspect request bodies. That makes broad `gh` support a poor match for
repo-scoped URL policies.

GitHub's REST API covers a large set of repo-centric workflows with repo identity encoded in the URL path. A thin
wrapper on a REST-focused client library can use that property directly instead of trying to coerce stock `gh` into a
policy model it was not designed for.

## Goals

- Support a curated set of high-value, repo-scoped GitHub workflows using REST-only endpoints
- Keep repo identity explicit in request URLs so a single-repo allowlist is practical under `m14`
- Provide a stable, documented wrapper surface instead of asking users to memorize raw REST routes
- Make the supported subset explicit and document what remains unsupported because it depends on GraphQL or broader
  trust assumptions
- Use `m15` proxy-side credential injection where practical instead of storing GitHub tokens in the agent container

## Out of Scope

- Full parity with stock `gh`
- GraphQL-backed GitHub operations
- Header or request-body inspection beyond what `m14` already supports
- Replacing git itself for clone, fetch, checkout, push, or merge mechanics
- Solving every GitHub auth flow in this milestone

## Design

### Shape of the wrapper

The wrapper should stay thin. The likely form is a small CLI on top of GitHub REST calls that exposes a curated set of
repo-scoped commands such as repository view, issue list/create, pull-request list/view/create/merge where REST
coverage is sufficient, release view, and workflow dispatch.

The wrapper should not try to perfectly mimic `gh` UX. It should optimize for:

- explicitness
- repo scoping
- policy compatibility
- predictable mapping from command to REST endpoint family

### Client library and language

Go is now the leading implementation candidate because it would produce a standalone binary and fit the repo's existing
Go-first CLI direction. The leading Go option is `google/go-github`.

Node plus Octokit remains a viable fallback if implementation planning shows materially better REST coverage or lower
integration cost for the initial supported command set.

The selection criteria should be:

- REST endpoint coverage for the supported workflows
- ability to ship a standalone binary versus requiring a runtime
- fit with the existing Go-based `agentbox` toolchain and release process
- ease of keeping repo identity explicit in URL-based requests

### Repo scoping

Repo scope should be explicit in the command surface, either as a required `--repo owner/name` style flag or a clearly
defined current-repo default that never broadens beyond one repository without an explicit user action.

The important architectural point is that the repo identity must remain visible in the final REST path so `m14` can
constrain access via URL-based rules.

### Auth

This milestone should not invent a second credential path. It should use `m15` proxy-side credential injection where
the wrapper's REST calls can be matched safely by host, method, and path. Residual flows that require the client to
receive credential material belong in later helper work:

- `m18` for residual helper-based flows

### Distribution

If the wrapper is implemented in Go, it can ship as a standalone binary. If implementation planning chooses Node plus
Octokit instead, then the runtime footprint and image/distribution story need to be justified explicitly.

Milestone planning should decide whether the wrapper belongs in the base image, a specific agent image, or as an
optional tool installation path.

### Project boundary

This milestone may later become its own open-source project. The current rationale is that there does not appear to be
an obvious standalone-binary equivalent to `gh` that intentionally stays on REST-only endpoints for use in constrained
environments with network proxy inspection.

That project-boundary decision is deferred for now. `m16` should proceed in a way that keeps extraction feasible later:

- keep the wrapper surface narrow and well documented
- avoid coupling the command surface too tightly to Agent Sandbox internals
- prefer packaging and tests that would still make sense if the wrapper moved into its own repository later

## Tasks

To be broken down when work begins. Rough outline:

- Select the supported command subset based on real repo-scoped workflows that map cleanly to REST
- Design the wrapper CLI surface and repo-scoping model
- Choose the implementation language and client library (`go-github` is the leading candidate; Octokit remains the main
  alternative)
- Implement the wrapper on REST calls only
- Add policy examples showing single-repo access under `m14`
- Add credential-injection examples that reuse the `m15` model where practical
- Document unsupported workflows that still require stock `gh` or broader trust
- Test the wrapper against representative GitHub workflows and failure modes

## Open Questions

- Which top 10 repo-centric workflows are important enough to support in the first cut?
- Should the wrapper require explicit `--repo`, or is deriving repo from the current checkout acceptable if it remains
  single-repo scoped?
- Is Go plus `google/go-github` sufficient for the supported workflow set, or do any required workflows push the
  milestone toward Node plus Octokit?
- Should the wrapper live in the base image, selected agent images, or be user-installed?
- Should the wrapper remain inside Agent Sandbox long term, or does the standalone binary use case justify spinning it
  out after the first useful version?
- Which workflows that look repo-scoped on the surface still fan out into broader trust assumptions in practice?
- Is the wrapper's output primarily human-oriented, script-oriented, or both?

## Definition of Done

- At least one meaningful repo-scoped GitHub workflow set can be executed through the wrapper using REST-only endpoints
- The supported wrapper commands keep repo identity visible in URL paths and are compatible with `m14` policy matching
- The supported subset and unsupported GraphQL-dependent workflows are documented clearly
- Policy examples exist for constraining the wrapper to a single GitHub repository
- The auth story for the wrapper is documented and reuses `m15` proxy-side injection where practical
