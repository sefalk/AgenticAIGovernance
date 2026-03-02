---
category: code_quality
applies_to: [all]
complexity: foundational
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [code_review, refactoring, accessibility_testing, error_handling]
---
# Static Analysis

## Purpose

Static analysis examines source code without executing it to find bugs, enforce coding standards, detect security vulnerabilities, and measure complexity. It is the fastest and cheapest quality feedback loop. Invoke this skill when setting up automated quality gates for a project, defining Level-3 code quality workflows, or selecting tooling at Level 4.

## Principles

- **Automate everything automatable:** Every rule that can be checked by a machine should be. Human reviewers focus on design, logic, and semantics.
- **Fail fast:** Static analysis runs before tests, before review. It's the first quality gate.
- **Verifiability (AAIG L1):** Static analysis results are deterministic and programmatically verifiable.
- **Efficiency (AAIG L1):** Fast feedback. Developer sees issues in seconds, not after a CI run.

## Techniques & Patterns

### Tool Categories

| Category | What It Checks | Example Tools |
|----------|---------------|---------------|
| **Linters** | Style, conventions, common mistakes | ESLint, Pylint, golangci-lint, Clippy, RuboCop |
| **Formatters** | Code formatting consistency | Prettier, Black, gofmt, rustfmt, clang-format |
| **Type checkers** | Type correctness (for dynamic/gradually typed languages) | TypeScript, mypy, pyright, Flow |
| **Complexity analyzers** | Cyclomatic complexity, cognitive complexity, coupling | SonarQube, Radon (Python), complexity-report (JS) |
| **Dead code detectors** | Unused variables, imports, functions, files | Vulture (Python), ts-prune (TS), deadcode (Go) |
| **Security analyzers** | Vulnerabilities from code patterns | Semgrep, Bandit, gosec, SpotBugs (see security_testing.md) |

### Language-Specific Recommendations

#### Python
| Tool | Purpose | Config File |
|------|---------|-------------|
| **Ruff** | Linting + formatting (extremely fast, replaces Flake8/isort/Black) | `ruff.toml` or `pyproject.toml` |
| **mypy** / **pyright** | Type checking | `mypy.ini` or `pyproject.toml` |
| **Bandit** | Security analysis | `.bandit` |
| **Radon** | Complexity analysis | CLI flags |

**Recommended CI pipeline:** `ruff check . && ruff format --check . && mypy . && bandit -r src/`

#### JavaScript / TypeScript
| Tool | Purpose | Config File |
|------|---------|-------------|
| **ESLint** (v9+) | Linting | `eslint.config.js` (flat config) |
| **Prettier** | Formatting | `.prettierrc` |
| **TypeScript** (`tsc --noEmit`) | Type checking | `tsconfig.json` |
| **Biome** | All-in-one (lint + format, very fast) | `biome.json` |

**Recommended CI pipeline:** `eslint . && prettier --check . && tsc --noEmit`

#### Java / Kotlin
| Tool | Purpose | Config File |
|------|---------|-------------|
| **Checkstyle** | Style enforcement | `checkstyle.xml` |
| **SpotBugs** | Bug detection | Maven/Gradle plugin |
| **Error Prone** | Compile-time bug detection | Compiler plugin |
| **ktlint** | Kotlin style | `.editorconfig` |

#### Go
| Tool | Purpose | Config File |
|------|---------|-------------|
| **golangci-lint** | Meta-linter (runs 50+ linters) | `.golangci.yml` |
| **gofmt** / **goimports** | Formatting | N/A (built-in) |
| **go vet** | Suspicious constructs | N/A (built-in) |

**Recommended CI pipeline:** `golangci-lint run ./...`

#### Rust
| Tool | Purpose | Config File |
|------|---------|-------------|
| **Clippy** | Linting (500+ lints) | `clippy.toml` |
| **rustfmt** | Formatting | `rustfmt.toml` |

**Recommended CI pipeline:** `cargo clippy -- -D warnings && cargo fmt -- --check`

#### C# / .NET
| Tool | Purpose | Config File |
|------|---------|-------------|
| **Roslyn Analyzers** | Built-in analysis | `.editorconfig` |
| **StyleCop** | Style enforcement | `stylecop.json` |
| **dotnet format** | Formatting | `.editorconfig` |

### Complexity Metrics

| Metric | What It Measures | Threshold |
|--------|-----------------|-----------|
| **Cyclomatic complexity** | Number of independent paths through a function | <= 10 per function |
| **Cognitive complexity** | How hard a function is to understand (nesting, breaks in flow) | <= 15 per function |
| **Lines per function** | Raw size | <= 50 lines |
| **File length** | Module size | <= 500 lines |
| **Dependency count** | Coupling (imports per file) | <= 15 imports |

### Editor Integration

Static analysis should run in the editor (real-time feedback):
- **VS Code:** ESLint extension, Pylint/Ruff extension, Rust Analyzer.
- **JetBrains:** Built-in inspections, Checkstyle plugin, SonarLint plugin.
- **Neovim:** LSP + null-ls or none-ls for linting integration.

### CI Configuration

```yaml
# Example: Multi-language static analysis in GitHub Actions
static-analysis:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - name: Run Semgrep (multi-language security)
      uses: returntocorp/semgrep-action@v1
    - name: Run language-specific analysis
      run: |
        # Python
        ruff check . && mypy .
        # or JS/TS
        npx eslint . && npx tsc --noEmit
```

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Zero lint errors** | 0 errors | Warnings may be allowed, errors block merge. |
| **Formatting check** | 100% compliant | No manual formatting debates. Autoformat or fail. |
| **Type check pass** | 0 errors | For typed / gradually typed languages. |
| **Cyclomatic complexity** | <= 10 per function | Functions exceeding limit must be refactored or justified. |
| **No new dead code** | 0 new | Detected unused code must be removed. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Suppressing everything** | `# noqa`, `// eslint-disable` plastered everywhere. | Require justification for every suppression. Audit quarterly. |
| **Warning fatigue** | 500 warnings treated as background noise. | Start strict (errors, not warnings). Fix all warnings or reclassify. |
| **Inconsistent config** | Each developer uses different lint rules. | Commit config files to the repo. Enforce in CI. |
| **Running only in CI** | Developer doesn't see issues until CI fails (slow feedback). | Configure editor integration. Add pre-commit hooks. |
| **Outdated rules** | Using 5-year-old lint configs that don't cover modern patterns. | Review and update rules quarterly. Adopt new recommended rulesets. |


## See Also

- [Code Review](../code_quality/code_review.md)
- [Refactoring](../code_quality/refactoring.md)

## References

- Semgrep: https://semgrep.dev/
- ESLint: https://eslint.org/
- Ruff: https://docs.astral.sh/ruff/
- golangci-lint: https://golangci-lint.run/
- SonarQube: https://www.sonarsource.com/products/sonarqube/
