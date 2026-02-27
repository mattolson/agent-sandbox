---
name: plan-task
description: Plan and track execution of a task. Use when starting implementation of a task defined in a milestone plan.
---

# Task Planning and Execution

Part of the three-tier planning system. See `/plan` for an overview.

This skill guides implementation of a single task, from initial planning through completion. It maintains an execution log that captures problems, decisions, and learnings along the way.

## Inputs

Before starting, read:
- The milestone plan containing this task
- `docs/plan/learnings.md` - to incorporate lessons from previous work
- Any relevant decision documents in `docs/plan/decisions/`

## Output

Two files in `docs/plan/milestones/{milestone}/tasks/{task}/`:
- `task.md` - The plan and final outcome (living document, update as things change)
- `execution-log.md` - Running log updated during implementation (captures the journey)

The task plan is a **living document**. Update scope, approach, and checklist as things evolve. The execution log preserves history, so there's no need to treat the plan as a snapshot.

## Lifecycle

A task moves through three phases:

### Phase 1: Planning

Before writing code, understand what we're building and how. Planning is iterative - expect to refine the approach through discussion before it's finalized.

**This phase requires your approval before proceeding to execution.**

#### 1.1 Context Review

- Review the task's summary, scope, and acceptance criteria from the milestone plan
- Review applicable learnings from previous tasks
- Confirm understanding of what "done" looks like

#### 1.2 Codebase Exploration

- Identify the files and systems involved
- Understand existing patterns and conventions
- Note integration points with other code

#### 1.3 Approach Design

- Outline the implementation approach
- Identify changes needed (new files, modifications, deletions)
- Consider edge cases and error handling
- Flag uncertainties that need resolution

Capture the plan in the task document. Review and iterate until the approach is solid, then get explicit approval before proceeding to implementation.

### Phase 2: Execution

During implementation:
- Keep the implementation steps checklist in `task.md` current as steps are completed
- Maintain the execution log in `execution-log.md`

#### When to Update the Log

Update the execution log whenever:
- **A new issue is encountered** - describe the issue and its solution
- **A key decision is made** - capture the choice and rationale
- **A lesson is learned** - note insights that apply to future work
- **10 minutes have passed** since the last update - review and capture any salient information

Do not let updates accumulate. Frequent, small updates are more valuable than infrequent summaries.

#### What to Capture

- **Issues and solutions**: Problems encountered and how they were resolved
- **Decisions**: Technical choices and their rationale
- **Scope changes**: Anything that changed from the original plan and why
- **Observations**: Things noticed that might be relevant later

#### Checkpoints

At natural breakpoints, review progress:
- Is the approach still sound?
- Have we discovered anything that changes the plan?
- Are there decisions that should be recorded formally in `docs/plan/decisions/`?
- Does the implementation steps checklist need updating (new steps, changed steps, removed steps)?

### Phase 3: Completion

When the task is done:

#### 3.1 Acceptance Verification

- Verify each acceptance criterion is met
- Confirm tests are passing
- Ensure the PR is ready for review

#### 3.2 Learning Capture

Review the execution log and extract learnings from this task:
- What would we do differently next time?
- What worked well that we should repeat?
- What did we learn that applies to future tasks?

Consolidate and distill insights from the execution log entries into `docs/plan/learnings.md`.

#### 3.3 Cleanup

- Update the milestone plan if this task revealed new information
- Create decision documents for any significant decisions made
- Note if downstream tasks are affected

## Task Document Template

Create at `docs/plan/milestones/{milestone}/tasks/{task}/task.md`:

```markdown
# Task: {identifier} - {name}

## Summary

{From milestone plan}

## Scope

{From milestone plan, updated if changed}

## Acceptance Criteria

{From milestone plan}
- [ ] {Criterion 1}
- [ ] {Criterion 2}

## Applicable Learnings

{Lessons from previous work that apply to this task}

## Plan

### Files Involved

{List of files to create, modify, or delete}

### Approach

{How we're going to implement this}

### Implementation Steps

- [ ] {Step 1}
- [ ] {Step 2}
- [ ] {Step 3}

### Open Questions

{Uncertainties to resolve during implementation}

## Outcome

### Acceptance Verification

- [x] {Criterion 1 - verified}
- [x] {Criterion 2 - verified}

### Learnings

{What we learned from this task - also append to docs/plan/learnings.md}

### Follow-up Items

{Anything discovered that affects other tasks or the milestone plan}
```

## Execution Log Template

Create at `docs/plan/milestones/{milestone}/tasks/{task}/execution-log.md`.

Entries are in **reverse chronological order** - newest at the top, so the latest activity is always visible first.

```markdown
# Execution Log: {identifier} - {name}

## {Timestamp} - Latest entry

{Entry describing what happened}

**Issue:** {If applicable - describe the problem}
**Solution:** {How it was resolved}

**Decision:** {If applicable - what was decided and why}

**Learning:** {If applicable - insight for future work}

## {Timestamp} - Previous entry

{Earlier entry}
```
