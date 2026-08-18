# Implementation Plan

<!-- copilot:generated | documenter | 2026-08-18 -->

**Workflow:** Feature Development
**Branch:** `agent/26-plan-tier-budget`
**Status:** COMPLETED
**Issue:** #26 (child of epic #22) · **Base:** `dev` @ `d606219`

## Context

Plans are the largest artifact a workflow writes. The issue proposed cutting
narrative sections out of the template so a Standard plan would land under
3,000 tokens.

Measured first, in a consuming project — 29 plans, 768 KB:

| Tier | n | avg characters | avg tokens |
|---|---|---|---|
| Standard | 19 | 20,555 | ~5,100 |
| Deep | 10 | 38,840 | ~9,710 |

Two findings contradicted the proposal:

- The template is **4 KB**. At ~20 KB per Standard plan, the scaffolding is not
  what costs — what is written into it is.
- **45%** of Standard-plan text sat in sections the template never defines,
  invented one plan at a time. Only 23% sat in sections the proposal would have
  removed, and removing all of them leaves ~3,900 tokens — still over the
  target the issue itself set.

> A template cannot hold a limit. Nothing in a template says *and no more than
> this*; it only offers headings, and a model that has more to say adds one.

## References

- Issue #26, epic #22 (token and credit efficiency)
- #107 / #125 — the context budget and its blind spot; same guard shape
- #130 — the three write passes, split out of this work

## Scope Assessment

- **Files affected:** 8
- **Layers touched:** framework payload (config, hook script, template, agent,
  skill), plus deploy manifest
- **Complexity tier:** Standard
- **Estimated size:** medium (3 subtasks)
- **Not in scope:** reducing the number of write passes — measured, documented,
  and filed as #130, because it requires changing the planner's read-only
  charter.
- **Risks:** a false block on a plan whose tier the guard cannot read. Mitigated
  by charging Standard (not blocking outright) and by the documented override.
- **Rollback plan:** remove the checker from the pre-commit shim; the config
  keys become inert.

## Subtasks

### 1. Budget the plan by tier and enforce it

- **Action:** add `PLAN_BUDGET_{TRIVIAL,STANDARD,DEEP}_TOKENS` to `af-env.conf`
  and a pre-commit checker that measures the staged blob of every `*.md` under
  a `plans/` directory except `WIP.md`.
- **Files:** `af-env.conf`, `hooks/scripts/check-plan-budget.py`,
  `hooks/git/pre-commit`, `.af-manifest`
- **Layer:** framework payload
- **Acceptance criteria:**
  - Tier is read from the plan's own text; an unstated tier is charged Standard.
  - The template's `<!-- Trivial / Standard / Deep -->` placeholder is not read
    as a tier.
  - Trivial budget 0 — a Trivial fix gets no plan file.
  - A commit that stages no plan pays nothing and prints nothing.
- **Exit criterion:** checker blocks an over-budget plan and passes an
  in-budget one, from a throwaway repository.
- **Tests needed:** exit-code contract, tier resolution, scope, override.
- **Status:** DONE

### 2. Scale the template and the planner by tier

- **Action:** mark `[Deep]`-only sections, state the budget in the template,
  forbid sections the template does not define, and replace the planner's
  verbatim copy of the template with a reference plus the tier rules.
- **Files:** `templates/PLAN.md`, `agents/planner.agent.md`
- **Layer:** framework payload
- **Acceptance criteria:**
  - Standard tier omits Current Baseline, Implementation Sequence, Rollback.
  - The planner gains a SOFT exit gate for the tier budget.
  - The context budget still passes for the agent set.
- **Exit criterion:** `check-context-budget.py` PASS.
- **Status:** DONE

### 3. Record the write passes

- **Action:** document that the plan text is emitted three times (planner
  returns, coordinator repeats into the delegation prompt, documenter writes),
  name the cause, and file the reduction separately.
- **Files:** `skills/git-workflow/SKILL.md`, `CHANGELOG.md`
- **Layer:** documentation
- **Acceptance criteria:** the count and its structural cause are written down;
  a follow-up issue exists.
- **Exit criterion:** #130 filed and linked to #22.
- **Status:** DONE

## Quality Gates

| Gate | Target | Type |
|---|---|---|
| `test-plan-budget.ps1` | 18/18 checks | HARD |
| `test-context-budget.ps1` | 82/82 checks | HARD |
| `python -m ruff check` | clean | HARD |
| Guard is silent on a passing commit | no output, exit 0 | HARD |
| Numbers quoted are measured, not assumed | every figure traced to a run | SOFT |

- **Suggested workflow:** Full TDD
- **Skills consulted:** git-workflow

## Change Log

| Date | Agent | Change |
|---|---|---|
| 2026-08-18 | planner | Measured the corpus; proposal revised against it |
| 2026-08-18 | implementer | Budget, guard, template, planner |
| 2026-08-18 | test-writer | 18-check regression suite |
| 2026-08-18 | documenter | Skill, changelog, this plan; #130 filed |
