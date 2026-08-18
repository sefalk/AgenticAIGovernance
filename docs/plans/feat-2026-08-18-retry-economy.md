<!-- copilot:generated | documenter | 2026-08-18 -->

# Implementation Plan: retry economy analyser

**Status:** COMPLETED
**Issue:** #43
**Branch:** `agent/43-retry-economy`

## Context

Issue #43. MANIFEST § 4 grants every agent the same two retries before
escalation. That allowance has never been checked against a workflow, so it is
a guess applied uniformly. #133 cannot be decided without it either: whether a
plan-critic is worth its cost depends on how much downstream rework it would
prevent.

## References

- Issue #43 — retry and escalation economy per agent, child of epic #22
- Issue #133 — the plan-critic decision that consumes these numbers
- Issue #12 — the lesson that a measurement must fail loudly, not report zero
- `agents/documenter.agent.md` — the Workflow Log Schema being read

## Scope Assessment

- **Files affected:** 4
- **Layers touched:** framework payload only (scripts, manifest, changelog)
- **Complexity tier:** Standard
- **Estimated size:** M
- **Risks:** the logs are self-reports written after the fact, so a retry nobody
  logged is invisible; the cause attribution is a heuristic over step order, not
  a record of intent. Mitigated by printing the heuristic above the numbers and
  by naming the one cause the logs cannot yield at all.

## Subtasks

### 1. Choose the source by measuring both

- **Action:** inventory the transcripts named in the issue and the workflow
  logs, then justify the substitution in the tool's own docstring.
- **Files:** `scripts/analyze-retry-economy.py`
- **Acceptance criteria:**
  - both candidate sources are counted before either is rejected
  - the reason for the substitution is readable from the tool, not only from
    the issue
- **Exit criterion:** field coverage of the chosen corpus measured and recorded.

### 2. The analyser

- **Action:** count retries per agent from repeated appearances in one `steps`
  list, attribute causes from the steps in between, and report the distribution
  alongside the aggregate.
- **Files:** `scripts/analyze-retry-economy.py`, `.af-manifest`
- **Acceptance criteria:**
  - retries, causes and escalations are reported per agent, with the retry
    number each escalation occurred at
  - the distribution is shown, not only the totals
  - an unreadable log is named and excluded, never counted as zero retries
  - no evidence exits 2; drift exits 1; a clean corpus exits 0
  - the cause the logs cannot yield is declared missing, not zero
- **Exit criterion:** `ruff check` clean; a full report over the 55-log corpus.

### 3. Regression suite

- **Action:** build synthetic corpora, one per claim, each constructed to break
  the claim it proves.
- **Files:** `scripts/test-retry-economy.ps1`, `.af-manifest`
- **Acceptance criteria:**
  - the empty directory, the missing directory and the all-unparsable corpus
    each exit 2
  - a summary contradicting its own steps, and a verdict outside the closed
    set, are each reported
  - `--json` parses and carries the same counts
- **Exit criterion:** `RESULT: ALL GREEN`.

## Quality Gates

- `python -m ruff check` on the analyser — clean
- `test-retry-economy.ps1` — 20/20
- Report produced against the 55-log corpus before any number was written down
- This document commits through both plan guards

## Plan Approval

Approved by: human (issue #43 agreed before implementation)

### Open Findings

- The corpus contradicts itself: 25 of 53 workflows have a `summary` disagreeing
  with their own `steps`, `summary.escalations` is 0 in all 55 logs while one
  step verdict says `ESCALATE`, six verdicts fall outside the MANIFEST closed
  set, and two logs are not valid YAML. Fixing the record is out of scope here
  and belongs to the documenter side.
- Tool errors as a retry cause remain unmeasurable until a step records them.

## Change Log

| Date | Change |
|---|---|
| 2026-08-18 | Plan created and executed |
