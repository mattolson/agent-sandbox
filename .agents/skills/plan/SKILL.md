---
name: plan
description: Entry point for the three-tier planning system. Use when starting planning work at any level - project, milestone, or task.
---

# Planning System

This is a three-tier planning system for iterative project development. Each tier produces artifacts that inform the next.

## The Three Tiers

### Tier 1: Project Planning

High-level planning done once at project start. Defines goals, approach, architecture, and milestones.

- Output: `docs/plan/project.md`
- Produces: List of milestones with identifiers (e.g., `m1-auth`, `m2-dashboard`)

### Tier 2: Milestone Planning

Done at the start of each milestone. Breaks the milestone into discrete tasks.

- Input: Project plan
- Output: `docs/plan/milestones/{milestone}/milestone.md`
- Produces: List of tasks with identifiers (e.g., `m1.1-login-form`, `m1.2-signup-flow`)

### Tier 3: Task Planning

Done at the start of each task. Plans implementation, tracks execution, captures learnings.

- Input: Milestone plan + accumulated learnings
- Output: `docs/plan/milestones/{milestone}/tasks/{task}/task.md`
- Also appends to: `docs/plan/learnings.md`

## Naming Convention

- Milestones: `m{number}-{name}` (e.g., `m1-auth`, `m2-dashboard`)
- Tasks: `m{milestone}.{task}-{name}` (e.g., `m1.1-login-form`, `m1.2-signup-flow`)

## File Structure

```
docs/plan/
├── project.md              # Tier 1 output - goals, architecture, milestones
├── learnings.md            # Accumulated learnings from all tasks
├── decisions/
│   ├── 001-switch-to-graphql.md
│   └── 002-defer-analytics.md
└── milestones/
    ├── m1-auth/
    │   ├── milestone.md    # Tier 2 output - milestone plan and task list
    │   ├── {milestone-level artifacts}
    │   └── tasks/
    │       ├── m1.1-login-form/
    │       │   ├── task.md
    │       │   └── {task artifacts}
    │       └── m1.2-signup-flow/
    │           └── task.md
    └── m2-dashboard/
        ├── milestone.md
        └── tasks/
            └── m2.1-user-profile/
                └── task.md
```

## Learnings and Decisions

Planning is imperfect. As work progresses, we discover things we didn't anticipate and make decisions that change the plan.

### Learnings

Lessons learned during execution that inform future planning. Captured in `docs/plan/learnings.md`. These may be technical or process-related.

Technical examples:
- "API rate limits are lower than documented, need to batch requests"
- "Integration tests take 5 minutes, run selectively during development"
- "The auth library doesn't support refresh tokens out of the box"

Process examples:
- "Breaking tasks into half-day chunks improved estimation accuracy"
- "Spiking unfamiliar APIs before planning saved rework"
- "Pairing on complex integrations caught issues earlier"

Learnings are reviewed at the start of each planning session.

### Decisions

Significant changes to the plan, recorded as individual documents in `docs/plan/decisions/`.

When a decision changes the plan:
1. Update the affected plan document (project.md, milestone.md) to reflect current state
2. Create a decision record documenting the change and rationale

Decision document format:

```markdown
# {Number}: {Title}

## Status

{Proposed | Accepted | Superseded by XXX}

## Context

{What situation prompted this decision?}

## Decision

{What are we changing?}

## Rationale

{Why this approach over alternatives?}

## Consequences

{What changes as a result? What are the tradeoffs?}
```

Decisions are numbered sequentially: `001-switch-to-graphql.md`, `002-defer-analytics.md`.

## Workflow

This is a conversational process. Describe your intent and I will:
1. Identify which planning tier applies
2. Look up relevant identifiers from existing plans
3. Guide you through the appropriate planning process

Examples:
- "Let's plan a new project" → Tier 1 project planning
- "Let's start the auth milestone" → I look up the milestone in project.md, begin tier 2 planning
- "Ready to work on login" → I find the task in the milestone plan, begin tier 3 planning

Learnings from each completed task feed into future task planning. When discoveries require plan changes, we update the plan and record a decision.

## Getting Started

Describe what you want to work on:
- Starting a new initiative? We'll do project planning.
- Ready to begin a milestone? Tell me which one.
- Ready to implement a task? Tell me what you're building.
