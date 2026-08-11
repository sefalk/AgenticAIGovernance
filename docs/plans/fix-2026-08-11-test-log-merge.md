<!-- copilot:generated | planner | 2026-08-11 -->

# Fix: the test log merges, and a log it cannot read is not silently replaced

- **Issue:** [#93](https://github.com/sefalk/AgenticAIGovernance/issues/93)
- **Branch:** `agent/93-test-log-merge-ps51`
- **Base:** `dev` @ `211034c`
- **Complexity tier:** Standard
- **Status:** COMPLETED

## Problem

`run-tests.ps1` reads `.github/test-log.json` with
`ConvertFrom-Json -AsHashtable`. That parameter exists only in PowerShell 6+.
Windows PowerShell 5.1 is the default host for the shipped VS Code tasks, so on
Windows the read *always* throws, the `catch` resets the accumulator to `@{}`,
and the script writes a log containing only the scope that just ran.

Measured in the consumer repo: a `domain` entry present before an
`-Scope adapters` run, absent after it. Exit code 0, no warning.

The lost merge is the symptom. The defect is the `catch`: it converts a hard,
diagnosable interpreter incompatibility into a plausible-looking artifact. Same
class as #73 in the same file — *the artifact looks authoritative and is wrong*
— and the same class as everything else this session: a mechanism that fails
silently and reads as consent.

Why it bites agents specifically: `testing.instructions.md` rule 5 tells every
agent to consult `test-log.json` before running anything, and several
acceptance criteria are phrased as "green afterwards at the same pass count as
before". An agent establishing that baseline finds the other scope absent — or
a stale single entry it compares against the wrong scope. Neither raises an
error.

## Investigation

### The bash runner already merges

`run-tests.sh` extracts the six known scopes with `sed` and re-emits all of
them. So this is a *divergence* between two runners that are supposed to be
interchangeable, not a missing feature. The regression test must therefore
assert the merge property against **both** runners, or the next drift is
invisible again.

### `-AsHashtable` is the only PS6-only construct in the payload

A scan of every shipped `.ps1` for PowerShell 6+ constructs (`-AsHashtable`,
`-Parallel`, `-AsByteStream`, `Test-Json`, `??`, `$IsWindows`, `Join-String`)
returns exactly one hit: the line in question. So the fix is a single edit —
but the *class* recurs, and nothing prevents the next one.

### Why the existing suite never caught it

`test-run-tests.ps1` case G runs one scope and asserts that scope's entry is
correct. That passes whether or not the merge works. As the issue says: a test
that only checks the scope just run "never observes the bug". The property has
to be stated across two runs.

## Approach

**A. Read without `-AsHashtable`.** Parse normally and copy the properties into
the hashtable. No version branch — the code should not care which host runs it.

**B. Make the reset audible, and only when it is a reset.** A missing file is
legitimately empty: no warning. A file that exists and cannot be parsed is data
loss: warn with the path and the parser's own message.

**C. Do not destroy the evidence.** An unreadable log is currently overwritten,
which removes the only artifact that could explain what happened. Copy it to
`test-log.json.unreadable` before writing. This is the #87 principle applied
one file over: never overwrite an existing, non-empty artifact without leaving
a trace.

**D. A standing guard for the class.** Assert that no shipped `.ps1` uses a
PowerShell 6+ only construct. The suite runs on 5.1; a static check is what
turns "we happened to notice" into "the next one fails a test".

## Subtasks

| # | Task | Acceptance criteria |
|---|---|---|
| 1 | Red: cross-run merge cases for both runners, unreadable-log cases, PS6-construct guard | New cases fail; existing 12 unchanged |
| 2 | Green: rewrite the read block in `run-tests.ps1` (A + B + C) | `test-run-tests.ps1` green at the higher count |
| 3 | Docs: CHANGELOG, plan | Entry names the measured symptom and the silent `catch` |

## Risks

| Risk | Mitigation |
|---|---|
| The merged log mixes hashtable and `PSCustomObject` values; `ConvertTo-Json -Depth 3` may render them differently | The round-trip is asserted by the merge test itself: read back both scopes after two runs |
| A warning on every legitimately absent log would be noise | Test both branches separately: absent = silent, unreadable = loud |
| The PS6-construct guard produces false positives on substrings in comments | Anchor on the parameter/operator form and keep the list short; a false positive is a failing test, so it surfaces immediately |

## Mutations to attempt

1. Restore `-AsHashtable` → the merge cases must go red on 5.1.
2. Drop the warning from the `catch` → the unreadable-log case goes red.
3. Skip the backup copy → the evidence case goes red.
4. Break the bash merge (drop one `sed` line) → the bash merge case goes red.
5. Empty the PS6 denylist → the guard case goes red.

## Results

`test-run-tests.ps1`: **12/12 → 14/19 (Red) → 19/19 (Green)**. `test-hooks.ps1`
unchanged at 233/0.

The Red run reproduced #93 in this repository rather than arguing from the
source: after a `-Scope domain` run followed by a `-Scope contracts` run in the
same fixture, the log held `scopes=[contracts]` alone. H2 showed the same thing
from the other side — a hand-seeded `properties` entry written by
`run-tests.sh` did not survive a single PowerShell run.

`I_sh_runner_keeps_foreign_scope` passed at Red. That is the finding worth
keeping: the bash runner already merged, so this was never a missing feature.
It was two runners documented as interchangeable disagreeing about what the
artifact means, with nothing asserting that they agree.

### Mutation ledger

| # | Mutation | Result |
|---|---|---|
| M1 | Restore `-AsHashtable` | 16/19 — H1, H2, K red |
| M2 | Drop the sentence naming the consequence from the warning | 18/19 — J1 red |
| M3 | Skip the backup copy | 18/19 — J2 red |
| M4 | Break the bash merge (drop the `domain` `sed` read) | 18/19 — I red |
| M5 | Inject `$IsWindows` into a shipped script | 18/19 — K red |

Five mutants, five killed, each by exactly the case that claims the property
and by no others. M1 is the only one that turns three cases red, and correctly
so: restoring the parameter is both the merge defect and a PS6-only construct.

## Notes

**Mutation 5 as planned would have proved nothing.** The plan said "empty the
PS6 denylist → the guard case goes red". Emptying the denylist does not make `K`
fail; it makes `K` *pass on nothing* — the precise anti-pattern this repository
added to `testing.instructions.md` and the code-review skill one commit
earlier, met while writing the very next test. The mutation has to go on the
product side: inject `$IsWindows` into a shipped script and watch the guard
catch it. Written down because the mistake is structural, not careless — a
guard's denylist *looks* like the thing under test, and it is not.

**The guard's first true positive was its own explanation.** `K` failed in
Green on the comment in `run-tests.ps1` saying why `-AsHashtable` is not used.
A guard that punishes documenting an absence will have that documentation
deleted to make it green. The scanner now strips block comments and whole-line
comments first. Trailing comments still count, deliberately: cutting at the
first `#` on a code line would let a `#` inside a string literal hide a real
construct, and a false negative in a guard is worse than a rule that says put
the note on its own line.

**No version branch.** The obvious fix is `if ($PSVersionTable.PSVersion.Major
-ge 6) { … } else { … }`. Rejected: it doubles the paths through the only code
that decides what the log means, and the 5.1 path is the one that would stay
untested on a maintainer's PS7 machine. The version-independent read is the
same length and has one behaviour.

**The absent/unreadable distinction is the whole point of B.** A missing log is
a legitimate first run and must stay silent, or the warning becomes noise and
noise is ignored. A log that exists and will not parse is data loss and must be
loud. J3 exists to keep the fix from over-correcting into the failure mode it
replaces.

**Standing debt:** MPUsageXPTP has not pulled the #73 fix and its `.github/`
payload is weeks stale. This fix needs to reach it too — it is the repository
where the symptom was measured.
