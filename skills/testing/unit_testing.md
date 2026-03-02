---
category: testing
applies_to: [all]
complexity: foundational
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [integration_testing, mutation_testing, property_based_testing, snapshot_testing]
---
# Unit Testing

## Purpose

Unit testing verifies the correctness of individual units of code (functions, methods, classes) in isolation from their dependencies. It is the foundation of a reliable test suite: fast, deterministic, and highly localized. Invoke this skill when a project requires automated testing at the unit level, or when defining Level-3 testing workflows or Level-4 quality gate thresholds.

## Principles

- **Isolation:** Each test verifies exactly one unit. External dependencies (databases, APIs, file systems, clocks) are replaced with test doubles.
- **Determinism:** A unit test must produce the same result every time, regardless of execution order, system state, or environment. Flaky tests are treated as bugs.
- **Speed:** The full unit test suite should run in seconds, not minutes. Tests that require network calls, disk I/O, or heavy setup are integration tests, not unit tests.
- **Traceability (AAIG L1):** Every test must be traceable to a requirement, specification, or behavioral expectation. Tests without a clear "why" are noise, not safety.
- **Verifiability (AAIG L1):** Test results must be programmatically verifiable -- pass/fail with clear failure messages, not manual inspection.

## Techniques & Patterns

### The AAA Pattern (Arrange-Act-Assert)

Every unit test follows three phases:

```
Arrange  -->  Set up the unit under test, its inputs, and any test doubles.
Act      -->  Invoke the behavior being tested (typically one method/function call).
Assert   -->  Verify the outcome matches the expected result.
```

**Rules:**
- One logical assertion per test (multiple `assert` calls are acceptable if they verify one behavior).
- No logic in tests (no `if`, `for`, `try/catch` in test code). Tests are linear scripts.
- The test name describes the scenario and expected outcome: `test_withdraw_insufficient_funds_raises_error`, not `test_withdraw_3`.

### Test Doubles (Mocks, Stubs, Fakes, Spies)

| Double | Purpose | When to Use |
|--------|---------|-------------|
| **Stub** | Returns pre-configured responses | When you need to control indirect inputs |
| **Mock** | Verifies interactions (method calls, arguments) | When the *behavior* (not the result) is what matters |
| **Fake** | Working implementation with shortcuts (e.g., in-memory DB) | When a stub is too simple but a real dependency is too heavy |
| **Spy** | Records calls for later assertion, delegates to real implementation | When you want to observe without fully replacing |

**Best practices:**
- Prefer stubs over mocks. Test *outcomes*, not *implementation details*. Mocks create coupling to internals.
- Do not mock what you don't own. Wrap third-party APIs behind your own interface, then stub/mock the interface.
- Use dependency injection to make units testable. If you can't inject a dependency, the design needs refactoring.

### Test Organization

```
src/
  payments/
    payment_processor.py
tests/
  payments/
    test_payment_processor.py          # mirrors source structure
    conftest.py / fixtures.py          # shared fixtures for this module
  conftest.py                          # global fixtures
```

- Mirror the source directory structure in the test directory.
- One test file per source file, named `test_<source_file>` (or `<source_file>_test` per language convention).
- Group tests by behavior, not by method. A method with 5 behaviors gets 5 tests, not 1.

### Language-Specific Guidance

#### Python
- **Framework:** `pytest` (preferred over `unittest`). Use `pytest.mark.parametrize` for data-driven tests.
- **Mocking:** `unittest.mock.patch` / `pytest-mock`. Patch at the call site, not the definition site.
- **Fixtures:** Use `pytest` fixtures with appropriate scope (`function`, `module`, `session`).

#### JavaScript / TypeScript
- **Framework:** `vitest` (preferred for Vite projects), `jest` otherwise. Use `describe`/`it` blocks.
- **Mocking:** `vi.mock()` / `jest.mock()` for module mocks. `vi.fn()` / `jest.fn()` for function spies.
- **Async:** Always `await` async operations in tests. Use `vi.useFakeTimers()` for time-dependent code.

#### Java / Kotlin
- **Framework:** JUnit 5. Use `@ParameterizedTest` with `@MethodSource` or `@CsvSource`.
- **Mocking:** Mockito. Use `@ExtendWith(MockitoExtension.class)` and `@Mock` / `@InjectMocks`.
- **Assertions:** AssertJ (fluent assertions) preferred over JUnit's built-in `assertEquals`.

#### C# / .NET
- **Framework:** xUnit (preferred), NUnit, or MSTest. Use `[Theory]` with `[InlineData]` for parameterized tests.
- **Mocking:** Moq or NSubstitute. Use constructor injection.
- **Assertions:** FluentAssertions for readable assertion chains.

#### Go
- **Framework:** Built-in `testing` package. Use `t.Run()` for subtests, table-driven test pattern.
- **Mocking:** `gomock` or hand-written fakes (idiomatic Go prefers interfaces + fakes over mocking frameworks).
- **Assertions:** `testify/assert` or `testify/require` for readable assertions.

#### Rust
- **Framework:** Built-in `#[cfg(test)]` module. Use `#[test]` attribute.
- **Mocking:** `mockall` crate. Define traits for external interfaces.
- **Organization:** Unit tests live in the same file as the source code, inside a `mod tests` block.

### Edge Cases & Boundary Testing

Every unit test suite should cover:

- **Happy path:** Normal/expected inputs produce correct output.
- **Boundary values:** Empty collections, zero, max int, empty string, null/None, single-element inputs.
- **Error paths:** Invalid inputs produce the correct error (not a crash, not silence).
- **State transitions:** If the unit has state, test all valid transitions and at least one invalid transition.

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Line coverage** | >= 80% | Measured via language-native coverage tools (e.g., `pytest-cov`, `c8`, `JaCoCo`). May be tightened at Level 4. |
| **Branch coverage** | >= 70% | More meaningful than line coverage for conditional logic. |
| **Mutation score** | >= 60% | See `mutation_testing.md` skill. Ensures tests actually detect faults. |
| **Zero flaky tests** | 0 flaky | Any test that passes/fails non-deterministically is a bug. |
| **Execution time** | < 60s (full suite) | Unit tests must be fast. Slow tests indicate hidden integration dependencies. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Testing implementation, not behavior** | Tests break on every refactor even though behavior is unchanged. | Assert on outputs and side effects, not internal method calls. |
| **The Giant Test** | One test with 15 assertions testing 5 behaviors. | Split into separate tests, one behavior each. |
| **Test-to-code coupling** | Test mirrors the source code line-by-line. | Write tests from the specification, not the code. |
| **Excessive mocking** | Every dependency is mocked; tests verify nothing real. | Use fakes for complex dependencies, reduce dependency count via design. |
| **Mystery Guest** | Tests depend on external data files or global state with no visible setup. | Inline test data or use explicit fixtures. |
| **Conditional test logic** | `if/else` in tests. | Separate into distinct test cases. |
| **Ignoring/skipping tests** | `@skip` / `xit` used permanently. | Fix or delete. Skipped tests are dead code. |
| **Hard-coded magic values** | `assert result == 42` with no explanation. | Use named constants or inline comments explaining expected values. |


## See Also

- [Integration Testing](../testing/integration_testing.md)
- [Mutation Testing](../testing/mutation_testing.md)
- [Property-Based Testing](../testing/property_based_testing.md)
- [Snapshot Testing](../testing/snapshot_testing.md)

## References

- Gerard Meszaros, *xUnit Test Patterns* (2007) -- canonical reference for test doubles and test organization.
- Martin Fowler, ["Mocks Aren't Stubs"](https://martinfowler.com/articles/mocksArentStubs.html) -- foundational distinction between test double types.
- Kent Beck, *Test-Driven Development: By Example* (2002) -- the original TDD methodology.
- `pytest` documentation: https://docs.pytest.org/
- `vitest` documentation: https://vitest.dev/
- JUnit 5 user guide: https://junit.org/junit5/docs/current/user-guide/
