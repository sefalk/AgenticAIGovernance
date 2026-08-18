<!-- copilot:generated | documenter | 2026-08-18 -->

# Implementation Plan: workflow log schema gate

**Status:** COMPLETED
**Issue:** #137
**Branch:** `agent/137-workflow-log-schema`

## Context

Issue #137. `documenter.agent.md` gives the workflow log a schema — a closed
set of statuses, a closed set of verdicts, a summary block — and nothing has
ever read a log back against it. The #43 analyser was the first tool to try,
and it found the corpus does not speak the schema: 2 of 55 logs are not valid
YAML, 16 use a status or verdict from outside the sets, and 25 of the 53
readable summaries contradict their own steps. The logs are the framework's
only record of what its agents did; a record the framework cannot read is not
a record.

## References

- Issue #137 — the workflow log has a schema and no validator
- Issue #91 — the documenter wrote a `completed:` 6.5 h in the future; the fix
  was to stop the model authoring it, the precedent followed here for counters
- Issue #125 — a guard that passes because it never runs
- Issue #43 — `analyze-retry-economy.py`, which supplied the measurement and
  whose definition of a retry this tool must match exactly
- `agents/documenter.agent.md` — the schema being enforced

## Scope Assessment

- **Files affected:** 7
- **Layers touched:** framework payload only (hook script, both hook twins,
  agent file, manifest, changelog, tests)
- **Complexity tier:** Standard
- **Estimated size:** M
- **Risks:** a blocking gate on a false positive strands the documenter at the
  end of a workflow. Mitigated by keeping the rules narrow (two closed sets and
  "does it parse"), by skipping block-scalar bodies so prose cannot trigger a
  violation, and by `ALLOW_WORKFLOW_LOG_SCHEMA=1` for a human who disagrees.
  Second risk: two tools disagreeing about what a retry is. Mitigated by
  deriving with the analyser's definition and checking both against the corpus.

## Subtasks

### 1. Correct the mechanism before building it

- **Action:** verify the pre-commit guard proposed in the issue can fire.
- **Files:** none — measurement only
- **Acceptance criteria:**
  - the claim is tested against a real repository, not reasoned about
  - if it fails, the issue is corrected in public before code is written
- **Exit criterion:** `git check-ignore -v` run against a real log; the issue
  carries the correction and the revised design.

### 2. The checker

- **Action:** scan a log for status and verdict vocabulary and for parseability;
  derive `summary.retries` and `summary.escalations` from the steps and rewrite
  them under `--fix-counters`.
- **Files:** `hooks/scripts/check-workflow-log.py`, `.af-manifest`
- **Acceptance criteria:**
  - a violation names the line and the offending value
  - a block scalar body is not scanned
  - a `verdict` outside a `steps` block is not read as a step verdict
  - PyYAML absent declares the parse rule unrun, never passed
  - the derived counters match `analyze-retry-economy.py` on the real corpus
  - clean exits 0, violations exit 1, cannot-check exits 2
- **Exit criterion:** `ruff check` clean; a read-only run over all 55 logs.

### 3. Wire it into the documenter's Stop hook

- **Action:** add a blocking schema gate and an advisory counter derivation to
  both hook twins.
- **Files:** `hooks/scripts/documenter-stop.ps1`, `hooks/scripts/documenter-stop.sh`
- **Acceptance criteria:**
  - the gate runs after the artifact gate, so a missing log blocks first
  - a violation blocks with a reason naming the vocabulary to use
  - the derivation never fails the hook
- **Exit criterion:** both files parse; the PowerShell twin verified by parser.

### 4. Take the counters away from the documenter

- **Action:** tell the documenter to write `0` and say why, mirroring the
  existing `started:`/`completed:` paragraph.
- **Files:** `agents/documenter.agent.md`
- **Acceptance criteria:**
  - the instruction cites the measurement, not the rule
  - the context budget still passes
- **Exit criterion:** `check-context-budget.py` PASS.

### 5. Regression suite

- **Action:** one fixture per rule, each built by changing exactly one thing in
  a conforming log.
- **Files:** `scripts/test-workflow-log-schema.ps1`, `.af-manifest`
- **Acceptance criteria:**
  - every negative case is proved to differ from the conforming fixture, so a
    silently missed substitution cannot pass as a result
  - `APPROVED (Attempt 2)` passes and `APPROVED-WITH-ISSUES` fails
  - the override is shown both on and off
  - without `--fix-counters` nothing is written
- **Exit criterion:** `RESULT: ALL GREEN`.

## Quality Gates

- `python -m ruff check` on the checker — clean
- `test-workflow-log-schema.ps1` — 26/26
- `test-retry-economy.ps1` — 20/20, unchanged
- Read-only run over all 55 real logs before any number was written down
- Counter derivation compared against `analyze-retry-economy.py` output
- `check-context-budget.py` — PASS
- This document commits through both plan guards

## Plan Approval

Approved by: human (issue #137 agreed before implementation)

### Open Findings

- The 16 non-conforming logs already in the consuming project are not migrated
  by this change. The gate applies from the next workflow onward; the existing
  corpus stays as evidence.
- The parse rule is the only rule that can be skipped, and it is skipped exactly
  when PyYAML is absent. A consumer without PyYAML gets vocabulary enforcement
  and no parse check, and is told so.

## Change Log

| Date | Change |
|---|---|
| 2026-08-18 | Plan created and executed |
