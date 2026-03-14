---
name: unit-testing
description: Verify correctness of individual units of code in isolation. AAA pattern, test doubles, language-specific guidance, edge cases, and quality gates for coverage and mutation score.
argument-hint: '[function or module to test] [language]'
---

# Unit Testing

## When to Use

- When a project requires automated testing at the unit level
- When defining test quality gates (coverage, mutation score)
- When choosing test doubles strategy (mocks, stubs, fakes)
- When establishing test organization conventions

## Principles

1. **Isolation** — Each test verifies exactly one unit. External
   dependencies are replaced with test doubles.
2. **Determinism** — A unit test must produce the same result every time.
   Flaky tests are treated as bugs.
3. **Speed** — The full unit test suite should run in seconds. Tests
   requiring network or disk I/O are integration tests.
4. **Traceability** — Every test must be traceable to a requirement or
   behavioral expectation. Tests without a clear "why" are noise.
5. **Proof of Failure (TDD)** — A test must be observed failing before
   the implementation makes it pass. Tests that pass immediately without
   verifying the Red phase risk being vacuous.

## Techniques & Patterns

### The AAA Pattern (Arrange-Act-Assert)

```
Arrange  →  Set up the unit, its inputs, and test doubles.
Act      →  Invoke the behavior under test (one call).
Assert   →  Verify the outcome matches expectations.
```

**Rules:**
- One logical assertion per test.
- No logic in tests (`if`, `for`, `try/catch`). Tests are linear scripts.
- Descriptive names: `test_withdraw_insufficient_funds_raises_error`.

### Test Doubles

| Double | Purpose | When to Use |
|--------|---------|-------------|
| **Stub** | Returns pre-configured responses | Control indirect inputs |
| **Mock** | Verifies interactions | Behavior matters, not result |
| **Fake** | Working implementation with shortcuts | Stub too simple, real dep too heavy |
| **Spy** | Records calls, delegates to real impl | Observe without replacing |

**Best practices:**
- Prefer stubs over mocks — test *outcomes*, not implementation details.
- Do not mock what you don't own. Wrap third-party APIs behind your own
  interface.
- Use dependency injection to make units testable.

### Test Organization

```
src/
  payments/
    payment_processor.py
tests/
  payments/
    test_payment_processor.py
    conftest.py
  conftest.py
```

Mirror source structure. One test file per source file. Group tests by
behavior, not by method.

### Language-Specific Guidance

| Language | Framework | Mocking | Notes |
|----------|-----------|---------|-------|
| **Python** | pytest | `unittest.mock` / `pytest-mock` | `pytest.mark.parametrize` for data-driven |
| **JavaScript** | vitest / jest | `vi.mock()` / `jest.mock()` | Always `await` async in tests |
| **Java** | JUnit 5 | Mockito | AssertJ for fluent assertions |
| **C#** | xUnit | Moq / NSubstitute | `[Theory]` + `[InlineData]` |
| **Go** | `testing` | gomock / hand-written fakes | Table-driven subtests |
| **Rust** | `#[cfg(test)]` | `mockall` | Tests in same file, `mod tests` |

### Edge Cases & Boundaries

Every suite should cover:
- **Happy path:** Expected inputs → correct output.
- **Boundary values:** Empty, zero, max, null/None, single-element.
- **Error paths:** Invalid inputs → correct error (not crash, not silence).
- **State transitions:** All valid + at least one invalid.

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Line coverage** | ≥ 80% | `pytest-cov`, `c8`, `JaCoCo` |
| **Branch coverage** | ≥ 70% | More meaningful than line coverage |
| **Mutation score** | ≥ 60% | See mutation-testing skill |
| **Zero flaky tests** | 0 | Flaky = bug |
| **Execution time** | < 60s (full suite) | Slow tests signal hidden integration deps |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Testing implementation** | Tests break on every refactor. | Assert on outputs and side effects. |
| **The Giant Test** | 15 assertions, 5 behaviors in one test. | Split into one-behavior-per-test. |
| **Excessive mocking** | Every dep mocked; tests verify nothing real. | Use fakes; reduce dep count via design. |
| **Mystery Guest** | Tests depend on external data/global state. | Inline test data or use explicit fixtures. |
| **Conditional test logic** | `if/else` in tests. | Separate into distinct test cases. |
| **Ignoring/skipping tests** | `@skip` used permanently. | Fix or delete. Skipped tests are dead code. |
| **Hard-coded magic values** | `assert result == 42` with no explanation. | Named constants or inline comments. |

## References

- Gerard Meszaros, *xUnit Test Patterns* (2007)
- Martin Fowler, ["Mocks Aren't Stubs"](https://martinfowler.com/articles/mocksArentStubs.html)
- Kent Beck, *Test-Driven Development: By Example* (2002)
- pytest: https://docs.pytest.org/
