# Feat: measure and budget the conditional instruction set (#44)

<!-- copilot:generated | planner | 2026-08-04 -->

- **Created:** 2026-08-04
- **Issue:** [#44](https://github.com/sefalk/AgenticAIGovernance/issues/44) (child of #22)
- **Branch:** `agent/44-conditional-instruction-budget`
- **Complexity tier:** Standard
- **Status:** IN PROGRESS

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
