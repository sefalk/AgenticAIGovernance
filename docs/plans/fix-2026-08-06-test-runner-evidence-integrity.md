<!-- copilot:generated | documenter | 2026-08-06 -->

# Fix: test runner evidence integrity (issue #73)

- **Status:** COMPLETED
- **Issue:** [#73](https://github.com/sefalk/AgenticAIGovernance/issues/73)
- **Branch:** `agent/73-test-runner-evidence-integrity`
- **Complexity tier:** Standard
- **Date:** 2026-08-06

## Problem

Two defects that happen to share a trigger.

### 1. The argument vector is corrupted (Windows only)

`$scopeMap['all'] = 'tests/'` was the only entry carrying a trailing separator.
`Join-Path` normalises it to `…\tests\`. When the workspace path contains
spaces, PowerShell quotes the argument, and the CRT argv parser reads the
resulting `\"` as an *escaped quote*: it loses the closing quote and swallows
every following argument into `argv[1]`.

Measured, from a path containing a space:

```
argv[1] = 'C:\…\af rt probe\tests" --tb=long -q --no-header'
(no argv[2], no argv[3], no argv[4])
```

pytest receives one nonsense path and collects nothing. `-Scope all` is the
**default**, so a bare `run-tests.ps1` was broken, along with four shipped VS
Code tasks (`tests: all`, `+ coverage`, `+ fail-fast`, `+ coverage + save`).
It only reproduces from a path containing spaces — which is every default
OneDrive path, and is why it survived.

### 2. A run that never happened is logged as green (both platforms)

`2>$null` discarded pytest's usage error. With empty stdout the summary regex
matched nothing, so the runner wrote:

```json
"all": { "passed": 0, "failed": 0, "errors": 0, "total": 0, "exit_code": 4 }
```

A consumer reading `failed: 0` concludes green. The test-execution skill tells
agents the log is "the source of truth for cross-agent test visibility" and
that they may **skip** a run when the log looks current — so this entry does not
merely misinform, it suppresses the run that would have exposed it.

This half is **not** Windows-specific: `run-tests.sh` produced the identical
entry from empty stdout. Any runner failure — wrong interpreter, missing
dependency, usage error — triggers it on any platform. The trailing separator
was one trigger; the log was the defect.

This is the same shape as #64, #68, #69, #70 and #74: **a gate that could not
run and a gate with nothing to report produce identical output, and every
reader takes that silence for consent.**

## Changes

| File | Change |
|---|---|
| `scripts/run-tests.ps1` | `'all' = 'tests'`; defensive `.TrimEnd('\','/')` after `Join-Path`; stderr captured to a temp file instead of `$null`; runner failure recorded as `status: error` with null counters and surfaced to the console |
| `scripts/run-tests.sh` | Same three changes, keeping the two runners in lockstep |
| `scripts/test-run-tests.ps1` | New regression harness (12 cases) |
| `skills/test-execution/SKILL.md` | Documents `status: error` and forbids accepting such an entry as evidence |
| `.github/.af-manifest` | Ships the new harness |

### The runner-failure rule

```
no parseable summary line  AND  non-zero exit  ⇒  the runner failed
```

Such an entry records `passed`/`failed`/`errors` as **`null`, never `0`**, adds
`status: "error"` and an `error_message` holding the interpreter's own words.
`null` is deliberate: a consumer testing `failed == 0` gets a false answer
instead of a reassuring one. Successful runs gain `status: "ok"`.

Stderr is retained rather than discarded. It is noise on a green run (PySpark),
but it is the only diagnosis when the runner fails — discarding it is what made
the failure silent in the first place.

## Verification

`test-run-tests.ps1` — 12 cases, all driven against the **shipped** scripts
(scope values are parsed out of them, never hardcoded), from fixture paths that
**contain a space**:

| Case | Asserts |
|---|---|
| A, B | No scope path in either runner carries a trailing separator |
| C ×5 | For every scope, the following arguments survive as separate argv entries |
| D | No log entry claims zero failures for a run that executed nothing |
| E | The entry is positively labelled `status: error` |
| F | The interpreter's own error text reaches the console |
| G ×2 | End-to-end: a real run's arguments arrive intact and are recorded as `ok` |

Red baseline (before the fix): **4/10 passed** — A, B, C_all, D, E, F red, with
D reporting exactly the issue's evidence, `failed=0 total=0 exit_code=1`.

Green: **12/12**.

Mutation tests, because a green run on fixtures written after the fix proves
little:

| Mutation | Red cases |
|---|---|
| `'all' = 'tests/'` restored | A, C_all (G survives — `TrimEnd` catches it) |
| …and `TrimEnd` removed | A, C_all, **G** |
| `$runnerFailed = $false` | D, E, F |

Both protections are therefore independently effective, and no case passes for
the wrong reason. `bash -n run-tests.sh` clean; the bash log path verified
behaviourally against a stub interpreter (`passed/failed/errors: null`,
`status: "error"`, valid JSON).

## Notes and residual scope

- **`run-tests.ps1` and `run-tests.sh` are `[customizable]` in `.af-manifest`.**
  Deployed projects that have modified them will not receive this fix by a
  plain update — it surfaces as a conflict to resolve. Projects on an older AF
  (e.g. MPUsageXPTP on 1.21.43) must be checked explicitly.
- The stop hooks were already immune to the lie: they gate on `exit_code -eq 0`,
  which a runner failure never satisfies. They were left untouched. The readers
  actually misled were agents and humans following the test-execution skill,
  which is why the fix lands in the log schema and its documentation.
- Not addressed: the log has no notion of *staleness of the code under test*
  beyond `last_run` versus commit timestamps. Out of scope here.
