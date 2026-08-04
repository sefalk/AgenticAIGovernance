# Fix: hook guards that are configured but never verified (#37)

<!-- copilot:generated | planner | 2026-08-04 -->

- **Created:** 2026-08-04
- **Issue:** [#37](https://github.com/sefalk/AgenticAIGovernance/issues/37)
- **Branch:** `agent/37-hook-guard-hermeticity`
- **Complexity tier:** Standard
- **Status:** COMPLETED

## The issue's diagnosis was wrong, and the way it was wrong matters

#37 reports 4 failing tests in `test-hooks.ps1` and concludes that the branch
guard for test-writer and refactorer "never fires" — a disabled protection
mechanism. Reproduction on `dev` gives **58 passed / 1 failed**. The three
branch-guard tests pass.

They passed because of the branch we happened to be standing on. The guard
reads the **real current branch**:

```powershell
$currentBranch = git -C $codeRoot branch --show-current
if ($currentBranch -and $currentBranch -notmatch '^agent/') { ...deny... }
```

The test never establishes a branch. It asserts "denied on non-agent branch"
and then inherits whatever the developer's checkout happens to be. On `dev` it
passes, on `agent/*` it fails. #37 was filed while verifying #23 — from an
agent branch.

So the guard works. What does not work is the test, and that has a second,
worse consequence.

### Four further tests are vacuous, and they are green

In both hooks the branch gate is evaluated **before** the gate the test is
named after. On `dev`, these four are denied by the branch gate and never
reach their subject:

| Test | Believed to verify | Actually verifies |
|---|---|---|
| `test-writer cannot edit production code` | `SRC_DIR` gate | branch gate |
| `test-writer cannot create production file` | `SRC_DIR` gate | branch gate |
| `refactorer cannot createFile` | no-new-files gate | branch gate |
| `refactorer cannot createDirectory` | no-new-files gate | branch gate |

Delete the `SRC_DIR` gate from `test-writer-pretooluse.ps1` and the suite stays
green. The suite reports on these gates on neither branch: red for the wrong
reason on `agent/*`, green for the wrong reason on `dev`.

This is the same error class #37 names — *configured ≠ effective* — one level
up: **tested ≠ verified**.

### The fourth failure is a real hook bug, not a test assumption

#37 guesses that `clean URL is allowed` fails because the test's expectation
drifted from a more restrictive `WEB_FETCH_ALLOWLIST`. It has not:
`docs.python.org` is in `af-env.conf`. The hook never reads it.

```powershell
$repo = (git rev-parse --show-toplevel)      # AAIG repo root
$conf = Join-Path $repo '.github/af-env.conf' # does not exist here
```

AAIG keeps its payload at `flavors/github-copilot/.github/`, so there is no
`.github/` at the repo top level. `$allow` stays empty, every domain falls
through to `ask`. The allowlist is configuration that never reaches the code
path that consumes it — and it fails **silently**, because "not in allowlist"
and "allowlist not found" produce the same output.

Every other `.ps1` hook resolves config script-relative
(`$PSScriptRoot` → `$mainRoot`, plus the worktree sentinel). The researcher
hook is the outlier, in both `.ps1` and `.sh`.

## Scope

| Subtask | What | Gate |
|---|---|---|
| 1 | Researcher hook resolves `af-env.conf` script-relative (`.ps1` + `.sh`) | `clean URL is allowed` passes for the right reason |
| 2 | Fixture-repo harness: run a hook against a temp git repo on a chosen branch | Branch is an input, not an accident |
| 3 | Branch-context tests use the harness, both directions | deny on `dev` **and** allow on `agent/x` |
| 4 | The four vacuous tests run on an `agent/*` fixture | Each reaches its own gate |
| 5 | Mutation check: disable each gate, confirm its test goes red | No assertion passes without its subject |
| 6 | Harden what the fixture exposed: detached HEAD, bash cwd dependency | Bash pendants tested, not read |

Out of scope, recorded as a follow-up: config resolution across hooks uses
**three** different strategies — script-relative, `git rev-parse
--show-toplevel`, and a bare relative `.github/af-env.conf` that depends on the
process's cwd (`coordinator-*.sh`, `implementer-stop.sh`, `refactorer-stop.sh`,
`documenter-stop.sh`, `test-writer-pretooluse.sh`). The bare-relative form has
the same silent-empty failure mode as the researcher bug. Fixing eleven files
is not this issue.

## Acceptance criteria

1. `test-hooks.ps1` is green on `dev` **and** on an `agent/*` branch, and the
   result does not depend on the checked-out branch at all.
2. The branch guard is verified in both directions for test-writer and
   refactorer.
3. Each of the four previously vacuous tests fails when its own gate is
   removed, demonstrated by mutation, not by inspection.
4. The researcher hook reads the allowlist from the deployed `.github/` in
   AAIG's own layout and in a deployed project.
5. No test-only backdoor in a hook: the branch is controlled by fixture layout,
   never by an environment variable a real run could set.

## Risks

- **A test-only override in production code.** Adding e.g.
  `AF_HOOK_BRANCH_OVERRIDE` would make the guard bypassable in real use.
  Rejected: the fixture supplies a real git repo on a real branch instead.
- **~~`.sh` hooks cannot be executed here~~ — wrong.** The plan assumed no bash
  on this machine and budgeted the `.sh` change as a mirror reviewed by
  reading. Git ships one (`C:\Program Files\Git\bin\bash.exe`). Running the
  pendants found a hook that had never executed at all. The assumption was
  itself an instance of *tested ≠ verified*.
- **Fixture cost.** Each `git init` is ~50 ms; the branch-context tests are a
  handful, not the whole suite.

## Outcome

| Acceptance criterion | Evidence |
|---|---|
| 1. Result independent of the checked-out branch | `test-hooks.ps1`: 63 passed / 0 failed on `agent/37-…` (was 55/4 there, 58/1 on `dev`) |
| 2. Branch guard verified in both directions | Two new `Assert-Allow` cases on an `agent/*` fixture, plus the existing deny cases on a `dev` fixture |
| 3. Vacuous tests fail without their gate | 5 mutants disabled one at a time, each killed by a named test; working tree clean afterwards |
| 4. Researcher hook reads the deployed allowlist | `docs.python.org` → `allow`, `evil.example.com` → `ask`, with distinguishable reasons |
| 5. No test-only backdoor | No environment override exists; the branch comes from fixture layout |

Subtask 6 found three defects the fixture made visible:

1. **A detached HEAD passed as an agent branch.** `git branch --show-current`
   returns empty when detached, and the guard denied only a *non-empty*
   non-agent branch — while our own merge-rehearsal advice is
   `git worktree add --detach`. Now: detached-inside-a-repo denies; outside a
   repository the guard stays silent, deliberately (non-git projects).
2. **`refactorer-pretooluse.sh` had never run.** It tested `$PYTHON` without
   defining it; under `set -u` it aborted before any gate. Zero coverage, so
   nothing noticed.
3. **The bash guards resolved git and `af-env.conf` against the process cwd.**
   Same silent-empty failure mode as the researcher bug, in the pendants #37
   asked us to check.

`scripts/test-hooks.sh` now covers the pendants (10 cases, all passing). One
local caveat is handled in the harness, not in the hooks: this Windows host
exposes `python3` as a Microsoft Store execution alias that `command -v` finds
but cannot run, so the harness shims it. On Linux the hooks see a real
`python3`.

## Follow-up

- Config resolution across hooks still uses three strategies (see *Scope*).
  The bare-cwd form remains in `coordinator-postmerge.sh`,
  `coordinator-posttooluse.sh`, `coordinator-pretooluse.sh`,
  `implementer-stop.sh`, `refactorer-stop.sh`, `documenter-stop.sh`.
- The researcher hook reads `tool_input.url` / `.uri`. VS Code's fetch tool
  passes `urls` (an array). Worth checking against a real payload — if it does
  not match, the credential scan and the allowlist are both inert in practice.

## Change log

| Date | Change |
|---|---|
| 2026-08-04 | Created. Diagnosis replaces the issue's hypothesis: guard works, tests are non-hermetic; researcher allowlist bug is real. |
| 2026-08-04 | Subtasks 1–5 done: researcher config resolution fixed, fixture harness added, 63/0 green, 5/5 mutants killed. |
| 2026-08-04 | Subtask 6 added and done after the fixture exposed a detached-HEAD gap, a dead bash hook, and cwd-dependent resolution. `test-hooks.sh` added. Status → COMPLETED. |
