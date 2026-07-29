---
title: "Talk artefacts — synthetic evidence blocks"
type: presentation-assets
description: Ready-to-use synthetic artefacts for the AAIG talk. Realistic in structure, neutral in content. Companion to talk-2026-07-29-agentic-ai-governance.md.
tags: [aaig, presentation, artefacts, synthetic]
updated: 2026-07-29
status: DRAFT — text ready, GIF not yet recorded
---

# Talk artefacts — synthetic evidence blocks

Companion to
[talk-2026-07-29-agentic-ai-governance.md](talk-2026-07-29-agentic-ai-governance.md).
Numbering matches §6 of that document.

> **All content on this page is synthetic.** No project, customer, dataset or
> repository path is real. The *structure* mirrors the framework's actual hook
> and agent output formats, so anyone who later encounters the real thing will
> recognise it — but nothing here discloses anything.
>
> Running domain for all examples: a generic **order and refund service**.
> Neutral, instantly understandable in any industry, and it makes the
> requirement in artefact 1 self-explanatory without a setup slide.

---

## Artefact 1 — Red-phase block · GIF · section D.1, stop 1

**The moment:** the test-writer returns a test that *passes*, and the handoff is
refused before the implementer ever sees it.

**Why this one is the GIF:** the audience watches a **green** test suite being
**rejected**. That is visually counter-intuitive, so it sticks — and it makes
the "inverted condition" argument without a single word of explanation.

### Storyboard (5 frames, ~16 s)

| Frame | ~s | Content |
|---|---|---|
| 1 | 0–3 | Coordinator dispatches the test-writer with the requirement |
| 2 | 3–7 | The test file that comes back |
| 3 | 7–10 | Test run: **1 passed** |
| 4 | 10–14 | Hook output: **blocked** |
| 5 | 14–16 | Coordinator: handoff refused, retry — hold this frame |

### Frame 1 — the dispatch

```text
coordinator → test-writer
─────────────────────────────────────────────────────────────────
Task     : REQ-114 — partial refund window
Phase    : RED
Contract : Orders returned between 30 and 60 days after delivery
           receive a 50% refund. Outside that window the current
           behaviour is unchanged.
Exit gate: new tests MUST fail against current production code.
```

### Frame 2 — what comes back

```python
# tests/domain/test_refund_policy.py
# copilot:generated | test-writer | 2026-08-10

def test_refund_after_return_window() -> None:
    order = Order(total=100.00, days_since_delivery=45)
    assert refund_amount(order) == 0.00
```

> **The subtlety worth naming out loud.** The test is not nonsense. It is
> well-formed, readable, correctly typed and properly marked. It simply asserts
> what the code *already does* instead of what the requirement *asks for* — the
> single most common way a Red phase quietly fails. Nothing in the diff looks
> wrong.

### Frame 3 — the run

```text
$ pytest tests/ -q --tb=line --no-header

tests/domain/test_refund_policy.py .                              [100%]

1 passed in 0.31s
```

### Frame 4 — the hook

Raw hook output (this is what the runtime actually emits):

```json
{
  "hookSpecificOutput": {
    "hookEventName": "Stop",
    "decision": "block",
    "reason": "Red phase violation: all tests PASS. New tests must FAIL against the existing production code to express a genuine requirement gap. Ensure your tests assert behaviour that is not yet implemented."
  }
}
```

> Show the raw JSON, not a prettified paraphrase. It is the strongest single
> piece of evidence in the talk: **`"decision": "block"` is a machine
> instruction, not advice.** No model decided this. No model was asked.

### Frame 5 — the consequence

```text
test-writer:Stop  ✖  BLOCKED — Red gate

  Handoff to implementer refused.
  Returning to test-writer with the block reason. Attempt 2 of 2.

  Note: the implementer was never invoked.
```

### What to say while it is on screen

> The suite is green. In CI, that is a pass. Here it is a violation — because at
> this point in the process the test is supposed to fail. And notice *where* it
> stops: not at the commit, at the **handoff**. The implementer never saw this
> test, so nothing got built on top of an assertion that never proved anything.

---

## Artefact 2 — the maker's self-report · still · section D.1, stop 2

**The moment:** the implementer finishes and reports its own gates as fully
passed.

```text
### Gate Summary
- **Tier:** Standard
- **HARD gates:** 7/7 passed
- **SOFT gates:** 3 evaluated (reviewer decides)
- **ADVISORY:** cyclomatic_complexity_max = 6
- **BLOCKED gates:** none
- **Failed HARD gates:** none
- **Skills Read:** unit-testing, error-handling
```

> Say: "This is the agent's own account of its own work. It is structured, it is
> complete, it is plausible — and on its own it is worth nothing. Not because
> the agent is lying, but because a self-check is the same judgement applied
> twice."

---

## Artefact 3 — the checker's verdict · still · section D.1, stop 2

**The moment:** a *different* agent re-measures and rejects.

```text
## Code Review Verdict: REJECTED

### Gate 1 — Auto-check
  syntax / imports .................... PASS
  test suite (48 passed, 0 failed) .... PASS
  lint ................................ PASS

### Gate 2 — Metrics (re-measured, not taken from the report)
  coverage · domain ................... 84.2%   threshold ≥ 90%   FAIL
  coverage · adapters ................. 71.0%   threshold ≥ 60%   pass
  complexity · max .................... 6       threshold ≤ 10    pass

### Finding
  The maker's summary reported "7/7 HARD passed". The coverage gate was
  measured across the whole package, not per architectural layer. Measured
  per layer, the domain core is 5.8 points below its threshold:
  refund_policy.py lines 41-58 (the 30-60 day branch) are uncovered.

### Required before re-submission
  1. Cover the 30-60 day branch, including both boundaries (30 and 60).
  2. Re-run coverage scoped to the domain layer.

Returning to implementer. Attempt 2 of 2.
```

### What to say while it is on screen

> The maker was not dishonest — it measured the wrong scope. That is exactly the
> class of error self-review cannot catch, because the same reasoning that
> produced the mistake also produces the self-assessment. So the rule in the
> framework is blunt: **an agent's check of its own structural output is never a
> binding gate.** It has to be a different actor. CI can tell you *what* was
> produced; it has no concept of *who* signed it off.

---

## Artefact 4 — pre-action denial · still · section D.1, stop 3

**The moment:** a forbidden operation is refused *before* it executes.

```text
block-dangerous  ✖  DENIED

  Requested : git push --force origin main
  Classified: destructive-remote-rewrite  +  protected-branch-target
  Policy    : hard-deny (not overridable by the agent)

  Rationale : force push rewrites published history; 'main' is protected.
              Integration into protected branches is request-based and
              human-completed. See git-workflow.instructions.md.

  Action    : not executed.
```

### What to say while it is on screen

> This is the difference between prevention and detection. Branch protection
> would also have rejected this push — *after* it left the machine, and after
> the local history was already rewritten. Here the command never ran. Both
> controls are worth having; they are not the same control.

---

## Artefact 5 — the record the run leaves behind · still · section D.1 wrap-up

```yaml
workflow_id: feat-refund-window
tier: Standard
started:  2026-08-10T09:14:22Z
finished: 2026-08-10T10:02:47Z

steps:
  - agent: planner
    verdict: APPROVED
    artefacts: [docs/plans/feat-2026-08-10-refund-window.md]
  - agent: test-writer
    verdict: BLOCKED           # Red gate — tests passed
    attempts: 2
    blocked_by: test-writer:Stop
  - agent: test-critic
    verdict: APPROVED
  - agent: implementer
    verdict: REJECTED          # coverage, domain layer
    attempts: 2
  - agent: code-critic
    verdict: APPROVED
  - agent: refactorer
    verdict: APPROVED

gates:
  hard_total: 19
  hard_failed_then_fixed: 2
  soft_evaluated: 8
  escalations_to_human: 0

provenance:
  files_marked: 3
  unmarked_files: 0
```

### What to say while it is on screen

> Two gates failed during this run and both were fixed before anything was
> handed on. That is the part that matters: not that the run was clean, but that
> the two failures are **in the record**. A diff would never have told you they
> happened.

---

## Artefact 6 — provenance marker · inline snippet · section D.1 wrap-up

```python
"""Refund policy — return-window rules."""
# copilot:generated | implementer | 2026-08-10
```

```python
def refund_amount(order: Order) -> Decimal:
    """Return the refundable amount for an order.

    Notes
    -----
    copilot:modified | implementer | 2026-08-10 | added 30-60 day partial band
    """
```

> One line. Machine-parseable. It answers *which code was AI-generated, by which
> role, when* — which is precisely the question the transparency debate is
> converging on. Pair this with the Article 50 point in section E.

---

## Artefact 7 — non-destructive update · still · section D.2

**The moment:** the framework is updated inside a running project and the
project's own customisations survive.

```text
$ framework update --dry-run

  UNCHANGED    41 files
  UPDATE        6 files   generic definitions, no local edits
  CREATE        2 files   new capability
  PRESERVE      3 files   marked customisable, locally edited
  DEACTIVATED   9 files   curated out of this project — not re-created
  CONFLICT      1 file    local edits AND upstream changes

  CONFLICT  config/quality-thresholds
            local  : domain coverage threshold 95  (raised by the project)
            upstream: adds a new mutation-score gate
            → merge required. Nothing will be overwritten.

  0 files written. Re-run without --dry-run to apply.
```

### What to say while it is on screen

> Nine files are deactivated because this project curated them away — and the
> update does **not** bring them back. That is the difference between a
> framework and a template: the project's decisions are treated as decisions,
> not as drift to be corrected. And the one genuine conflict is surfaced for a
> human rather than silently resolved in either direction.

---

## Production notes

- **Legibility beats completeness.** At presentation size, roughly 12 lines and
  70 columns is the practical ceiling for a code block. Trim rather than shrink;
  every block above is already within that budget except artefact 5, which
  should be cropped to the `steps:` section if the room is large.
- **Colour only where it carries meaning.** Green for the passing suite in
  artefact 1 frame 3, red for `block` / `DENIED` / `REJECTED`. Nothing else.
- **Keep the raw JSON raw.** Artefact 1 frame 4 loses its force if it is
  reformatted into prose. The whole point is that it is machine output.
- **Consistent dates.** Every artefact is stamped `2026-08-10` — the talk date.
  Cheap detail, but a mismatched timestamp is the kind of thing a sceptic in the
  front row notices.
- **Fallback frame.** Export artefact 1 frame 4 as a standalone still. If the
  GIF fails to play, that single frame carries the argument on its own.
