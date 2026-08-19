<!-- copilot:generated | documenter | 2026-08-07 -->

# Fix: the context budget measured the disk, not the content (issue #59)

- **Status:** COMPLETED
- **Issue:** [#59](https://github.com/sefalk/AgenticAIGovernance/issues/59)
- **Branch:** `agent/59-context-budget-invariance`
- **Complexity tier:** Small
- **Date:** 2026-08-07

## Problem

`check-context-budget.py` estimated tokens as `path.stat().st_size // 4` —
bytes on disk, divided by four.

Bytes on disk move for reasons that leave the content the model reads
completely unchanged:

| Transformation | Effect on bytes | Effect on content |
|---|---|---|
| LF → CRLF | +1 per line (~87 tok on a 350-line file) | none |
| `-` → `—`, `->` → `→`, `>=` → `≥` | +2 per character | none |
| Editor adds a UTF-8 BOM | +3 | none |

`architecture.instructions.md` measured **1,966** by bytes and **1,617** by
characters — a 20% spread on one file. That spread was not theoretical: on
`dev` the conditional set measured 5,773 against a 5,500 budget, so the gate
reported a 273-token breach on a payload that measures 5,387 once the artefact
is removed. Nothing had been added.

A gate whose entire job is detecting real change must not react to changes that
are not real. This is the same family as the defects fixed under #64/#68/#69/
#70/#74/#73/#62/#78/#72 — a gate that produces an authoritative-looking verdict
it has no basis for.

The file already half-knew this: `_read_text` normalised CRLF before parsing
frontmatter, while `_tokens` measured the un-normalised bytes next to it.

## Change

1. **`_tokens` counts characters, not bytes.** It now reads through
   `_read_text`, which opens in text mode (universal newlines fold CRLF and
   lone CR to `\n`) with `utf-8-sig` (a leading BOM is dropped). The explicit
   `.replace("\r\n", "\n")` is gone — text mode already does it, and keeping a
   partial hand-rolled version of the same rule invites the two to diverge.
2. **A file that is not valid UTF-8 BLOCKS.** Counting characters means
   decoding, and decoding can fail. `UnicodeDecodeError` is not an `OSError`,
   so without this it would have escaped `main` and exited 1 — which the
   caller reads as *over budget*. A wrong verdict dressed as a real one is
   worse than no verdict; exit 2 says the result is unknown.
3. **`utf-8-sig` also fixes a latent bug in the budget reader.** A BOM on
   `af-env.conf` put `\ufeff` in front of the first key, so
   `^AF_CONTEXT_BUDGET_TOKENS=` never matched and the gate silently fell back
   to its default. A budget that quietly reverts to a default is not a budget.
4. **All three budgets re-derived on the new scale, in the same change.** A
   mixed-estimator state would be worse than either alone.

### Recalibration

Measured 2026-08-07:

| Set | Bytes scale | Character scale | Old budget | New budget | Headroom |
|---|---:|---:|---:|---:|---:|
| always-on | 4,895 | 4,865 | 5,000 | **4,950** | 1.7% |
| conditional | 5,773 | 5,387 | 5,500 | **5,500** | 2.1% |
| largest agent (coordinator) | 10,841 | 10,753 | 11,000 | **10,900** | 1.4% |

Rule applied uniformly: **the measured figure plus the headroom it previously
had, rounded down to the nearest 50.** Switching scale shrinks every total, so
leaving the budgets alone would have silently handed back slack the framework
never voted for. The conditional budget is the exception and is deliberately
*not* raised: it previously had negative headroom, so there was no ratio to
preserve, and raising it while the payload had just been shown to fit would
read as moving the goalposts.

`DEFAULT_CONTEXT_BUDGET` / `DEFAULT_AGENT_BUDGET` in the script — the fallback
used when `af-env.conf` is absent — were moved to the same figures. A default
that disagrees with the shipped config is a second, invisible budget.

## Deliberately not done

**The divisor is still 4, and still uncalibrated.** Issue #59 also asks for the
ratio to be measured against a real tokenizer (AC2), the error band documented
(AC3), and an optional `--verify-tokenizer` flag added. Per the scope
correction recorded on the issue, those drop in priority: this gate detects
drift in the framework's own definition files, it is not cost accounting, and
the budgets are calibrated against the estimator's own scale.

What was cheap and is done instead: `af-env.conf` and the script docstring now
say plainly what the number is not — the rule of thumb for English prose, a
drift scale, not a tokenizer-derived or billed count. **Issue #59 should stay
open** for the calibration part.

## Verification

| Suite | Before | After |
|---|---|---|
| `test-context-budget.ps1` | 31 checks, **1 failing** (`J_real_payload_within_budget` — dev is over its own conditional budget) | **39 checks, 0 failing** |
| `check-context-budget.py` on the real payload | exit 1 | exit 0 |

Eight cases were added:

| Case | Asserts |
|---|---|
| `S_crlf_matches_lf` | the same 2,000 characters measure the same as LF and as CRLF |
| `S_line_endings_counted_as_characters` | …and that the shared figure is 500, not merely equal |
| `T_typographic_punctuation_matches_ascii` | 400 × `—` measures as 400 × `-` |
| `T_punctuation_counted_as_characters` | …and that the shared figure is 100 |
| `U_bom_does_not_change_total` | a BOM is invisible |
| `U_bom_in_conf_still_read` | a BOM on `af-env.conf` does not swallow the budget |
| `V_added_text_still_counts` | invariance is not blindness — 400 more characters still move the number by 100 |
| `W_invalid_utf8_blocked` | undecodable input exits 2, not 1 |

`New-Fixture` gained `-RootBytes` and `-ConfBytes` so a case can write a fixture
byte-for-byte; the existing token-padding path writes ASCII, where bytes and
characters coincide, so no existing case changed meaning.

### Mutation testing

| Mutation | Failures |
|---|---|
| **A** — `_tokens` back to `st_size // 4` | 5 (`J`, `S_crlf`, `T_typographic`, `U_bom`, `W`) |
| **B** — `utf-8-sig` back to `utf-8` | 2 (`U_bom`, `U_bom_in_conf`) |
| **C** — `UnicodeDecodeError` allowed to escape | 1 (`W`) |

`U_bom_does_not_change_total` did not bind on the first attempt. The fixture was
2,001 characters, and integer division swallowed the difference: with the BOM
kept as a character the total was 2,002/4 = 500, identical to 2,001/4 = 500, so
the mutation changed nothing the case could see. The fixture is now 2,003
characters, where one extra character crosses a token boundary. Same lesson as
#72: *a case that passes under its own mutation is decoration.*

## Incidental

- The authoring checklist told the reader to run a Python script with `pwsh`.
- **Nothing runs this gate automatically.** Its only reference is a manual
  checklist item in `copilot-authoring.instructions.md`. That is why `dev`
  drifted 273 tokens over its conditional budget without anyone noticing —
  and it is the reason to expect it to happen again. Out of scope here; worth
  its own issue.
