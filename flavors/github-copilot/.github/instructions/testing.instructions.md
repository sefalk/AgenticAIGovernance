---
name: 'Testing Standards'
description: 'TDD workflow, test conventions, and quality gates for all test files.'
applyTo: '**/test_*.py,tests/**/*.py,**/conftest.py'
---

# Testing Standards

Follow these conventions for all test code.

**Reference depth lives in skills.** How to *write* a good test — AAA, test
doubles, fixtures, edge cases, anti-patterns — is in
`skills/unit-testing/SKILL.md`. How to *run* tests — the full task table, phase
mapping, runtimes, per-agent budgets, test log — is in
`skills/test-execution/SKILL.md`. This file holds the rules that bind.

## TDD Workflow

Every code change follows **Red → Green → Refactor** as discrete steps:

1. **Red** — Write a failing test. Confirm it fails for the right reason.
2. **Green** — Write minimum implementation to make it pass.
3. **Refactor** — Improve structure. All tests remain green.

Each step is a **separate commit** (format: `git-workflow.instructions.md`).

## Test Directory Structure

```
tests/
  conftest.py     # Shared fixtures
  domain/         # Domain core tests (no external deps)
  adapters/       # Adapter tests (may use external deps)
  properties/     # Property-based tests (hypothesis)
  contracts/      # Port-adapter contract tests
  integration/    # End-to-end pipeline tests
```

## Naming Conventions

- Test files: `test_{module_name}.py`
- Test functions: `test_{function_name}_{scenario}`
- Fixtures: descriptive noun (`sample_data`, `empty_input`)

The name is the documentation: `test_withdraw_insufficient_funds_raises_error`,
not `test_1` or `test_it_works`.

## Three-Tier Test Strategy

**Tier 1 — Domain core** (fast, no external deps). Pure functions over plain
Python data. No I/O imports; if you need external deps, it is an adapter test.
Use `pytest.mark.parametrize` for boundary cases.

**Tier 2 — Property-based** (hypothesis). For mathematical invariants or wide
input spaces. Minimum 100 examples; every property carries a docstring stating
the invariant it asserts. Patterns: `skills/property-testing/SKILL.md`.

**Tier 3 — Adapter / integration** (may use external deps). Test-scoped
fixtures, never global singletons. Isolated and idempotent. Mark with custom
markers for selective execution.

**Contract tests** — every port interface gets a contract suite: an abstract
test class stating what *every* adapter must satisfy, with the adapter supplied
by a fixture the concrete subclass overrides. Adapter-specific test classes
inherit it, so a new adapter proves conformance by construction.

## Test Execution Rules

The complete task table, phase mapping, expected runtimes and per-agent budgets
are in `skills/test-execution/SKILL.md`. These rules bind regardless:

1. **Prefer `run_task`** with a pre-defined label. The common ones:
   `tests: domain` (fast, ~5s), `tests: all` (full suite, ~20 min),
   `tests: all + coverage`, `tests: domain + fail-fast` (Red phase),
   `lint: ruff check`.
2. **Never call `pytest` or `ruff` directly** — always the canonical runner
   script. A direct call bypasses venv resolution, the configured lint
   strictness, and the test log.
3. **A full-suite run happens at most ONCE per workflow.** Everything else is
   scoped. Exceeding this wastes 20+ minutes per run.
4. **Use the narrowest scope** — `domain` first; `all` only for the single
   final verification.
5. **Check `.github/test-log.json` before running.** If the scope passed
   recently and no relevant code changed, skip the run and cite the log — it
   is the source of truth for cross-agent test visibility.
6. **Do not pre-run what a stop hook already runs.** The implementer and
   refactorer stop hooks run the full suite and write the log.
7. **`run_in_terminal` is reserved** for coordinator and code-critic. Other
   agents use `run_task`, `runTests` (file- or test-scoped), or
   `createAndRunTask` when no label expresses the invocation. `createAndRunTask`
   is not a quieter terminal: the same PreToolUse classifier inspects it, and it
   may only invoke scripts under `AF_TASK_SCRIPT_DIRS`.
8. **Never create temp output files** — the runner streams to stdout.
9. **Task labels are a stable API** — do not rename one without updating
   every agent definition that uses it.

## Quality Gates

These are the **canonical thresholds** — source of truth for all agents.

| Module Type | Line Coverage | Branch Coverage | Mutation Score | Max Complexity |
|---|---|---|---|---|
| Domain core | ≥ 90% | ≥ 85% | ≥ 80% | ≤ 10 |
| Ports | ≥ 80% | ≥ 75% | ≥ 70% | ≤ 5 |
| Adapters | ≥ 60% | ≥ 50% | N/A | ≤ 15 |
| Utilities | ≥ 85% | ≥ 80% | ≥ 75% | ≤ 8 |

### Delta Thresholds (Per Change)

| Metric | Requirement |
|---|---|
| Coverage delta | ≥ 0 (no regression) |
| Lint violation delta | ≤ 0 (no new violations) |
| Complexity delta | ≤ 0 for refactoring tasks |

## What Not to Write

- **Trivial tests** — `assert True`, or a test that cannot fail.
- **Tests of implementation** — assert on behaviour, not internal variables.
- **External deps in domain tests** — if you need them, it is an adapter test.
- **Logic in tests** — no `if`/`for`/`try` in test bodies; tests are linear.
- **Shared mutable state** between tests.
- **`print()` in place of an assertion.**
- **Skips without a reason** — `@pytest.mark.skip` requires `reason=`.
