---
name: plan-project
description: Create a project plan for a new initiative. Use when starting a new project, defining goals, breaking work into milestones, and doing initial technical due diligence.
---

# Project Planning

Part of the three-tier planning system. See `/plan` for an overview.

This skill guides the creation of a high-level project plan. The output defines goals, approach, architecture, and milestones. It is intentionally broad; detailed planning happens later during milestone planning and task planning as work progresses.

## Output

The final artifact is `docs/plan/project.md`.

The project plan can be updated as work progresses. When significant changes are made, update the plan to reflect current state and **always create a decision record** in `docs/plan/decisions/`. The decision records serve as the history of how the plan evolved.

## Process

Work through these phases interactively with the user. Do not rush ahead. Each phase should be a conversation.

### Phase 1: Problem Definition

Clarify what we're building and why.

- What problem are we solving?
- Who is it for?
- What does success look like?
- What are the constraints (resources, technical, organizational)?
- What direct requests have come from customers or potential users?
- What are their stated requirements vs. underlying needs?

Capture answers in a working draft. Confirm understanding before proceeding.

### Phase 2: Solution Exploration

Explore the solution space before committing to an approach.

- What are the possible approaches?
- What are the tradeoffs of each?
- Are there existing solutions or prior art to consider?
- What technologies or patterns are candidates?

Document options considered, not just the chosen path.

### Phase 3: Technical Due Diligence

Identify risks and unknowns early.

- What are the biggest technical unknowns?
- Are there feasibility concerns that need validation?
- What dependencies exist (external services, APIs, libraries)?
- What could go wrong?

Flag items that need spikes or proof-of-concept work.

### Phase 4: Architecture Sketch

Outline how the pieces fit together. Focus on decisions that are hard to reverse, affect milestone boundaries, or require early validation.

- What are the major components?
- How do they interact?
- What are the key interfaces or boundaries?
- What data flows through the system?
- What decisions are hard to change later (data models, public APIs, core abstractions)?

Leave internal implementation details for milestone and task planning. The goal is knowing enough to draw milestone boundaries correctly and flag what needs early de-risking.

### Phase 5: Rollout Planning

For modifications to existing systems, define how to deploy safely.

- Is this a new system or a modification to an existing one?
- What is the migration path for existing users or data?
- Can changes be rolled out incrementally (feature flags, canary, percentage rollout)?
- What is the rollback plan if something goes wrong?
- Are there dependencies on external teams or systems for rollout?

Skip this phase for greenfield projects with no existing users.

### Phase 6: Milestone Breakdown

Divide the work into logical chunks.

- What are the natural phases of delivery?
- What can be delivered incrementally?
- What are the dependencies between milestones?
- What is the rough sequence?

Each milestone should have a clear goal and boundary.

## Project Plan Template

When all phases are complete, compile into `docs/plan/project.md` using this structure:

```markdown
# Project: {Name}

## Problem Statement

{What problem are we solving and why}

## User Requirements

{Direct requests and requirements from customers or potential users}

## Success Criteria

{How we'll know we succeeded}

## Constraints

{Resources, technical, organizational limitations}

## Approach

{Chosen approach and rationale}

### Alternatives Considered

{Other options explored and why they were not chosen}

### Literature Review

{Links to similar systems, architectures, or prior art reviewed during planning. Include brief notes on what was learned from each.}

## Architecture Overview

{High-level description of components and how they interact}

## Technical Risks

{Unknowns, feasibility concerns, dependencies}

## Rollout Plan

{Migration path, incremental rollout strategy, rollback plan. Omit for greenfield projects.}

## Milestones

### Milestone 1: {Name}

{Goal and scope}

### Milestone 2: {Name}

{Goal and scope}

{Continue as needed}

## Open Questions

{Anything unresolved that needs future attention}
```
