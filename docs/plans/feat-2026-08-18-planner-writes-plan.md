<!-- copilot:generated | documenter | 2026-08-18 -->

# Implementation Plan: the planner writes its own plan

**Status:** COMPLETED
**Issue:** #130
**Branch:** `agent/130-planner-writes-plan`

## Context

Issue #130. The plan text is emitted three times before it reaches disk: the
planner returns it, the coordinator repeats it verbatim inside the documenter's
delegation prompt, and the documenter emits it again as the argument to
`createFile`. All three are output emissions. Measured over the 66 plans in
this framework and one consuming project, a plan is a median 1,747 tokens when
it first lands, so the two redundant passes cost a median 3,494 output tokens
per workflow and roughly 390,000 across the corpus. The cause is a
least-privilege rule applied by agent rather than by path: the planner is
read-only, so the agent that produces the document cannot be the one that saves
it.

## References

- Issue #130 — the plan is emitted three times before it reaches disk
- Issue #22 — the epic this belongs to; split out of #26
- Issue #64 — a pathless write cannot be cleared by a path guard
- Issue #69 — an unknown write tool must not fail open
- `hooks/scripts/test-writer-pretooluse.ps1` — the prior art, a denylist
- `skills/tdd-orchestration/SKILL.md` § 4 — where the relay is specified

## Scope Assessment

- **Files affected:** 13
- **Layers touched:** framework payload only (hook twins, agent files, skills,
  prompt, manifest, changelog, tests)
- **Complexity tier:** Standard
- **Estimated size:** M
- **Risks:** widening any agent's write surface is the change most likely to be
  regretted. Mitigated by making the guard an allowlist rather than a denylist —
  the planner's legitimate surface is one directory, so everything else is
  refused by default instead of enumerated — and by proving the confinement with
  cases that try to escape rather than cases that behave. Second risk: the
  coordinator reviewing a plan it no longer has in context. Mitigated by the
  coordinator retaining `read/readFile`, which it already needs for § 4.

## Subtasks

### 1. Measure before changing anything

- **Action:** size the plan as first committed, not as finalised, since the
  relay carries the first version.
- **Files:** none — measurement only
- **Acceptance criteria:**
  - the corpus is both repositories, not a sample
  - the relay size is read from the commit that added each file
  - the earlier claim in the issue is corrected in public if wrong
- **Exit criterion:** 66 plans measured; the issue comment corrected to say two
  emissions are removed, not one, because `createFile` takes the body as an
  argument.

### 2. The confinement guard

- **Action:** a `planner-pretooluse` hook that allows `.md` writes under a
  `plans/` directory inside the code root and denies everything else.
- **Files:** `hooks/scripts/planner-pretooluse.ps1`,
  `hooks/scripts/planner-pretooluse.sh`, `.af-manifest`
- **Acceptance criteria:**
  - the allowed path definition matches `check-plan-budget.py::_is_plan`
  - a resolved path outside the code root is denied, so traversal and absolute
    paths cannot reach an allowed-looking directory
  - a write with no path is denied rather than passed
  - an unrecognised write tool is denied
  - a batch write is denied if any one path is outside the plan directory
- **Exit criterion:** both twins written; the PowerShell twin executes under the
  suite.

### 3. Give the planner the path and take away the relay

- **Action:** add `edit/createFile` and the hook registration; instruct the
  planner to write the file and return its path, not its text.
- **Files:** `agents/planner.agent.md`, `agents/documenter.agent.md`,
  `agents/coordinator.agent.md`, `skills/tdd-orchestration/SKILL.md`,
  `skills/git-workflow/SKILL.md`, `skills/copilot-authoring/SKILL.md`,
  `prompts/af-quick-fix.prompt.md`, `MANIFEST.md`
- **Acceptance criteria:**
  - the delegation prompt no longer contains `{planner_output}`
  - the coordinator's § 4 review reads the file
  - the documenter no longer lists plan persistence as a responsibility
  - the Quick Fix investigation document loses the same relay
  - MANIFEST § 4 states the exception by path, and critics and the arbiter are
    unchanged
  - the context budget still passes
- **Exit criterion:** `check-context-budget.py` PASS.

### 4. Regression suite

- **Action:** one case per escape route, each piped into the hook as real stdin.
- **Files:** `scripts/test-planner-write-scope.ps1`, `.af-manifest`
- **Acceptance criteria:**
  - a majority of cases are attempts to write outside the plan directory
  - allow and deny are distinguished by the hook's actual output, so a crashing
    hook fails both directions rather than passing one
  - the denial names the path it refused
- **Exit criterion:** `RESULT: ALL GREEN`.

## Quality Gates

- `test-planner-write-scope.ps1` — 20/20, of which 14 are escape attempts
- `test-hooks.ps1` — 267/0, unchanged
- `check-context-budget.py` — PASS
- The measurement was run over both repositories before any number was written
- This document commits through both plan guards

## Plan Approval

Approved by: human (option (a) approved on issue #130 before implementation)

### Open Findings

- The bash twin cannot be executed on this host, so it is reviewed against its
  PowerShell counterpart and the existing `_common.sh` helpers rather than run.
  The same limitation applies to every `.sh` hook in the repository.
- The guard confines by path, not by intent: a planner that writes a plan-shaped
  file full of source code is still permitted. Content is the critics' problem,
  and the plan structure gate already reads what was written.

## Change Log

| Date | Change |
|---|---|
| 2026-08-18 | Plan created and executed |
