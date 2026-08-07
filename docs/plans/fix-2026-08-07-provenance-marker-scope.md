<!-- copilot:generated | documenter | 2026-08-07 -->

# Fix: the provenance gate could not see the marker the instruction prescribes

**Issue:** [#81](https://github.com/sefalk/AgenticAIGovernance/issues/81)
**Branch:** `agent/81-provenance-marker-scope`
**Status:** COMPLETED
**Workflow:** L3_Bug_Fix

## The defect

`instructions/provenance.instructions.md` prescribes two placements for a
Python provenance marker:

| Case | Placement |
|---|---|
| New module | after the module docstring |
| Modified function | inside that function's docstring, under `Notes` |

Every gate that enforced the marker read the **first five lines of the file**:

| File | Mechanism |
|---|---|
| `hooks/scripts/implementer-stop.ps1` | `Get-Content -TotalCount 5` |
| `hooks/scripts/implementer-stop.sh` | `head -n 5` |
| `hooks/scripts/test-writer-stop.ps1` | `Get-Content -TotalCount 5` |
| `hooks/scripts/test-writer-stop.sh` | `head -5` |
| `hooks/scripts/scan-secrets.ps1` | `Get-Content -TotalCount 5` (advisory) |
| `hooks/scripts/scan-secrets.sh` | `head -n 5` (advisory) |
| `agents/compliance-checker.agent.md` | "Read first 5 lines" (two rows) |

For a module docstring of four lines or more the two rules cannot both be
satisfied. For the function-level placement they can *never* both be
satisfied — no fixed window at the top of a file reaches into a function
body. The block message named `instructions/provenance.instructions.md` as
the authority while rejecting exactly what that document prescribes, so the
agent's only way out was to violate the convention it was being pointed at.

Downstream evidence: MPUsageXPTP work item **WIT #3119** carried the
acceptance criterion "provenance marker relocated per the project
convention" — unsatisfiable while the hook stood.

This is the same family as #64, #69, #70, #72, #78 and #85: a gate whose
answer is not about the thing it claims to judge.

## The fix

One shared detector, six call sites.

- `_common.ps1` → `Test-AfProvenanceMarker -Path <path> [-Kind any|generated]`
- `_common.sh` → `af_has_provenance_marker <path> [any|generated]`

It scans the **whole file** for `copilot:(generated|modified)`. `-Kind
generated` narrows the accepted kinds to `copilot:generated`, because
test-writer's gate is about authorship of a *new* file and `copilot:modified`
must not satisfy it. A missing or unreadable path is reported unmarked, never
an error.

### What the fix deliberately does not do

**It does not judge where the marker sits.** A marker's job is to be found.
Prescribing its position is the instruction's job and checking that position
is a reviewer's. A boolean gate answering "is this file attributed?" should
not silently also be answering "is it attributed in the spot I expected?" —
those are different questions and only the first has a defensible automatic
answer.

**It does not tighten what counts as a marker.** The obvious adjacent
improvement is to require the full `copilot:kind | agent | YYYY-MM-DD`
triple. That is a behaviour change: it would newly block work in consumer
projects whose existing markers are sloppier than the format, in a commit
whose stated purpose is to *unblock*. Widening where we look must not quietly
narrow what passes. Left as a possible follow-up.

**It does not change `provenance.instructions.md`.** The issue's acceptance
criteria allowed either satisfying the `Python — modified function`
placement or removing it from the instruction. The whole-file scan satisfies
it, so the instruction stands unchanged.

## Tests

Red first, in both suites.

**Behaviour (7 PowerShell / 7 bash):** four fixtures — marker on line 1,
marker after a six-line module docstring, marker inside a function
docstring's `Notes` section, no marker at all — plus a path that does not
exist, and two `generated`-kind cases proving `copilot:modified` alone still
does not satisfy a new-file gate.

The gates themselves could not be exercised end to end: `implementer-stop`
and `test-writer-stop` run the project's whole test suite before reaching the
provenance gate, and this host has no `pytest` on `PATH`, so a fixture-based
case would silently skip. A case that silently skips is worse than no case at
all — the failure mode this whole issue family is about. The detector is
therefore probed directly, and bound to the gates by static assertions.

**Call sites (13 PowerShell / 6 bash):** each of the six scripts must
reference the shared detector, and must no longer contain a fixed
five-line window (`TotalCount 5`, `head -n 5`, `first 5 lines`); plus
`compliance-checker.agent.md` must no longer describe a five-line window.
Without these, the detector is a helper nobody calls — the failure mode of
issue #69.

### Two vacuous passes found and removed during Red

Both worth recording, because both are the bug under test wearing a
different hat:

1. **A missing detector looked like a `False` verdict.** With
   `Test-AfProvenanceMarker` undefined, PowerShell wrote a non-terminating
   error and left `$v` as `$null`; `[bool]$null` is `False`, so
   "a path that does not exist is unmarked" passed *without a detector
   existing*. In bash the same thing happened via a non-zero exit from a
   missing function. Both probes now emit `MISSING-DETECTOR`.
2. **The probe received one argument, not a list.** `powershell -File`
   passes every argument as a single string, so `-Paths ($paths -join ',')`
   arrived as one element and `Split-Path -Leaf` reported only the last
   path. Caught at Green: six behaviour cases failed with
   `got: does-not-exist.py=False`. The probe now splits the list itself.

### Results

| Suite | Before | Red | Green |
|---|---|---|---|
| `test-hooks.ps1` | 162 / 0 | 162 / 20 | **182 / 0** |
| `test-hooks.sh` | 69 / 0 | 69 / 13 | **82 / 0** |

`bash -n` clean on all four changed shell scripts. Context budget PASS
(always-on 4,865/4,950; conditional 5,387/5,500; largest agent 10,753/10,900).

### Mutation checks

| Mutation | Expected | Observed |
|---|---|---|
| Detector reads only the first 5 lines again | the instructed placements fail | **3 red** — long-docstring, in-function, and the generated-kind long-docstring case |
| `-Kind` ignored (always `any`) | the generated-only case fails | **1 red** — `copilot:modified` alone would satisfy a new-file gate |
| `implementer-stop.sh` reverted to `head -n 5` | its two static cases fail | **2 red** — "asks the shared detector", "no fixed window" |

Note that mutation 1 leaves the line-1 case green. A detector that only ever
saw the top of the file would still have passed the one placement nobody
actually uses — which is precisely why the defect survived this long.

## Follow-up

- Require the full `kind | agent | date` triple — deliberately out of scope
  here, see above.
- Issue #86 touches the same six call sites (gates scoped to authored change
  rather than the whole diff) and is scheduled next, so the sites are opened
  once more rather than a third time.
