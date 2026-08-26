---
name: test-execution
description: 'Run tests and lint from an agent — pre-defined task labels, phase-specific scoping, expected runtimes, the per-workflow test budget, and the shared test log. Read this before executing any test or lint run.'
---

# Test Execution

How agents actually run tests in this framework. The *rules* live in
`instructions/testing.instructions.md`; this is the operational detail behind
them. Read it when you are about to run something, not when you are writing a
test.

## When to Use

- Before the first test or lint run in a workflow step.
- When you need a scope the minimal inline task list does not cover.
- When deciding whether a run can be skipped in favour of the test log.

## Pre-Defined Tasks (preferred)

Use `run_task` with the task label. Arguments are fixed — no dynamic params.

| Task Label | Args | Primary Users |
|---|---|---|
| `tests: all` | `-Scope all` | refactorer, implementer (final) |
| `tests: domain` | `-Scope domain` | implementer, test-writer, test-critic |
| `tests: adapters` | `-Scope adapters` | implementer, test-writer |
| `tests: properties` | `-Scope properties` | test-writer, test-critic |
| `tests: contracts` | `-Scope contracts` | implementer |
| `tests: all + coverage` | `-Scope all -Coverage` | code-critic, implementer |
| `tests: domain + coverage` | `-Scope domain -Coverage` | code-critic, implementer |
| `tests: adapters + coverage` | `-Scope adapters -Coverage` | code-critic, implementer |
| `tests: domain + fail-fast` | `-Scope domain -FailFast` | test-writer (Red phase) |
| `tests: all + fail-fast` | `-Scope all -FailFast` | refactorer, implementer |
| `tests: all + coverage + save` | `-Scope all -Coverage -OutputFile` | code-critic |
| `tests: adapters + fail-fast` | `-Scope adapters -FailFast` | implementer |
| `lint: ruff check` | `-Scope all` | implementer, refactorer, code-critic |
| `lint: ruff check src` | `-Scope src` | implementer, refactorer |
| `lint: ruff check tests` | `-Scope tests` | test-writer, refactorer |
| `lint: changed files` | `-Scope changed` | implementer, refactorer |
| `lint: ruff fix` | `-Scope all -Fix` | refactorer |

All `lint:` tasks call `.github/scripts/run-lint.ps1`, which resolves the venv
interpreter itself and derives the rule set from `LINTING_STRICTNESS` in
`af-env.conf`. **Never invoke `ruff` directly** — task shells do not activate
the venv, so a bare `ruff` command fails with `CommandNotFoundException`, and a
direct call would bypass the configured strictness. It also would not
reproduce the gate's verdict even with the right `--select`:
`check-python-linting.py` applies the project's own ruff `ignore` /
`per-file-ignores` on top of the selected rules (visible as `project_ignore=`
in its output), so a direct `ruff check --select=...` call can show violations
the gate does not have — a wasted edit, and pressure to add a `# noqa` the
project never asked for (issue #124).

### Checking the gate's own file set

The stop-hook lint gate does not lint the repository — it lints the *branch
delta*: everything changed between `merge-base(HEAD, BASE_BRANCH)` and `HEAD`,
plus the staged or unstaged working tree. That is a different set from any
directory scope, which is why a green `lint: ruff check` run has never been
proof that the gate will pass.

`lint: changed files` reproduces that set exactly, so you can see what the gate
will say before it says it. Use it before handing off; use `lint: ruff check`
when you want the repository as a whole instead.

The scope reports `files=0` when the branch changes no Python — that is a pass,
not a skipped run. It fails loudly only when the changed set cannot be computed
at all (no git repository), because "I cannot tell" must never be reported as
"nothing to do".

## Fallback: `runTests` or `createAndRunTask` (dynamic cases only)

For file- or test-scoped runs, use `runTests` with `files` and/or `testNames`
arguments. For one-off tasks not covered by pre-defined tasks (e.g., syntax
checks, custom lint), use `createAndRunTask`.

Only `code-critic` and `coordinator` have `run_in_terminal` — other agents
must use `run_task`, `runTests`, or `createAndRunTask`.

`createAndRunTask` requires `.vscode/tasks.json` to be strict JSON — it cannot
parse JSONC. When adding or editing tasks, follow
`instructions/tooling.instructions.md`; a pre-commit guard enforces it.

Before creating a task, check whether a pre-defined task already covers it, or
whether `runTests` handles the case. `createAndRunTask` is for invocations no
fixed label expresses.

It is **not** a quieter terminal. The same PreToolUse classifier inspects task
payloads and terminal commands, and a task may only invoke scripts under
`AF_TASK_SCRIPT_DIRS` — bare binaries (`git`, `ruff`, `pytest`), inline
interpreter payloads (`powershell -Command …`), shell metacharacters and
`options.shell` overrides are denied. If the thing you want to run has no
reviewed script, the answer is to add one, not to phrase it as a task.

## Phase-Specific Test Strategy

| Phase | Agent | Preferred Task | Fallback (when -Filter/-File needed) |
|---|---|---|---|
| Red (verify failing) | test-writer | `tests: domain + fail-fast` | `runTests` with `files`/`testNames` |
| Green (make pass) | implementer | `tests: domain` | `runTests` with `files` |
| Green (full suite) | implementer | `tests: all` | — |
| Refactor (no regression) | refactorer | `tests: domain` | `runTests` with `files` |
| Code review (metrics) | code-critic | `tests: all + coverage` | — |
| Code review (save report) | code-critic | `tests: all + coverage + save` | — |
| Re-Red (specific test) | test-writer | — | `runTests` with `files` + `testNames` |

## Expected Runtimes

| Scope | Tests | Typical Runtime | Cost |
|---|---|---|---|
| domain | ~600 | ~5s | LOW — run freely |
| properties | ~40 | <1s | LOW — run freely |
| contracts | ~20 | ~2s | LOW — run freely |
| adapters | ~300 | ~15–20 min | HIGH — run sparingly |
| all | ~1100 | ~20 min | HIGH — once per workflow |

Counts and runtimes are indicative for a mature project — the cost *ordering*
is the durable part, not the absolute numbers.

## Test Budget per Workflow

**Cardinal Rule:** a full-suite run (`tests: all`) happens **at most ONCE** per
workflow. All other test execution must be scoped.

| Agent | Budget | Scope | When to Skip |
|---|---|---|---|
| test-writer | 1–3 targeted runs | `-Filter` or `-File` on new tests, domain scope, fail-fast | Never runs all. Never adapters unless writing adapter tests. |
| implementer | unlimited domain, 1 adapters (if changed), 0× all | domain during dev, adapters only if adapter code changed | Stop hook runs all via canonical script and writes test log — do not pre-run all. |
| refactorer | unlimited domain, 0 adapters, 0 all | domain after each step | Stop hook runs full suite — do NOT pre-run all yourself. |
| code-critic | 0–1 scoped runs | domain+coverage or adapters+coverage | Accept implementer results if test log shows < 5 min old. Never re-run what test log shows as current. |
| test-critic | 0 runs | N/A — review only, do not execute | Always skip. Read test log for context. |

## Test Log (`.github/test-log.json`)

The test runner automatically maintains a persistent test log at
`.github/test-log.json`. Each scoped run updates ONLY that scope's entry —
other scope data is preserved.

**Before running tests**, read the test log:

- Compare `last_run` with the last code change time.
- If the scope passed recently and no relevant code changed → **skip the run**.
- Report: `Tests: accepted from test log (domain: 619/619 passed, 5s ago)`.

The test log is the source of truth for cross-agent test visibility.

**Never accept an entry with `"status": "error"` as evidence.** That status
means the runner itself failed — wrong interpreter, missing dependency, usage
error, nothing collected — and no test was executed. Such an entry carries
`passed`/`failed`/`errors` as `null`, never `0`, precisely so that a run which
never happened cannot be read as a green one. Its `error_message` field holds
the interpreter's own words. Fix the runner and re-run the scope; do not report
the scope as passing and do not skip the run.

**Never accept an entry with `"status": "running"` as evidence either.** The
runner claims its entry *before* pytest starts and replaces it when pytest
returns, so `running` means one of exactly two things: a run is in flight right
now, or a run was interrupted — terminal closed, agent cancelled, machine
slept — and never reported. Counters and `exit_code` are `null`; `started`
holds the moment the entry was claimed. Neither case is a result: re-run the
scope. Before this marker existed, an interrupted run left the *previous*
entry in place, and a stale green was indistinguishable from a fresh one.

## Direct Invocation (terminal-capable agents only)

```bash
# Via terminal (for -Filter or -File):
.github/scripts/run-tests.ps1 -Scope domain -Filter "test_name"
.github/scripts/run-tests.ps1 -File tests/domain/test_helper.py
.github/scripts/run-tests.ps1 -Scope all -Coverage

# Mutation testing (manual only, not via task):
mutmut run --paths-to-mutate=<module> --tests-dir=tests/domain/
```

Never call `pytest` directly — the canonical runner resolves the interpreter,
applies the scope mapping, and writes the test log. A bare `pytest` call does
none of that.

## pytest Configuration (`pyproject.toml`)

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
markers = [
    "slow: tests taking > 5 seconds",
    "property: hypothesis property-based tests",
]
addopts = "-ra --strict-markers"
```

## References

- `instructions/testing.instructions.md` — the binding rules and quality gates
- `skills/unit-testing/SKILL.md` — how to write the tests being run
- `instructions/tooling.instructions.md` — authoring `.vscode/tasks.json`
