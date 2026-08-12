<!-- copilot:generated | documenter | 2026-08-12 -->

# Fix: the token divisor was a folk constant — now it is a measurement (issue #59)

- **Issue:** [#59](https://github.com/sefalk/AgenticAIGovernance/issues/59)
- **Branch:** `agent/59-calibrate-token-divisor`
- **Base:** `dev` @ `a1cbc8b`
- **Complexity tier:** Standard
- **Status:** COMPLETED
- **Date:** 2026-08-12

## Problem

Issue #59 raised two defects in `check-context-budget.py`. The first — that the
estimator measured bytes on disk, so it moved when nothing the model reads had
changed — was fixed on 2026-08-07 (see
[fix-2026-08-07-context-budget-invariance.md](fix-2026-08-07-context-budget-invariance.md)).

The second was left open: the divisor. `CHARS_PER_TOKEN = 4` is the "~4
characters per token" rule of thumb for English prose, and the code said so
plainly:

> It has not been calibrated against a tokenizer for this payload, which is
> denser markdown.

The issue's hypothesis was that this understates reality:

> Dense markdown of this kind typically runs closer to ~3–3.5 characters per
> token, which would mean the budgets understate real consumption by 15–30%.

A budget that is wrong by 30% in the unsafe direction is not a budget. So the
number had to be either corrected or defended — but it could not stay
undefended, because an unexplained constant is indistinguishable from a wrong
one, and nobody can tell which by reading it.

## Measurement

All 24 files the gate measures (`copilot-instructions.md`, `instructions/*.md`,
`agents/*.agent.md`), encoded with tiktoken 0.13.0 `o200k_base` and
cross-checked against `cl100k_base` (the two agree to within 0.05 chars/token):

| | |
|---|---|
| Characters | 183,317 |
| Real tokens | 44,602 |
| **Aggregate ratio** | **4.110 chars/token** |
| Per-file range | 3.83 (`copilot-authoring.instructions.md`) – 4.29 (`architecture.instructions.md`) |
| Per-file median | 4.111 |

Error of the current `characters/4` estimate against that:

| Scope | Error |
|---|---|
| Per file | −4.2% … +7.2%, median +2.8% |
| Always-on set | +3.6% (est 4,867 vs actual 4,697) |
| Conditional set | +1.7% (est 5,442 vs actual 5,353) |
| Agents | +2.8% (est 35,519 vs actual 34,552) |

**The hypothesis is falsified.** The payload runs at 4.110 characters per
token, not 3–3.5. The divisor does not understate consumption by 15–30%; it
*over*states it by 2.8% — which is the conservative direction for a ceiling.
The issue's own worked example survives as the worst case in the payload:
`architecture.instructions.md` is 6,469 characters → 1,617 estimated, 1,509
actual, +7.2%.

## Change

1. **The divisor stays 4, and the reason changes from folklore to data.** The
   comment above `CHARS_PER_TOKEN` now records the date, the tokenizers, the
   measured ratio, the per-file band and the direction of the error. Moving it
   to 4.11 would shift every figure by under 3% — inside the noise this gate
   exists to ignore — and would *relax* all three ceilings for nothing.

2. **`--verify-tokenizer`.** A constant that nobody can re-derive decays back
   into folklore as soon as the payload's character mix drifts. The flag
   re-runs the calibration and prints per-file and aggregate drift. It imports
   tiktoken lazily, inside the handler, so the gate itself stays
   dependency-free. It exits 1 when the aggregate error exceeds 10%, because
   these figures are quoted to humans as "tokens" in plans and pull requests; a
   constant that far off is no longer describing the payload. Absent tiktoken
   it exits **2 (BLOCKED)**, not 0 — a verification that could not run is an
   unknown result, and reporting "calibration fine" on the strength of a
   missing import is the exact failure mode this repository keeps closing.

3. **The error band is documented next to the budgets** in `af-env.conf`,
   which is where someone deciding whether to raise a ceiling will be looking.

4. **The budgets are not restated.** They were already calibrated on the
   character scale; the measurement validates that scale rather than replacing
   it. Acceptance criterion 4 of the issue ("all three budgets are recalibrated
   in the same change") is therefore declined on the evidence, not skipped —
   see below.

## Tests

Both new cases are in `test-context-budget.ps1`, and both branches were
executed:

- **JJ** — with tiktoken present, `--verify-tokenizer` against the **real**
  payload exits 0 and reports the ratio. This is a live regression gate on the
  calibration itself: if the payload's character mix ever drifts past 10%, the
  suite goes red. Without tiktoken it must exit 2.

  It deliberately does not use a synthetic fixture. Fixture text is a run of
  filler characters, which BPE collapses to a handful of tokens — a synthetic
  case here measures the fixture generator and fails an entirely correct
  divisor. It was written that way first and did exactly that.

- **KK** — the gate source carries no top-level `tiktoken` import. Asserting
  this on the source rather than by attempting an import is the only form that
  stays true on a host which happens to have the package installed.

Full suite: **56/56 passing**, verified twice — once with the tiktoken venv on
`PATH` (exercising JJ's positive branch) and once with a cleaned `PATH`
(exercising the blocked branch).

## Acceptance criteria

| # | Criterion | Status |
|---|---|---|
| 1 | Estimate invariant to line endings, punctuation, BOM | Already met (2026-08-07); cases S/T/U/V/W |
| 2 | The divisor is justified by measurement, not assertion | Met |
| 3 | Measured error band documented next to the budgets | Met (`af-env.conf`) |
| 4 | All three budgets recalibrated in the same change | **Declined on evidence** — the measurement shows the correction is under 3% and in the safe direction. The issue anticipated this outcome: *"Someone could reasonably close this as not worth the churn."* |
| 5 | The gate acquires no third-party runtime dependency | Met — lazy import, asserted by case KK |

## Known limitation

The calibration uses OpenAI tokenizers as a proxy. Claude's BPE is not
available through tiktoken, and the framework's payload is consumed by Claude.
The close agreement between `o200k_base` and `cl100k_base` suggests the ratio
is robust across BPE vocabularies for English markdown, but this is an
inference, not a measurement of the tokenizer that actually bills. Stated here
rather than buried, because a calibration whose caveat is hidden is worse than
an admitted rule of thumb.

## Follow-up

This change should precede [#107](https://github.com/sefalk/AgenticAIGovernance/issues/107)
(per-consumer budgets seeded at deploy time). #107 calibrates budgets on each
consumer's own payload; doing it first would have measured every consumer
against a ruler that was then swapped. The ruler is now fixed and documented,
so #107 can seed against a scale that will not move under it.
