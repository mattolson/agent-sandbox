---
name: plan-milestone
description: Break a milestone into discrete tasks. Use when starting work on a milestone that has been defined in the project plan.
---

# Milestone Planning

Part of the three-tier planning system. See `/plan` for an overview.

This skill breaks a milestone into discrete, implementable tasks. The output is a milestone plan that sequences work and identifies dependencies.

## Inputs

Before starting, read:
- `docs/plan/project.md` - to understand the milestone's context and goals
- `docs/plan/learnings.md` - to incorporate lessons from previous work
- Any relevant decision documents in `docs/plan/decisions/`

## Output

The final artifact is `docs/plan/milestones/{milestone}/milestone.md`.

The milestone plan can be updated as work progresses. When task scope changes significantly, update the task definition but also record the change in a **Changes** section. This preserves history for milestone retrospectives while keeping the plan current.

## Process

Work through these phases interactively. Each phase should be a conversation.

### Phase 1: Context Review

Review the milestone's definition from the project plan.

- What is this milestone's goal?
- What are its boundaries (what's in scope, what's not)?
- What dependencies does it have on prior milestones?
- What does completion look like?

Confirm understanding before proceeding.

### Phase 2: Learnings Review

Review accumulated learnings that may apply to this milestone.

- What lessons from previous work are relevant here?
- Are there process improvements to apply?
- Are there technical pitfalls to avoid?

Note applicable learnings in the milestone plan.

### Phase 3: Task Identification

Identify the discrete pieces of work.

- What are the logical units of work?
- Is each task appropriately scoped for a single PR?
- Are tasks independently testable or verifiable?
- What are the natural boundaries between tasks?

A task should map to a well-crafted PR: a piece of functionality or a fix, along with relevant tests, sized appropriately for human peer review. Not so large that review becomes burdensome, not so small that it lacks meaningful context.

### Phase 4: Dependency Mapping

Understand how tasks relate to each other.

- Which tasks block other tasks?
- Which tasks can be done in parallel?
- Are there external dependencies (APIs, other teams, etc.)?
- What is the critical path?

### Phase 5: Risk Identification

Flag uncertainties specific to this milestone.

- Which tasks have technical unknowns?
- Where might scope be unclear?
- What could cause rework?
- Are there tasks that should be spiked first?

### Phase 6: Sequencing

Order the tasks for execution.

- What is the recommended order?
- Where are there decision points that might change the sequence?
- Which tasks should be done early to reduce risk?

## Milestone Plan Template

When all phases are complete, compile into `docs/plan/milestones/{milestone}/milestone.md`:

```markdown
# Milestone: {identifier} - {name}

## Goal

{What this milestone achieves}

## Scope

{What's included and explicitly excluded}

## Applicable Learnings

{Lessons from previous work that apply here}

## Tasks

### {m1.1-task-name}

**Summary:** {One-sentence description of what this task delivers}

**Scope:**
- {What's included}
- {What's explicitly excluded or deferred}

**Acceptance Criteria:**
- {Condition that must be true when complete}
- {Another condition}

**Dependencies:** {What must be done first}

**Risks:** {Uncertainties or concerns}

### {m1.2-task-name}

**Summary:** {One-sentence description of what this task delivers}

**Scope:**
- {What's included}
- {What's explicitly excluded or deferred}

**Acceptance Criteria:**
- {Condition that must be true when complete}
- {Another condition}

**Dependencies:** {What must be done first}

**Risks:** {Uncertainties or concerns}

{Continue for all tasks}

## Execution Order

{Recommended sequence, noting parallelization opportunities and decision points}

## Risks

{Milestone-level risks and mitigation strategies}

## Definition of Done

{How we know this milestone is complete}

## Changes

{Record significant changes to scope or tasks as they occur}

### {Date}: {Change summary}

{What changed and why}
```
