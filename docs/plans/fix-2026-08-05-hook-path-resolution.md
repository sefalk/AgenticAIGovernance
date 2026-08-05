# Fix: one way to resolve roots, config and interpreter (#54)

<!-- copilot:generated | planner | 2026-08-05 -->

- **Created:** 2026-08-05
- **Issue:** [#54](https://github.com/sefalk/AgenticAIGovernance/issues/54)
- **Branch:** `agent/54-hook-path-resolution`
- **Complexity tier:** Deep
- **Status:** COMPLETED

## The measured defect

Three lookups in the hook layer share one failure mode: **an empty result is
treated as "the feature is off" rather than as an error.** All three were
confirmed by execution before this plan was written.

### 1. Config resolved from the cwd

Fixture repo with `.github/af-env.conf` at the root:

```
cwd=root      -> [BASE_BRANCH=trunk]
cwd=docs      -> []
cwd=docs/deep -> []
script-relative equivalent always resolves: [BASE_BRANCH=trunk]
```

No error, no warning — every setting silently falls back to its default. The
agent process is not guaranteed to sit at the repo root, and under worktrees it
routinely does not.

### 2. The `.ps1` side is not clean either

Issue #54 states that the cwd-relative form is confined to the `.sh` hooks.
It is not:

| File | Line | Shape |
|---|---|---|
| `coordinator-pretooluse.ps1` | 46, 108 | `Join-Path (Get-Location) '.github/af-env.conf'` |
| `documenter-stop.ps1` | 35 | same |

`coordinator-pretooluse.ps1` is the hook that enforces the hard gates.

### 3. The interpreter lookup has the same shape

`command -v python3` is treated as "found" whenever it returns a path. On
Windows hosts it returns the WindowsApps App Execution Alias:

```
which: [/c/Users/.../WindowsApps/python3]
size:  [121]
exec:  [Python was not found; run without arguments to install from the Microsoft Store, ...]
python (no 3): [/c/.../Python311/python] -> [43]
```

Repaired in two hooks during #56. Still present in `researcher-pretooluse.sh`,
`refactorer-pretooluse.sh`, `test-writer-pretooluse.sh`,
`session-mcp-readiness.sh`, and as `command -v python` in `implementer-stop.sh`
and `refactorer-stop.sh`.

## Root cause

Four resolution strategies are in use across ~20 hook files:

| Strategy | Files | Correct? |
|---|---|---|
| Script-relative `MAIN_ROOT` + worktree sentinel | most `.ps1`, 3 `.sh` | yes |
| `git rev-parse --show-toplevel` | `block-dangerous.*`, `session-mcp-readiness.*`, `session-context.sh` | no — misses when `.github/` is not at the top level |
| Bare cwd-relative | 6 `.sh`, 2 `.ps1` | no — misses whenever cwd is not the root |
| `Join-Path (Get-Location)` | 2 `.ps1` | no — same as above |

The preamble is copied per file, so a fix lands in one copy and the other nine
keep the defect. That is exactly what happened after #37 and again after #56.

## Design decision: shared helper **and** a drift guard

Two options were considered.

- **Inline the correct preamble everywhere + a test that asserts they are
  identical.** No new runtime dependency, but the duplication stays and the
  validated-interpreter logic is ~10 non-obvious lines to copy correctly.
- **Extract a sourced helper.** DRY, one place to fix — at the cost of a new
  file that every hook depends on.

Chosen: **both, for different jobs.** The helper removes the duplication; the
drift guard is a static test that fails if any hook reintroduces a bare
cwd-relative config read or an unvalidated interpreter lookup. The helper
alone would not stop the next hook from being written the old way.

The missing-helper failure mode is covered by the deploy manifest and by a
test that asserts every hook sources it.

## Subtasks

### 1. `_common.sh` / `_common.ps1`

Expose, in both shells:

- `MAIN_ROOT` / `CODE_ROOT` — script-relative, worktree-sentinel aware.
- A config accessor that returns a value **and** distinguishes
  *config file not found* from *key not present*.
- A validated interpreter path — probed by execution, not by presence.

**Acceptance:** given a fixture repo, the accessor returns the configured value
from any cwd; with the config removed it reports *not found*, not an empty
value; the interpreter resolver rejects a stub that resolves but does not run.

### 2. Migrate every hook

All `.sh` and `.ps1` hooks source the helper and drop their local preamble,
including the `--show-toplevel` users.

**Acceptance:** no hook file contains a bare `.github/af-env.conf` read, a
`Join-Path (Get-Location)` config read, or `git rev-parse --show-toplevel` for
config resolution. Existing hook tests stay green.

### 3. Drift guard in the test harness

Static assertions in `test-hooks.ps1` and `test-hooks.sh` over every hook file.

**Acceptance:** the guard fails on a deliberately reintroduced cwd-relative
read (verified by seeding one), and passes on the migrated tree.

### 4. Manifest and docs

New files in `.af-manifest`; a short note in the hook authoring guidance.

**Acceptance:** deploy dry-run lists the new files; `test-deploy-flags.ps1`
stays green.

## Risks

| Risk | Mitigation |
|---|---|
| Sourcing failure breaks every hook at once | Helper is dependency-free and syntax-checked in both shells before migration; hook suite is the gate |
| `set -e` interaction — a helper function returning non-zero kills the caller | Accessors return 0 with an explicit *found* flag rather than signalling by exit status |
| Behaviour change in gate hooks goes unnoticed | Migration is mechanical; the 90-assertion suite must stay green with no expectation edits |
| Deploy order (helper missing in an older target) | Manifest entry + a test asserting each hook sources it |

## Out of scope

- **#64** — `researcher-pretooluse` is dead on every path (payload shape, `sed`
  crash). Separate branch; it will consume this helper rather than re-roll the
  interpreter logic.
- **#61** — this repo does not run its own hooks. Unchanged here.

## Outcome

All four subtasks landed. Every acceptance criterion was verified by running
the suites, not by reading the diff.

| Subtask | Result | Commit |
|---|---|---|
| 1. Shared preamble | `_common.sh` / `_common.ps1` — script-relative roots, worktree sentinel, `af_conf_get` / `Get-AfConfig`, execution-probed interpreter | `c73fc16` |
| 2. Migrate every hook | 13 `.sh` and 7 `.ps1` hooks source the preamble; all `--show-toplevel`, `Join-Path (Get-Location)` and bare `command -v python*` lookups removed | `0ebf351` |
| 3. Drift guard | `scripts/check-hook-resolution.py` (AF001–AF005), run over `hooks/` by `test-hooks.ps1` | `7c28ec4` |
| 4. Manifest and docs | `_common.*` + the checker registered in `.af-manifest`; *Writing a New Hook* section in `hooks/README.md` | `fe8f60b`, `f3b3f10` |

**Measured at completion:** `check-hook-resolution.py hooks` exit 0 ·
`test-hooks.ps1` 103/103 · `test-hooks.sh` 17/17 · `test-lint-gate.ps1` 21/21 ·
`test-deploy-flags.ps1`, `test-hooks-integration.ps1`,
`test-worktree-scripts.ps1`, `test-quality-gate.ps1`, `test-session-cost.ps1`,
`test-large-file-guard.ps1` all exit 0 · `ruff check` and `ruff format` clean.

### What the work uncovered beyond the plan

- **The harness was hiding the defect it should have caught.** `test-hooks.sh`
  installed a `python3` shim into its fixture `PATH`, so the bash hooks always
  saw a working `python3` under test and never under production. The shim is
  gone; the suite now resolves the interpreter through `_common.sh` itself and
  skips with a stated reason if none works.
- **A missing assertion, not a missing fix, is why the interpreter bug
  survived subtask 1.** The PowerShell side had no test that the resolved
  interpreter *runs*. Adding one immediately failed and exposed that
  PowerShell 5.1 silently drops empty-string arguments to native commands, so
  the probe `& python -c ''` degenerated to `python -c` and `Find-AfPython`
  rejected every working interpreter — which is what broke `test-lint-gate.ps1`
  from 21/21 to 2/21. Probing with `-c 'pass'` fixes it; the assertion now
  guards it, together with a stub that resolves but exits non-zero.
- **`set -e` abort hazard.** Several migrated hooks used `A && B && exit 0`
  chains, which abort the hook when `A` is merely false. Converted to explicit
  `if` blocks.
- **The checker must report on stdout.** With
  `$ErrorActionPreference = 'Stop'`, any native-command stderr becomes a
  terminating PowerShell error, which killed the suite on the checker's own
  findings. Findings go to stdout; the exit code carries the verdict.

### Deferred, with evidence

- `coordinator-pretooluse.sh` and `session-mcp-readiness.sh` fail `bash -n`
  **on `HEAD`** (escaped quote inside single quotes; unterminated quote).
  Pre-existing, unrelated to this branch — filed separately rather than
  smuggled into this fix.
- `test-context-budget.ps1` → `J_real_payload_within_budget` fails on `HEAD`
  too.
