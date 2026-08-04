# Feat: measure and budget the conditional instruction set (#44)

<!-- copilot:generated | planner | 2026-08-04 -->

- **Created:** 2026-08-04
- **Issue:** [#44](https://github.com/sefalk/AgenticAIGovernance/issues/44) (child of #22)
- **Branch:** `agent/44-conditional-instruction-budget`
- **Complexity tier:** Standard
- **Status:** COMPLETED

## Current measurement

Re-measured on today's payload (the issue's table is from 2026-08-03; #23 and
#25 have landed since, so `architecture` is smaller than reported):

| Instruction file | Tokens | `applyTo` | Counted by the gate? |
|---|---:|---|---|
| `testing` | 3,640 | `**/test_*.py,tests/**/*.py,**/conftest.py` | no |
| `copilot-authoring` | 3,152 | `**/*.agent.md,**/*.prompt.md,**/*.instructions.md` | no |
| `architecture` | 1,617 | `src/**/*.py` | no |
| `quality-gates` | 1,512 | `**` | yes |
| `git-workflow` | 1,158 | `**` | yes |
| `tooling` | 882 | `**/.vscode/tasks.json` | no |
| `provenance` | 791 | `**` | yes |

**Conditional: 9,291 tok. Always-on: 4,868 tok** (incl. `copilot-instructions.md`,
1,383). The unwatched half is 1.9× the watched one.

> **Correction — measurement basis.** The table above was produced with a
> throwaway script counting `len(text) // 4` (decoded characters). The checker
> counts `stat().st_size // 4` (bytes on disk). The two disagree by up to 20%
> on files dense in `—`, `→` and `≥`, which cost 3 bytes but 1 character in
> UTF-8 — `architecture` reads 1,617 by characters and 1,966 by bytes. The
> checker's number is authoritative here because it is what the gate enforces;
> the conditional total it measured before any change was **9,699**, not 9,291.
> Whether bytes/4 systematically overstates prose-heavy instruction files
> against a real tokenizer is a separate question, and a separate issue —
> changing the estimator would re-baseline all three budgets at once.

The gate currently reports `PASS -- always-on 4,868/5,000; largest agent
coordinator 10,668/11,000`. Both numbers are true and both are incomplete.

## The finding that reorders the priorities

The issue frames the implementer as the problem (12,677 effective vs an 11,000
budget). The coordinator is worse. It sits at **10,668 of 11,000 — 97% — before
any conditional file loads**, and `copilot-authoring.instructions.md` matches
`**/*.agent.md`. The moment the coordinator reads or writes an agent file it is
at ~13,800, and the gate says PASS throughout.

So the same half-instrumentation affects the agent with the least headroom, not
just the one named in the issue.

## Design decision: report the bound, gate the set

Three options were considered for "measure the effective per-agent payload".

1. **Per-agent glob declarations.** Each agent declares which conditional files
   it plausibly loads. Most precise, and it will drift the first time an agent's
   role changes without the declaration being updated — a second source of truth
   for something already implied by the agent's role.
2. **Infer co-occurrence from the agent's tools/role.** Not computable offline
   and not deterministic. The checker's whole premise is that it needs no
   instrumentation.
3. **Worst case: always-on + own + all conditional.** An upper bound, exact and
   free. Its weakness is that it adds the *same* 9,291 to every agent, so it
   ranks agents identically to the current number.

Chosen: **(3) for reporting, and a budget on the conditional set as a whole for
enforcement.**

The reasoning: what can honestly be budgeted is the thing that actually grew
unwatched — the conditional set. Gating each agent's worst case would fail all
fifteen agents at once for a shared cause, which is a broken signal, not a
strict one. Gating the conditional total attacks the same cause once, and the
per-agent worst case makes the consequence visible so the number stops
flattering itself (the issue's own wording).

A worst case that exceeds the agent budget is printed with a marker but does
**not** set the exit code. That is a deliberate asymmetry, recorded here so it
is not mistaken for an oversight.

## Scope

| # | Subtask | Acceptance |
|---|---|---|
| 1 | `check-context-budget.py` reports the conditional set per file with its glob | Breakdown lists every non-universal instruction file |
| 2 | Per-agent worst case reported (own + always-on + conditional) | Agent table gains the bound; marker when it exceeds the agent budget |
| 3 | `AF_CONDITIONAL_BUDGET_TOKENS` gates the conditional total | Over budget → exit 1, named offenders, fix advice |
| 4 | Review each conditional `applyTo` for over-breadth; record the verdict either way | Decision documented per file |
| 5 | Reduce `testing` and `copilot-authoring`, or justify their size | Contract stays inline, reference depth moves to skills |
| 6 | Set the conditional budget to the achieved total plus headroom | Budget derived from a measurement, not chosen |

## Acceptance criteria

1. The conditional worst case is reported alongside the unconditional total.
2. The conditional total is enforced, not merely displayed.
3. A malformed or absent `AF_CONDITIONAL_BUDGET_TOKENS` behaves like the
   existing budgets — block on malformed, documented default when absent.
4. Every conditional `applyTo` has a recorded verdict, including "correctly
   scoped".
5. No enforceable rule is lost when files shrink — shorter, not thinner.

## Glob review (subtask 4)

Every conditional `applyTo` was assessed for over-breadth. **No file is
over-scoped.**

| File | `applyTo` | Verdict |
|---|---|---|
| `testing` | `**/test_*.py,tests/**/*.py,**/conftest.py` | Correctly scoped. Matches exactly the files whose authoring the rules govern. |
| `copilot-authoring` | `**/*.agent.md,**/*.prompt.md,**/*.instructions.md` | Correctly scoped, but the highest-impact glob in the set: framework maintenance edits agent files constantly, so for the coordinator it behaves as always-on. All three file types genuinely need the rules, so narrowing would drop real coverage. Cut the size instead — done in subtask 5. |
| `architecture` | `src/**/*.py` | Correctly scoped, and project-customisable (this project's own consumer maps it to `mpusage/**/*.py`). Now the largest conditional file at 1,966 tok; its content is project-owned, so reducing it is a per-project decision, not a framework one. |
| `tooling` | `**/.vscode/tasks.json` | Correctly scoped — the tightest glob in the set, a single file path. |

The finding matters for the design: the conditional set's cost came from **file
size, not glob width**. A glob audit alone would have found nothing to fix,
which is exactly why the instrument had to be a budget on the set.

## Outcome

| AC | Evidence |
|---|---|
| 1. Worst case reported alongside the unconditional total | `check-context-budget.py --verbose` prints `per-agent worst case (own + always-on + all N conditional)` with both figures per row |
| 2. Conditional total enforced, not displayed | `AF_CONDITIONAL_BUDGET_TOKENS`; over budget → exit 1 with named offenders (`test-context-budget.ps1` case O) |
| 3. Malformed/absent budget behaves like the others | Malformed → exit 2 (case P); absent → documented default, exit 0 (case Q) |
| 4. Every `applyTo` has a recorded verdict | Glob review table above — four files, four verdicts |
| 5. Shorter, not thinner | Both reduced files keep every enforceable rule inline; only lookup tables and material already present in `unit-testing` moved out |

**Measured effect**

| | Before | After |
|---|---:|---:|
| `testing.instructions.md` | 3,671 | 1,304 |
| `copilot-authoring.instructions.md` | 3,176 | 1,110 |
| Conditional set | 9,699 | 5,262 |
| Coordinator worst case | 20,367 | 15,959 |

`AF_CONDITIONAL_BUDGET_TOKENS=5500` — derived from the achieved 5,262 with the
same deliberately small headroom (~4%) as the other two budgets.

Test suite: 31/31 checks (19 pre-existing + 12 new). `test-quality-gate.ps1`
15/15 and `test-lint-gate.ps1` 21/21 unaffected.

**Not fixed, deliberately:** every agent still exceeds its budget in the worst
case (15 of 15). That is honest — always-on plus the coordinator's own prompt is
already 10,729 of 11,000. The worst case is a bound, not a prediction, and it is
reported rather than gated for exactly that reason.

## Risks

- **A rule moved into a skill is never read at the moment it is needed.** Same
  risk as #23 and #25; same mitigation — the *contract* stays in the
  instruction, only *reference material* moves.
- **The worst case is pessimistic and could be dismissed as noise.** Mitigated
  by labelling it a bound, not an estimate.
- **Setting the conditional budget to today's number would lock in the
  problem.** It is set in subtask 6, after the reduction, not before.
- **`testing.instructions.md` is project-customisable.** Anything moved must
  not assume the AF repo's own layout.

## Change log

| Date | Change |
|---|---|
| 2026-08-04 | Created. Re-measured the payload; found the coordinator at 97% of budget before any conditional file loads, which the issue does not mention. |
| 2026-08-04 | Instrumented: conditional breakdown, per-agent worst case, `AF_CONDITIONAL_BUDGET_TOKENS`. Corrected the measurement basis — the pre-change conditional total is 9,699 by the gate's own estimator, not 9,291. |
| 2026-08-04 | Glob review: no over-breadth found; cost is file size, not glob width. |
| 2026-08-04 | Extracted `skills/test-execution` and `skills/copilot-authoring`; conditional set 9,699 → 5,262. Budget calibrated to 5,500. Status → COMPLETED. |
