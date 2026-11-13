**Workflow:** Bug Fix
**Branch:** `agent/543-hook-suite-preflight`
**Status:** IN_PROGRESS
**AF Version:** 2.0.0

## Context

AF #543 records that the hook suite checks whether pytest can seed its fixture venv only after hundreds of assertions and several minutes of hook subprocesses. Move this existing prerequisite gate before any hook test begins, and add an isolated regression proving a missing pytest host exits before launching a hook. The Local release line is independently owned; no 1.28.x changes are in scope.

## References

- AF #543 — late pytest fixture prerequisite failure
- AF #447 comment 6851558764 — current-source suite baseline and raw timing evidence
- AF #528 comment 6851620341 — approved performance priorities

## Scope Assessment

- **Files affected:** 3
- **Layers touched:** Test harness only
- **Complexity tier:** Standard
- **Estimated size:** small (2 subtasks)
- **Not in scope:** Hook policy, shared runner behavior, Local release line, global dependency installs, MP
- **Risks:** Preserve supported host-interpreter search and the existing no-pytest-on-PATH fixture test. An early prerequisite error must not be confused with a skipped or passing suite.

## Current Baseline

- Source: `cd71b950bccba2f79410728b049f1eb8019af29d`, VERSION 2.0.0.
- Successful scoped `test-hooks.ps1`: 645 passed, 0 failed, 716.2 seconds.
- Without pytest on the fixture host: 633 passed before one late prerequisite failure at 791.4 seconds.

## Subtasks

### 1. Proving the missing-host failure is early

- **Action:** Add a focused suite that runs `test-hooks.ps1` in an isolated disposable payload with a Python command that cannot import pytest, and records attempted hook-process launches.
- **Files:** `flavors/github-copilot/.github/scripts/test-hooks-preflight.ps1`, `flavors/github-copilot/.github/scripts/suite-scope.json`
- **Layer:** Test harness
- **Acceptance criteria:**
  - The isolated suite fails against the current late-check behavior because hook processes run before the pytest prerequisite failure.
  - The isolated suite uses no network, shared venv, user settings or real secrets and cleans up its own temporary fixture.
  - The canonical runner selects the new suite when `test-hooks.ps1` changes.
- **Exit criterion:** The focused regression is observed failing for the late prerequisite ordering.
- **Tests needed:** Run only `test-hooks-preflight.ps1` through the canonical runner during Red.
- **Dependencies:** none
- **Status:** TODO

### 2. Moving the fixture-host check to suite startup

- **Action:** Resolve and verify the existing pytest-capable host, prepare the same fixture venv, and fail with an explicit nonzero diagnostic before hook cases or expensive fixtures begin; remove the duplicate late setup/assertion while preserving the existing successful path.
- **Files:** `flavors/github-copilot/.github/scripts/test-hooks.ps1`
- **Layer:** Test harness
- **Acceptance criteria:**
  - Missing pytest exits nonzero before any hook subprocess or expensive test fixture starts.
  - The failure names the missing pytest-capable fixture host; it is not reported as PASS or SKIP.
  - With pytest available, all existing assertions pass, including the fixture that removes pytest from PATH while supplying a venv with pytest.
  - No packages are installed by the suite and no test runner is changed.
- **Exit criterion:** The focused regression passes and the canonical hook-suite run passes with no skips.
- **Tests needed:** Focused preflight regression and the scoped `test-hooks.ps1` canonical run.
- **Dependencies:** Subtask 1
- **Status:** TODO

## Implementation Sequence

1. Subtask 1 → observe Red and review the regression.
2. Subtask 2 → implement the early preflight and verify focused and canonical suites.

## Quality Gates

| Gate | Target | Type |
|---|---|---|
| Regression behavior | Missing pytest fails before hook launches; supported pytest fixture path remains green | HARD |
| Scope and line isolation | Only AF 2.x worktree and listed test-harness files | HARD |
| Architecture and maintainability | Reuse the existing suite runner and host-discovery behavior | SOFT |

- **Suggested workflow:** Full TDD
- **Skills consulted:** `git-worktrees`, `tdd-orchestration`, `unit-testing`, `test-execution`

## Plan Approval

**Approved by:** auto-approved (2 subtasks, no high-risk changes)
**Verdict:** APPROVED

## Change Log

| Date | Agent | Change |
|---|---|---|
| 2026-11-13 | coordinator | Initial plan from AF #543 evidence |
