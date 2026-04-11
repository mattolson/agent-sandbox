# Milestone: m15 - GitHub REST Wrapper

Provide an officially supported GitHub wrapper built on Oktokit that uses REST-only endpoints so repo identity stays
visible in request URLs and can be constrained by `m14` policies. The goal is not to replace stock `gh` wholesale; it
is to provide a practical, repo-scoped GitHub tool surface that works with the fine-grained proxy model.

## Problem

Stock `gh` is not a good fit for `m14`-style single-repo policy enforcement in the general case because many common
operations use GraphQL, where repo identity lives in the request body rather than the URL. `m14` intentionally treats a
matched URL as a trusted endpoint and does not inspect request bodies. That makes broad `gh` support a poor match for
repo-scoped URL policies.

GitHub's REST API covers a large set of repo-centric workflows with repo identity encoded in the URL path. A wrapper on
Oktokit can use that property directly instead of trying to coerce stock `gh` into a policy model it was not designed
for.

## Goals

- Support a curated set of high-value, repo-scoped GitHub workflows using REST-only endpoints
- Keep repo identity explicit in request URLs so a single-repo allowlist is practical under `m14`
- Provide a stable, documented wrapper surface instead of asking users to memorize raw REST routes
- Make the supported subset explicit and document what remains unsupported because it depends on GraphQL or broader
  trust assumptions
- Start with existing/manual auth flows and leave tighter integration with later credential milestones as follow-up work

## Out of Scope

- Full parity with stock `gh`
- GraphQL-backed GitHub operations
- Header or request-body inspection beyond what `m14` already supports
- Replacing git itself for clone, fetch, checkout, push, or merge mechanics
- Solving every GitHub auth flow in this milestone

## Design

### Shape of the wrapper

The wrapper should stay thin. The likely form is a small CLI on top of Oktokit REST calls that exposes a curated set of
repo-scoped commands such as repository view, issue list/create, pull-request list/view/create/merge where REST
coverage is sufficient, release view, and workflow dispatch.

The wrapper should not try to perfectly mimic `gh` UX. It should optimize for:

- explicitness
- repo scoping
- policy compatibility
- predictable mapping from command to REST endpoint family

### Repo scoping

Repo scope should be explicit in the command surface, either as a required `--repo owner/name` style flag or a clearly
defined current-repo default that never broadens beyond one repository without an explicit user action.

The important architectural point is that the repo identity must remain visible in the final REST path so `m14` can
constrain access via URL-based rules.

### Auth

This milestone does not need to invent a new credential path. It can start by working with the existing/manual token
flows that are already available in the environment. Later milestones can improve the auth story:

- `m16` for proxy-side secret injection
- `m18` for residual helper-based flows

### Distribution

Because Oktokit is a JavaScript client, the wrapper will likely be Node-based unless implementation planning turns up a
stronger alternative. Milestone planning should decide whether it belongs in the base image, a specific agent image, or
as an optional tool installation path.

## Tasks

To be broken down when work begins. Rough outline:

- Select the supported command subset based on real repo-scoped workflows that map cleanly to REST
- Design the wrapper CLI surface and repo-scoping model
- Implement the wrapper on Oktokit REST calls only
- Add policy examples showing single-repo access under `m14`
- Document unsupported workflows that still require stock `gh` or broader trust
- Test the wrapper against representative GitHub workflows and failure modes

## Open Questions

- Which top 10 repo-centric workflows are important enough to support in the first cut?
- Should the wrapper require explicit `--repo`, or is deriving repo from the current checkout acceptable if it remains
  single-repo scoped?
- Should the wrapper live in the base image, selected agent images, or be user-installed?
- Which workflows that look repo-scoped on the surface still fan out into broader trust assumptions in practice?
- Is the wrapper's output primarily human-oriented, script-oriented, or both?

## Definition of Done

- At least one meaningful repo-scoped GitHub workflow set can be executed through the wrapper using REST-only endpoints
- The supported wrapper commands keep repo identity visible in URL paths and are compatible with `m14` policy matching
- The supported subset and unsupported GraphQL-dependent workflows are documented clearly
- Policy examples exist for constraining the wrapper to a single GitHub repository
- The auth story for the wrapper is documented, even if richer secret handling is deferred to later milestones
