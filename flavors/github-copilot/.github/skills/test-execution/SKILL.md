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
| `lint: ruff fix` | `-Scope all -Fix` | refactorer |

All `lint:` tasks call `.github/scripts/run-lint.ps1`, which resolves the venv
interpreter itself and derives the rule set from `LINTING_STRICTNESS` in
`af-env.conf`. **Never invoke `ruff` directly** — task shells do not activate
the venv, so a bare `ruff` command fails with `CommandNotFoundException`, and a
direct call would bypass the configured strictness.

The stop-hook lint gate only sees *changed* files. Use these tasks to check the
repository as a whole.

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
whether `runTests` handles the case. `createAndRunTask` is the last resort.

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
