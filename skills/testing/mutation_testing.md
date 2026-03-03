---
category: testing
applies_to: [all]
complexity: intermediate
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [unit_testing, property_based_testing]
---
# Mutation Testing

## Purpose

Mutation testing evaluates the **effectiveness** of a test suite by introducing small, systematic changes (mutations) to the source code and checking whether the test suite detects them. A mutation that survives (tests still pass) reveals a gap in test coverage -- not in lines covered, but in faults detected. Invoke this skill when line/branch coverage alone is insufficient to guarantee test suite quality, or when defining Level-3/4 quality gates for test effectiveness.

## Principles

- **Coverage is necessary but not sufficient:** 100% line coverage does not mean the tests catch bugs. Mutation testing measures test *strength*, not just test *reach*.
- **Agentic Hallucination Defense:** Autonomous agents are prone to writing "sham tests" that achieve 100% line coverage but mock out the core logic (testing nothing). Mutation testing mathematically breaks the code to prove the agent's tests actually assert behavior.
- **Verifiability (AAIG L1):** Mutation scores provide a programmatically measurable quality gate that complements coverage metrics.
- **Efficiency (AAIG L1):** Mutation testing is computationally expensive. Apply it strategically -- target critical code paths and business logic, not boilerplate or generated code.

## Techniques & Patterns

### How Mutation Testing Works

```
1. Parse the source code.
2. Apply a mutation operator (e.g., replace `>` with `>=`).
3. Run the test suite against the mutated code.
4. Classify the result:
   - KILLED: At least one test failed. The test suite detected the fault. Good.
   - SURVIVED: All tests passed. The test suite missed the fault. Gap found.
   - TIMED OUT: The mutation caused an infinite loop. Typically counted as killed.
   - NO COVERAGE: No test executes the mutated line. A coverage gap.
```

### Mutation Operators

Mutation operators are the atomic transformations applied to source code. State-of-the-art tools implement the following categories:

| Category | Operators | Example |
|----------|-----------|---------|
| **Arithmetic** | Replace `+` with `-`, `*` with `/`, etc. | `a + b` --> `a - b` |
| **Relational** | Replace `>` with `>=`, `==` with `!=`, etc. | `if (x > 0)` --> `if (x >= 0)` |
| **Logical** | Replace `&&` with `\|\|`, negate conditions | `a && b` --> `a \|\| b` |
| **Literal** | Replace constants: `0` --> `1`, `true` --> `false`, `""` --> `"x"` | `return 0` --> `return 1` |
| **Statement** | Remove statements, remove `else` blocks, remove method calls | Delete `list.add(item)` |
| **Return value** | Replace return values with defaults (`null`, `0`, `""`, `empty`) | `return result` --> `return null` |
| **Void method call** | Remove calls to void methods | Delete `logger.info(msg)` |
| **Unary** | Remove negation, increment/decrement mutation | `!condition` --> `condition` |
| **Exception** | Remove `throw`, change exception types | `throw new X()` --> (removed) |

### Interpreting Results

**Mutation Score** = (Killed Mutants + Timed Out) / (Total Mutants - No Coverage)

| Score Range | Interpretation | Action |
|-------------|---------------|--------|
| >= 85% | Excellent | Test suite is strong. Focus on surviving mutants in critical code. |
| 70% -- 84% | Good | Address surviving mutants in business-critical paths. |
| 50% -- 69% | Moderate | Significant gaps. Prioritize writing fault-detecting tests. |
| < 50% | Weak | The test suite provides false confidence. Major improvement needed. |

**Analyzing surviving mutants:**
1. **Is the mutant equivalent?** Some mutations produce functionally identical code (e.g., mutating dead code). These are false positives. Mark them as ignored.
2. **Is the assertion weak?** The test covers the line but doesn't assert the specific behavior the mutation changes. Strengthen the assertion.
3. **Is a test case missing?** No test exercises the scenario the mutation would break. Write a new test.
4. **Is the code itself problematic?** Sometimes a surviving mutant reveals code that is overly complex or has redundant logic. Consider refactoring.

### Strategic Application

Mutation testing is computationally expensive (O(mutants x test-suite-time)). Apply it strategically:

- **Target high-value code:** Business logic, financial calculations, security checks, data validation, algorithms. Not: UI glue code, configuration, logging.
- **Incremental analysis:** Run mutation testing only on changed files (differential mode). Most tools support this.
- **Sampling:** For large codebases, use statistical sampling (e.g., 20% of mutants) to estimate the mutation score without full enumeration.
- **CI integration:** Run mutation testing as a nightly or weekly CI job, not on every commit (too slow). Use it as a quality gate for releases.

### Language-Specific Tooling

#### Python
- **Tool:** `mutmut` (recommended) or `cosmic-ray`.
- **Usage:** `mutmut run --paths-to-mutate=src/` then `mutmut results`. Cache is stored in `.mutmut-cache`.
- **Tip:** Use `mutmut run --tests-dir=tests/ --runner="pytest -x --tb=short"` for faster runs (`-x` = fail fast).

#### JavaScript / TypeScript
- **Tool:** `Stryker Mutator` (the standard).
- **Usage:** `npx stryker run`. Configure via `stryker.config.json` or `stryker.config.mjs`.
- **Tip:** Use `--mutate='src/**/*.ts'` and `--ignorePatterns='**/*.spec.ts'` to target correctly.
- **Tip:** Enable `--incremental` for differential mode on CI.

#### Java / Kotlin
- **Tool:** `PIT` (pitest) -- the most mature JVM mutation testing tool.
- **Usage:** Maven plugin (`pitest-maven`) or Gradle plugin. Produces HTML reports.
- **Tip:** Use `targetClasses` and `targetTests` to scope the analysis. Enable `withHistory` for incremental runs.
- **Tip:** For Kotlin, use `pitest` with the `pitest-kotlin` plugin for Kotlin-specific mutation operators.

#### C# / .NET
- **Tool:** `Stryker.NET`.
- **Usage:** `dotnet stryker` in the test project directory. Configure via `stryker-config.json`.
- **Tip:** Use `--mutation-level` (Basic, Standard, Advanced, Complete) to control operator breadth.

#### Go
- **Tool:** `go-mutesting` or `gremlins`.
- **Usage:** `go-mutesting ./...`. Reports surviving mutants per file.
- **Note:** Go mutation testing tooling is less mature than other ecosystems. Consider supplementing with property-based testing (see `property_based_testing.md`).

#### Rust
- **Tool:** `cargo-mutants`.
- **Usage:** `cargo mutants --jobs 4`. Uses `cargo test` under the hood.
- **Tip:** Use `--file` to scope to specific modules. Combine with `--timeout-multiplier` to handle long-running mutants.

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Mutation score** | >= 60% | Across targeted code. May be tightened to 75%+ at Level 4 for critical systems. |
| **No surviving mutants in critical paths** | 0 survivors | For code explicitly tagged as critical (e.g., `@Critical`, `# CRITICAL`). |
| **Equivalent mutant review** | All reviewed | Surviving mutants must be either fixed (test added) or marked equivalent with justification. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Mutating everything** | Running mutation testing on the entire codebase including boilerplate, config, and generated code. Wastes compute. | Scope to business logic and critical paths. |
| **Ignoring survivors** | Running mutation testing for the score number, then ignoring surviving mutants. | Analyze every survivor: fix the test, mark as equivalent, or refactor the code. |
| **Chasing 100%** | Trying to kill every mutant, including equivalent mutants and trivial cases. | Accept that some mutants are unkillable (equivalent) or low-value. Target critical code. |
| **Running on every commit** | Mutation testing on every CI push slows the pipeline to a crawl. | Run differential on PRs, full on nightly/weekly. |
| **Weak-assertion blindness** | High mutation score from tests that assert `!= null` instead of asserting actual values. | Review assertion quality, not just mutation score. |


## See Also

- [Unit Testing](../testing/unit_testing.md)
- [Property-Based Testing](../testing/property_based_testing.md)

## References

- R.A. DeMillo, R.J. Lipton, F.G. Sayward, "Hints on Test Data Selection: Help for the Practicing Programmer" (1978) -- seminal paper on mutation testing.
- Mike Papadakis et al., "Mutation Testing Advances: An Analysis and Survey" (2019) -- comprehensive survey of the field.
- Stryker Mutator: https://stryker-mutator.io/
- PIT (pitest): https://pitest.org/
- mutmut: https://mutmut.readthedocs.io/
- cargo-mutants: https://github.com/sourcefrog/cargo-mutants
