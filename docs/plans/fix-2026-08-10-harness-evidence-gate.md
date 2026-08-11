<!-- copilot:generated | planner | 2026-08-10 -->

# Fix: the harness must not certify what it never observed

- **Issues:** [#95](https://github.com/sefalk/AgenticAIGovernance/issues/95),
  [#96](https://github.com/sefalk/AgenticAIGovernance/issues/96)
- **Branch:** `agent/95-96-harness-evidence-gate`
- **Base:** `dev` @ `7b6130b`
- **Complexity tier:** Standard
- **Status:** COMPLETED

## Problem

Both issues describe the same property from two directions, and both concern
the instrument rather than the thing measured.

- **#95** — the harness reads a hook's decision by looking for the expected
  answer in its output. A hook that emits a correct decision *and then a
  contradictory one* is certified as correct.
- **#96** — a negative content assertion (`$stamped -notmatch '2099'`) passes
  when `$stamped` is `$null`. The read-back channel added in #91 has no
  self-check, so an empty read-back is indistinguishable from a good file.

The common property: **a verdict requires a subject, and exactly one
statement about it.** Where either is missing the harness currently returns
the most agreeable answer available.

This matters more than an ordinary defect because every quality claim this
framework makes is read through these two files. `test-hooks.ps1` opens with
a self-check whose entire premise is this failure mode — and that self-check
covers the decision channel only.

## Investigation

Both issues state their mechanism as *inferred, not executed*. #95 asks
explicitly for confirmation with a deliberate two-object fixture. Measuring
first changed the conclusion.

### #95: the stated mechanism does not reproduce in PowerShell

The issue predicts that `ConvertFrom-Json` turns two concatenated objects into
a collection whose first element answers `$p.hookSpecificOutput.decision`.
Measured on the host that runs the suite (`5.1.26100.8875`):

```
--- Stop shape: two objects ---
THREW: Invalid JSON primitive: "systemMessage":"artifact gate PASS"}.
--- PreToolUse shape: two objects ---
THREW: Invalid JSON primitive: "hookSpecificOutput":{"permissionDecision":"allow"}}.
--- object followed by plain text ---
THREW: Invalid JSON primitive: ARNING: something.
```

`Resolve-Decision` catches that and returns `error`; `Get-StopDecision`
returns `"unparsable: …"`. Both are red. **The PowerShell harness already
rejects the two-object hook — but by accident of the parser, not by design.**
Nothing pins the property, the failure message names the wrong cause
(`unparsable` rather than *the hook made two statements*), and a stricter or
more lenient parser in any future host silently changes the answer.

### #95: the defect is real, in the other harness

`test-hooks.sh` matches by substring:

```sh
block) [[ "$out" == *'"block"'* ]] && ok=1 ;;
deny)  [[ "$out" == *'"deny"'*  ]] && ok=1 ;;
```

Measured against a block-then-pass emitter:

```
--- stop_case expect=block against a block+pass emitter ---
MATCH -> harness reports PASS
--- run_case expect=deny against a deny+allow emitter ---
MATCH -> harness reports PASS
--- run_case expect=silent against {} + a deny ---
no match -> red
```

So the exact scenario that prompted the issue — `documenter-stop` losing its
`exit 0` and printing a block followed by `artifact gate PASS` — is certified
as a correct block by the bash harness. `silent` escapes only because it
happens to compare for equality rather than containment.

### #96: reproduces exactly, in both harnesses

```
null_notmatch_2099=True
empty_notmatch_2099=True
```

and in bash, reading a file that does not exist:

```
--- vacuous negative: empty subject, absent file ---
no 2099 in an empty string -> harness reports PASS
```

`Assert-True` receives `[bool]$Condition` — the evidence is collapsed to a
boolean *before* the harness sees it. By then `$null -notmatch '2099'` is
indistinguishable from a genuine pass. **No guard inside `Assert-True` can
recover what it was never given**, which decides the shape of the fix.

## Approach

One property, enforced in the two places a verdict is formed.

### A. Exactly one statement per invocation (#95)

Count top-level JSON values in the hook's output and treat anything other than
one as its own outcome, distinct from a parse error. Counting rather than
relying on the parser's exception is the point: it makes the property explicit
and host-independent.

- **PowerShell:** a scanner shared by `Resolve-Decision` and `Get-StopDecision`
  — the two places that turn output into a verdict. New decision value
  `multi` so the failure says what happened.
- **bash:** the harness already requires a working interpreter (`$af_py`), so
  the count is delegated to it rather than to a brace-counting loop in shell.
  `run_case` and `stop_case` fail before their substring match when the count
  is not one.

A top-level JSON **array** stays one value. Empty output stays `silent`; that
is an existing, deliberate outcome and is not this issue's subject.

### B. No verdict without a subject (#96)

- `Assert-Contains` / `Assert-NotContains` take the **subject and the pattern
  separately** and fail when the subject is null, empty or whitespace. This is
  the primary fix: the harness evaluates the match itself, so the evidence can
  no longer arrive pre-collapsed.
- `Assert-True` gains an optional `-Subject` for genuinely compound conditions
  (regex counts, conjunctions), with the same empty-subject rule.
- The `#91` timestamp assertions and the `stop-tests` output assertions move
  onto them — those are the call sites the issue names.
- Same pair in bash: `assert_contains` / `assert_not_contains`.

### C. The self-check covers the read-back channel

Seeded content comes back; an absent path comes back as `$null`; the two are
distinguishable by assertion. Plus the negative case the issue asks for: an
assertion against an empty subject must **fail**.

Testing that an assertion fails without failing the suite needs the counters
snapshotted and restored around the probe. That is the honest way to test a
test harness, and it is what makes AC "a negative content assertion against an
empty subject fails" mechanically checkable rather than a claim.

## Subtasks

| # | Task | Acceptance criteria |
|---|---|---|
| 1 | Red: statement-count cases, read-back self-check, vacuous-subject cases, in both harnesses | New cases fail for the stated reason; existing counts unchanged |
| 2 | Green (PS): shared statement scanner, `multi` outcome, `Assert-Contains`/`-NotContains`, `Assert-True -Subject`, converted call sites | `test-hooks.ps1` green at the new higher count |
| 3 | Green (bash): `af_json_statements`, guards in `run_case`/`stop_case`, `assert_contains`/`assert_not_contains`, converted call sites | `test-hooks.sh` green at the new higher count |
| 4 | Docs: CHANGELOG, plan, and the harness header comment that states the property | Header names both channels, not just the verdict one |

## Risks

| Risk | Mitigation |
|---|---|
| Enforcing one statement breaks cases where a hook legitimately prints diagnostics beside its JSON | Measure first: run the full suite after the guard and inspect every new failure rather than relaxing the rule |
| bash suite takes ~15 min per full run | Use the PS suite for iteration; run bash fully once before the docs commit |
| An empty-subject rule turns legitimate "the hook printed nothing" cases red | Those are `silent`/exit-code assertions, which do not go through the content helpers |

## Mutations to attempt

1. Read-back returns `$null` unconditionally → the #91 timestamp assertions must go red, **including the `-notmatch` one** (AC of #96).
2. Statement scanner always reports 1 → the two-object cases go red.
3. `Assert-NotContains` drops its empty-subject guard → the vacuous case goes red.
4. bash `stop_case` loses the count guard → the block-then-pass case goes red.
5. A top-level array counted as N → the array case goes red.

## Results

| Suite | Baseline | Red | Green |
|---|---|---|---|
| `test-hooks.ps1` | 213 / 0 | 218 / 14 | **233 / 0** |
| `test-hooks.sh` | 106 / 0 | 106 / 12 | **120 / 0** |

The bash Red run is the substantive finding: `run_case said: pass` for a
deny-then-allow emitter and `stop_case said: pass` for a block-then-pass one,
both produced by the real harness functions against stub hooks.

### Mutations

| # | Mutation | Red cases |
|---|---|---|
| M1 | read-back returns `$null` unconditionally | 9 — including `a completed: the documenter invented does not survive the hook`, the `-notmatch` assertion named in #96 |
| M2 | statement counter always reports 1 | 4 |
| M3 | `Test-SubjectPresent` always true | 4 |
| M4 | `Assert-True` ignores `-Subject` | 1 |
| M5 | `[` no longer opens a value (array not counted as one) | 1 |
| M6 | `Resolve-StopDecision` skips the count | 1 |
| M7 | `Resolve-Decision` skips the count | 2 |
| B1 | `af_json_statements` always reports 1 | 4 — including both end-to-end cases: `a hook that denies and then allows is not certified as denying` and the Stop-hook pendant |
| B2 | `af_subject_present` always true | 2 |

All nine mutants killed. M5 was rewritten after a first version (`$count++`
at every closing brace) turned 102 cases red — it proved the counter is
load-bearing but said nothing specific, so it was narrowed to the property
the case actually claims. B1 is the one that matters most: it turns red
exactly the two cases that were passing before this branch, in the harness
functions the rest of the suite is built on.

## Notes

**The issue's mechanism did not survive measurement.** #95 reasoned from the
code that `ConvertFrom-Json` would build a collection and the first element
would answer. On 5.1 it throws. The issue said so itself — "inferred from that
code, not from an executed run" — and the two-object fixture it asked for is
the reason this landed as a real fix in bash rather than a no-op in
PowerShell. The PowerShell half is still worth having: it converts an accident
of the parser into a stated property, with a message that names the right
cause.

**Why the fix could not live inside `Assert-True`.** Its signature takes
`[bool]$Condition`. By the time it is called, `$null -notmatch '2099'` is
already `$true` and the subject is gone. Any guard there would be guarding
nothing. This is the general shape: a checker cannot recover evidence its
caller has already discarded.

**Commit granularity.** The Red commit carries `test-hooks.sh` only. The
PowerShell assertions and the harness they exercise are the same file, so its
Red (measured at 218 / 14) could not be committed apart from the
implementation. The measurement is the evidence; the commit boundary is not.

**Placement in bash.** The self-check needs `run_case`, `stop_case` and
`$READ_FILE`, which are defined further down the file. Bash resolves a
function body at call time, so the block is wrapped in
`run_harness_self_check` and invoked after those definitions — the same
constraint PowerShell does not have, and the reason the two suites read
differently at that point.
