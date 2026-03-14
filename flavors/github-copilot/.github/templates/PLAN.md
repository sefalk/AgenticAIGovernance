# Implementation Plan

<!-- copilot:generated | planner | YYYY-MM-DD -->
<!-- Naming: {type}-{YYYY-MM-DD}-{slug}.md  (e.g., feat-2026-03-10-bucketing-v2.md) -->
<!-- Location: docs/plans/ (or project-specific convention discovered by coordinator) -->
<!-- The coordinator determines the filename and persists this file. -->

**Workflow:** <!-- Feature Development | Bug Fix | Refactoring -->
**Branch:** `agent/<!-- workflow-id -->`
**Status:** <!-- DRAFT | APPROVED | IN_PROGRESS | COMPLETED -->

## Context

<!-- What is being built/fixed and why. Include the user's original request
     or a summary of the triggering issue.
     Use blockquotes (>) for non-obvious decisions, caveats, or "why not X?" reasoning. -->

## References

<!-- Related ADRs, prior plans, notebooks, or external docs. Delete if none. -->

## Scope Assessment

- **Files affected:** <!-- count -->
- **Layers touched:** <!-- domain core / ports / adapters / orchestrators -->
- **Complexity tier:** <!-- Trivial / Standard / Deep — see quality-gates.instructions.md -->
- **Estimated size:** <!-- small (1-2 subtasks) / medium (3-5) / large (6+) -->
- **Not in scope:** <!-- Optional — explicitly excluded modules, files, or concerns -->
- **Risks:** <!-- list any concerns, unknowns, or high-impact areas -->
- **Rollback plan:** <!-- For Deep tier or high-risk changes only. How to revert if needed. -->

## Current Baseline (optional)

<!-- Fill only for coverage expansion, refactoring, or performance work.
     Capture metrics that the acceptance criteria will compare against.
     Delete this section if not applicable. -->

## Subtasks

### 1. <!-- Subtask title -->

- **Action:** <!-- what to do -->
- **Files:** <!-- which files to create or modify -->
- **Layer:** <!-- Domain Core / Port / Adapter / Orchestrator -->
- **Acceptance criteria:**
  - <!-- criterion 1 — testable -->
  - <!-- criterion 2 — measurable -->
- **Exit criterion:** <!-- single condition that marks this subtask done -->
- **Tests needed:** <!-- what tests should be written -->
- **Dependencies:** <!-- which subtasks must complete first, or "none" -->
- **Status:** <!-- TODO | IN_PROGRESS | DONE | SKIPPED -->

<!-- Copy this block for each additional subtask.
     For Deep-tier plans, consider organising subtasks as Phases with
     Effort/Risk/Prerequisite headers and per-phase exit criteria:

     ### Phase N — Title
     **Effort:** X · **Risk:** Y · **Prerequisite:** Z
     [task table / description]
     **Exit criterion:** ... -->

## Implementation Sequence

<!-- Ordered list showing the dependency chain -->
1. <!-- Subtask → Subtask → ... -->

## Quality Gates

| Gate | Target | Type |
|---|---|---|
| Line coverage | <!-- per module: Domain ≥ 90%, Ports ≥ 80%, Adapters ≥ 60% --> | HARD |
| Architecture compliance | <!-- boundaries to verify --> | SOFT |
| <!-- additional gate --> | <!-- target --> | <!-- HARD / SOFT / ADVISORY --> |

- **Suggested workflow:** <!-- Full TDD / Quick Fix / Trivial Fix / Review Only -->
- **Skills consulted:** <!-- list of SKILL.md files read, or "none — no applicable skills" -->

## Plan Approval

**Approved by:** <!-- human | auto-approved (< 4 subtasks, no high-risk) -->
**Verdict:** <!-- APPROVED | APPROVED-WITH-FINDINGS -->

### Open Findings

<!-- List any findings from plan approval. Tracked here and resolved
     during implementation. Remove when resolved. -->

- <!-- finding 1 -->

## Follow-Up

<!-- Populated by the documenter at end-of-workflow.
     Captures SHOULD-FIX and ADVISORY items from critic reviews
     that were not addressed during this workflow. Remove this
     section if empty. -->

- <!-- item 1 -->

## Change Log

<!-- Updated during and after implementation. Each entry records what
     changed and when. The documenter finalises this at end-of-workflow. -->

| Date | Agent | Change |
|---|---|---|
| <!-- YYYY-MM-DD --> | planner | Initial plan created |
