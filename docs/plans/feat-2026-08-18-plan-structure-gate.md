<!-- copilot:generated | documenter | 2026-08-18 -->

# Implementation Plan: plan structure gate

**Status:** COMPLETED
**Issue:** #132
**Branch:** `agent/132-plan-structure-gate`

## Context

Issue #132. The plan is the only first-class artifact with no reviewer; its gate
was a subtask count. #26 budgeted the plan's length and explicitly left its
quality alone. A dedicated plan-critic is deferred to #133 until the retry cost
it would prevent has been measured.

## References

- Issue #132 — problem statement and the C+B split
- Issue #133 — the deferred plan-critic decision
- `skills/tdd-orchestration/SKILL.md` § 4 — the gate that was a count
- `hooks/scripts/check-plan-budget.py` — the guard this one runs beside

## Scope Assessment

- **Files affected:** 9
- **Layers touched:** framework payload only (hooks, skills, agents, templates)
- **Complexity tier:** Standard
- **Estimated size:** M
- **Risks:** a structural rule can be satisfied with noise; it raises the floor,
  not the ceiling. Rejecting a formally unusual but legitimate plan is mitigated
  by keeping the rules to what the templates themselves define, by the DRAFT
  stand-down, and by `ALLOW_PLAN_STRUCTURE=1`.

## Subtasks

### 1. Mechanical guard

- **Action:** add `check-plan-structure.py` to the pre-commit shim, beside the
  budget guard and over the same scope.
- **Files:** `hooks/scripts/check-plan-structure.py`, `hooks/git/pre-commit`,
  `.af-manifest`
- **Acceptance criteria:**
  - a placeholder field, an invented section, a subtask without acceptance
    criteria, a missing scope field, an unstated tier, and a plan with no
    subtasks each block the commit and are named in the output
  - an investigation document is checked against `INVESTIGATION.md`, not
    rejected for lacking subtasks
  - a conforming plan produces no output at all
  - a git failure exits 2 rather than passing
- **Exit criterion:** `ruff check` clean, guard silent on this branch's own
  commits.

### 2. Regression suite

- **Action:** mirror `test-plan-budget.ps1` with a fixture per rule, each
  negative case being the conforming plan with one thing taken away.
- **Files:** `scripts/test-plan-structure.ps1`, `.af-manifest`
- **Acceptance criteria:**
  - every rule has a case that fails when the rule is removed
  - duplicate subtask numbers are both checked, not collapsed
- **Exit criterion:** `RESULT: ALL GREEN`.

### 3. Substantive gate

- **Action:** replace the subtask count in `tdd-orchestration` § 4 with five
  questions, persisted as `plan_review` in the workflow log and audited by the
  compliance-checker post-flight.
- **Files:** `skills/tdd-orchestration/SKILL.md`, `agents/documenter.agent.md`,
  `agents/compliance-checker.agent.md`, `agents/planner.agent.md`,
  `skills/git-workflow/SKILL.md`
- **Acceptance criteria:**
  - the escalation triggers are unchanged
  - an absent `plan_review` block is reported as skipped, not as passed
  - the context budgets still pass
- **Exit criterion:** `check-context-budget.py` PASS.

## Quality Gates

- `python -m ruff check` on the new guard — clean
- `test-plan-structure.ps1` — 25/25
- `test-plan-budget.ps1` — unchanged, still green
- `check-context-budget.py` — PASS
- This document commits through both plan guards

## Plan Approval

Approved by: human (issue #132 agreed before implementation)

### Open Findings

- Measured against the framework's own 34 plan documents, exactly one passes
  the new guard. The corpus is not rewritten — the guard reads the staged blob.

## Change Log

| Date | Change |
|---|---|
| 2026-08-18 | Plan created and executed |
