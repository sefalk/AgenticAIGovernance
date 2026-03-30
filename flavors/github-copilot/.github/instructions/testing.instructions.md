---
name: 'Testing Standards'
description: 'TDD workflow, test conventions, and quality gates for all test files.'
applyTo: '**/test_*.py,tests/**/*.py,**/conftest.py'
---

# Testing Standards

Follow these conventions for all test code.

## TDD Workflow

Every code change follows **Red → Green → Refactor** as discrete steps:

1. **Red** — Write a failing test. Confirm it fails for the right reason.
2. **Green** — Write minimum implementation to make it pass.
3. **Refactor** — Improve structure. All tests remain green.

Each step is a **separate commit**:
```
[red] test_compute_result_filters_nulls
[green] compute_result: filter null values
[refactor] extract validation to helper
```

## Test Directory Structure

```
tests/
  conftest.py                    # Shared fixtures
  domain/                        # Domain core tests (no external deps)
    test_{module}.py
  adapters/                      # Adapter tests (may use external deps)
    test_{adapter}.py
  properties/                    # Property-based tests (hypothesis)
    test_{module}_properties.py
  contracts/                     # Port-adapter contract tests
    test_{port}_contract.py
  integration/                   # End-to-end pipeline tests
    test_{pipeline}.py
```

## Naming Conventions

- Test files: `test_{module_name}.py`
- Test functions: `test_{function_name}_{scenario}`
- Fixtures: descriptive noun (`sample_data`, `empty_input`)

```python
# Good names
def test_compute_result_returns_empty_for_no_data():
def test_parse_input_raises_on_missing_field():

# Bad names
def test_1():
def test_it_works():
```

## Three-Tier Test Strategy

### Tier 1: Domain Core Tests (fast, no external deps)

- Pure functions using plain Python data
- No I/O imports — if you need external deps, it's an adapter test
- Use `pytest.mark.parametrize` for boundary cases
- Target: ≥ 90% line coverage of domain core

### Tier 2: Property-Based Tests (hypothesis)

- Functions with mathematical invariants or wide input spaces
- Minimum 100 examples per property
- Each property has a docstring stating the invariant

```python
from hypothesis import given, strategies as st

@given(lst=st.lists(st.integers(), min_size=0, max_size=100))
def test_function_preserves_invariant(lst):
    """Invariant: describe what should always hold and why."""
    result = my_function(lst)
    assert invariant_holds(result)
```

### Tier 3: Adapter / Integration Tests (may use external deps)

- Use test-scoped fixtures (not global singletons)
- Keep isolated and idempotent
- Mark with custom markers for selective execution

### Contract Tests (Port–Adapter Verification)

Every port interface should have a **contract test suite**:

```python
"""Contract tests for the DataReader port."""

class DataReaderContract:
    """Every DataReader adapter must pass these."""

    @pytest.fixture
    def reader(self):
        raise NotImplementedError("Subclass must provide a reader fixture")

    def test_read_returns_data(self, reader):
        result = reader.read("test_source")
        assert result is not None
```

Adapter-specific tests inherit the contract:

```python
class TestMyAdapterContract(DataReaderContract):
    @pytest.fixture
    def reader(self):
        return MyAdapter(config)
```

## The AAA Pattern (Arrange-Act-Assert)

Every unit test follows three phases:

```python
def test_compute_result_filters_nulls():
    # Arrange — set up inputs and expected state
    data = [1, None, 3, None, 5]
    expected = [1, 3, 5]

    # Act — invoke the behaviour under test (one call)
    result = compute_result(data)

    # Assert — verify the outcome
    assert result == expected
```

**Rules:**
- **One logical assertion per test.** Multiple `assert` calls are fine if
  they verify one behaviour. Separate tests for separate behaviours.
- **No logic in tests.** No `if`, `for`, `try/except` in test code. Tests
  are linear scripts.
- **Descriptive name = documentation.** The test name describes the scenario
  and expected outcome: `test_withdraw_insufficient_funds_raises_error`.
- **Visible data.** Inline test data or use explicit fixtures. Avoid
  "Mystery Guest" anti-pattern (hidden external data files).

## Agent Test Execution

<!-- copilot:modified | implementer | 2026-03-18 | added pre-defined tasks via run_task -->

Agents execute tests via **pre-defined VS Code Tasks** (`run_task`) for common
scenarios, falling back to `run_in_terminal` only for dynamic cases.

### Pre-Defined Tasks (preferred)

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

### Fallback: `runTests` or `createAndRunTask` (dynamic cases only)

For file- or test-scoped runs, use `runTests` with `files` and/or `testNames`
arguments. For one-off tasks not covered by pre-defined tasks (e.g., syntax
checks, custom lint), use `createAndRunTask`.

Only `code-critic` and `coordinator` have `run_in_terminal` — other agents
must use `run_task`, `runTests`, or `createAndRunTask`.

### Phase-Specific Test Strategy

| Phase | Agent | Preferred Task | Fallback (when -Filter/-File needed) |
|---|---|---|---|
| Red (verify failing) | test-writer | `tests: domain + fail-fast` | `runTests` with `files`/`testNames` |
| Green (make pass) | implementer | `tests: domain` | `runTests` with `files` |
| Green (full suite) | implementer | `tests: all` | — |
| Refactor (no regression) | refactorer | `tests: domain` | `runTests` with `files` |
| Code review (metrics) | code-critic | `tests: all + coverage` | — |
| Code review (save report) | code-critic | `tests: all + coverage + save` | — |
| Re-Red (specific test) | test-writer | — | `runTests` with `files` + `testNames` |

### Expected Runtimes

| Scope | Tests | Typical Runtime | Cost |
|---|---|---|---|
| domain | ~600 | ~5s | LOW — run freely |
| properties | ~40 | <1s | LOW — run freely |
| contracts | ~20 | ~2s | LOW — run freely |
| adapters | ~300 | ~15–20 min | HIGH — run sparingly |
| all | ~1100 | ~20 min | HIGH — once per workflow |

### Test Budget per Workflow

**Cardinal Rule:** A full-suite run (`tests: all`) happens **at most ONCE**
per workflow. All other test execution must be scoped.

| Agent | Budget | Scope | When to Skip |
|---|---|---|---|
| test-writer | 1–3 targeted runs | `-Filter` or `-File` on new tests, domain scope, fail-fast | Never runs all. Never adapters unless writing adapter tests. |
| implementer | unlimited domain, 1 adapters (if changed), 0× all | domain during dev, adapters only if adapter code changed | Stop hook runs all via canonical script and writes test log — do not pre-run all. |
| refactorer | unlimited domain, 0 adapters, 0 all | domain after each step | Stop hook runs full suite — do NOT pre-run all yourself. |
| code-critic | 0–1 scoped runs | domain+coverage or adapters+coverage | Accept implementer results if test log shows < 5 min old. Never re-run what test log shows as current. |
| test-critic | 0 runs | N/A — review only, do not execute | Always skip. Read test log for context. |

### Test Log (`.github/test-log.json`)

The test runner automatically maintains a persistent test log at
`.github/test-log.json`. Each scoped run updates ONLY that scope's entry —
other scope data is preserved.

**Before running tests**, read the test log:
- Compare `last_run` timestamp with the last code change time
- If the scope passed recently and no relevant code changed → **skip the run**
- Report: "Tests: accepted from test log (domain: 619/619 passed, 5s ago)"

**The test log is the source of truth** for cross-agent test visibility.

### Rules

1. **Prefer `run_task`** — pre-defined tasks are safer and avoid terminal confirmation.
2. **Never call pytest directly** — always use the canonical test runner script.
3. **Never create temp output files** — the runner streams to stdout.
4. **Use the narrowest scope** — `domain` first, `all` only for the single final verification per workflow.
5. **Use `runTests` for specific files/tests** — `run_in_terminal` is reserved for coordinator and code-critic only.
6. **Use fail-fast tasks for Red phase** — stop at first failure to confirm the right test fails.
7. **Task labels are a stable API** — do not rename without updating all agent definitions.
8. **Check test log before running** — read `.github/test-log.json` first. If the scope passed recently and no code changed since, skip the run and cite the log.
9. **Respect the test budget** — see "Test Budget per Workflow" above. Exceeding budget wastes 20+ minutes.
10. **`createAndRunTask` is last resort** — before creating a task, check if a
    pre-defined task already covers it (`run_task`), or if `runTests` handles
    the case (file-scoped runs, coverage). Only use `createAndRunTask` when
    no existing task or tool fits.

## Test Doubles (Stubs, Mocks, Fakes, Spies)

Use test doubles to isolate the unit under test from its dependencies.

| Double | Purpose | When to Use |
|---|---|---|
| **Stub** | Returns pre-configured responses | Control indirect inputs (e.g., "return this DataFrame when called") |
| **Mock** | Verifies interactions (calls, arguments) | The *behaviour* (not the result) is what matters |
| **Fake** | Working implementation with shortcuts | Stub is too simple, real dependency too heavy (e.g., in-memory store) |
| **Spy** | Records calls, delegates to real implementation | Observe without fully replacing |

**Guidelines:**
- **Prefer stubs over mocks.** Test *outcomes*, not *implementation details*.
  Mocks couple tests to internals and break on harmless refactoring.
- **Don't mock what you don't own.** Wrap third-party APIs behind your own
  interface (port), then stub the interface.
- **Use dependency injection.** If you can't inject a dependency, the design
  needs refactoring.
- **Minimise test doubles.** Pure functions need no doubles. If a function
  requires many doubles, it has too many dependencies.

```python
# Stub example — control what the dependency returns
def test_processor_skips_empty_batches(mocker):
    reader = mocker.stub(name="reader")
    reader.read.return_value = []
    processor = BatchProcessor(reader=reader)

    result = processor.run()

    assert result.batches_processed == 0
```

## Fixtures

- Prefer **factory fixtures** over static ones
- Put shared fixtures in the nearest `conftest.py`
- Expensive fixtures at `session` scope
- Data fixtures at `function` scope (avoids state leakage)

## What Makes a Good Test

- **Specific**: tests one behaviour, fails for one reason
- **Named descriptively**: function name is the documentation
- **Independent**: no test depends on another's execution
- **Fast**: domain tests complete in < 1 second total
- **Deterministic**: no uncontrolled randomness

## What to Avoid

- **Trivial tests**: `assert True`, `assert 1 == 1`
- **Testing implementation**: test behaviour, not internal variables
- **External deps in domain tests**: if you need them, it's an adapter test
- **Shared mutable state** between tests
- **`print()` assertions**: use proper `assert`
- **Skipped tests without reason**: `@pytest.mark.skip` must have `reason=`

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

## Running Tests

All test execution uses the canonical test runner script.
Agents must use `run_task` or `run_in_terminal` with `run-tests.ps1` / `run-tests.sh`.
See "Agent Test Execution" above for the full task table and rules.

```bash
# Via VS Code tasks (agents use run_task with these labels):
#   tests: domain               # Fast domain tests (~5s)
#   tests: all                  # Full suite (~20 min)
#   tests: domain + coverage    # Domain with coverage report

# Via terminal (for -Filter or -File):
.github/scripts/run-tests.ps1 -Scope domain -Filter "test_name"
.github/scripts/run-tests.ps1 -File tests/domain/test_helper.py
.github/scripts/run-tests.ps1 -Scope all -Coverage

# Mutation testing (manual only, not via task):
mutmut run --paths-to-mutate=<module> --tests-dir=tests/domain/
```

## pytest Configuration (pyproject.toml)

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
markers = [
    "slow: tests taking > 5 seconds",
    "property: hypothesis property-based tests",
]
addopts = "-ra --strict-markers"
```
