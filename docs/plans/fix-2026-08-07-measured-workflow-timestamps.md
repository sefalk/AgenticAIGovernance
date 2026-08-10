<!-- copilot:generated | documenter | 2026-08-07 -->

# Implementation Plan — Workflow-log timestamps are measured, not authored

**Workflow:** Bug Fix
**Issue:** [#91](https://github.com/sefalk/AgenticAIGovernance/issues/91)
**Branch:** `agent/91-measured-workflow-timestamps`
**Base:** `dev` @ `661922b`
**Status:** COMPLETED
**Complexity tier:** Standard

## The defect

The workflow log is the only durable record of when a workflow ran, and its
`started:` and `completed:` fields were filled in by the documenter. In
workflow `3121-ruff-format-repo-wide` it wrote `completed: "2026-08-07T16:30:00Z"`
for a workflow that finished at 09:59Z — six and a half hours in the future —
and a `started:` an hour before the branch's first commit. The same output
declared "zero fabricated data".

Nothing rejected it. Every gate that reads the log — `documenter-stop`, the
compliance-checker post-flight — checks that the field is *present*, and an
invented value is present. Presence was the whole test, so a plausible wrong
number scored exactly as well as a measurement.

## Why validation was the wrong fix

The issue offered two paths: compute the values in the hook, or validate what
the model wrote (block a future `completed:`, block `started: > completed:`).

Validation would have caught this particular timestamp and accepted every lie
inside the range. It also leaves the field's authorship where the problem is:
a model asked for a number it does not have will produce a plausible one, and
plausible is precisely what a range check cannot distinguish from correct.

The `cost:` block had already settled this shape for the same file — measured
by the hook, and the documenter explicitly told never to estimate or transcribe
it. The timestamps now follow that precedent. This is the same argument that
resolved #87: remove the capability rather than warn against using it.

## The fix

**Stamped by `documenter-stop`, after the artifact gate passes.**

- `completed:` is the moment the hook fires. The hook fires when the documenter
  finishes, so no derivation is needed — it is a direct observation.
- `started:` is the branch's oldest commit
  (`git log --format=%cI {BASE_BRANCH}..HEAD | tail -1`), the same
  approximation the cost collector already uses for `--workflow-start`.
- Anything the documenter left behind is **replaced, not joined**. Two
  `completed:` keys is a YAML file whose meaning depends on which one the
  parser reaches last.
- Only top-level keys are touched. A `started:` indented inside a step entry
  belongs to that step.
- A call made while the workflow is still running is not stamped at all — it
  never reaches the artifact gate (issue #72 lifecycle split).
- The block degrades silently on any error, like the cost block: a timestamp is
  not worth failing a workflow over.

**Removed from the schema in `documenter.agent.md`.** Leaving the fields in the
schema and arguing against them in prose elsewhere is how the fabrication
happened in the first place — the schema is the instruction. In their place,
the same sentence the cost block gets: *do not write these, your Stop hook
stamps them.*

**Point 3 of the issue** — dropping the "zero fabricated data" self-declaration
— had nothing to remove: the phrase is not in the framework text, the model
produced it unprompted. What the constraint list can say is that asserting your
own accuracy is not a substitute for a value someone measured, and it now does.

## Verification

| Suite | Before | Red | Green |
|---|---|---|---|
| `test-hooks.ps1` | 205 / 0 | 208 / 5 | 213 / 0 |
| `test-hooks.sh` | 100 / 0 | — | 106 / 0 |

`check-context-budget.py` PASS (always-on 4,865/4,950; conditional
5,387/5,500) and `validate-skills.py` PASS (61 skills) after the change.

The harness gained a read-back: `Invoke-Hook -ReadBack <relpath>` returns the
file as the hook left it, and `stamp_log` does the same in bash. A hook that
writes into the repository cannot be judged by its verdict — the fixture is
deleted on the way out, so the assertion has to read the file before then.

### A PowerShell trap worth recording

The first read-back always came back empty although the parameter provably
arrived — printing it at function entry showed the right value. The local was
named `$readBack` and the parameter `$ReadBack`; PowerShell variable names are
case-insensitive, so `$readBack = $null` wiped the parameter and the following
`if ($ReadBack)` was false. Never differentiate a local from a parameter by
casing alone.

### A second PowerShell trap

The mutation harness reported *anchor not found* for a source line it provably
contained: `-like` treats the backtick as its escape character, so an anchor
holding PowerShell's own `` `" `` escape stops matching itself. `.Contains()`
is the right operator for a literal anchor.

## Mutations

Each mutation was applied to the green tree, the PowerShell suite run, and the
tree restored. All four were killed.

| Mutation | Result |
|---|---|
| Append the stamps instead of replacing the documenter's | 211 / 2 — invented value survives; each-key-once fails |
| Let a mid-workflow call fall through to the stamping block | 209 / 4 — mid-workflow log is stamped as finished |
| Restore `started:`/`completed:` in the agent's log schema | 212 / 1 — schema assertion fails |
| Stamp `completed:` only, forget where the workflow began | 210 / 3 — `started:` missing, bare log half-stamped |

## What this does not do

- It does not date a workflow whose branch has no commits — `started:` then
  equals `completed:`. That is honest rather than precise: with nothing
  committed there is no observation to make, and inventing one is the defect.
- It does not validate timestamps written by anything other than the
  documenter. Nothing else writes them, and a validation layer over a field no
  model authors is machinery guarding an empty room.
