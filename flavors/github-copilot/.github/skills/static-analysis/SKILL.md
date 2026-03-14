---
name: static-analysis
description: Run and interpret static analysis tools — Ruff, mypy, Bandit, Radon. Covers configuration, complexity thresholds, editor integration, and failure handling.
argument-hint: '[module or package path] [tool: ruff|mypy|bandit|radon|all]'
disable-model-invocation: true
---

# Static Analysis Skill

Instructions for running, configuring, and interpreting static analysis tools.
Static analysis is the **first quality gate** — it runs before tests and
before review.

## When to Use

- Setting up or verifying quality gates on a project
- Before submitting code for review (pre-delivery checklist)
- Diagnosing lint, type, or security issues in changed files
- Establishing a metrics baseline

## Principles

- **Automate everything automatable** — rules enforceable by tools should
  never be debated in review
- **Fail fast** — static analysis runs before tests, before review
- **Zero-error baseline** — warnings may be allowed, errors block merge
- **Editor integration** — feedback in seconds, not after a CI run

## Tool Stack (Python)

| Tool | Purpose | Config Location |
|---|---|---|
| **Ruff** | Linting + formatting (replaces Flake8/isort/Black) | `pyproject.toml` `[tool.ruff]` |
| **mypy** / **Pyright** / **Pylance** | Type checking | `pyproject.toml` `[tool.mypy]` |
| **Bandit** | Security vulnerability detection | `.bandit` or CLI flags |
| **Radon** | Cyclomatic & cognitive complexity | CLI flags |

## Commands

### 1. Lint Check

```bash
# Full package
ruff check <package>/

# With statistics summary
ruff check <package>/ --statistics

# Auto-fix safe violations
ruff check <package>/ --fix

# Single file
ruff check <package>/module.py
```

### 2. Format Check

```bash
# Check only (CI mode)
ruff format --check <package>/

# Apply formatting
ruff format <package>/
```

### 3. Type Check

```bash
# mypy
mypy <package>/

# Single file
mypy <package>/module.py
```

In VS Code, Pylance provides real-time type checking. Use `pylanceSyntaxErrors`
or `pylanceFileSyntaxErrors` MCP tools for programmatic access.

### 4. Security Analysis

```bash
# Scan package (medium+ severity)
bandit -r <package>/ -ll

# Scan with specific tests
bandit -r <package>/ -t B101,B102,B105
```

| Bandit ID | Category | Example |
|---|---|---|
| B101 | assert used | `assert` in production code |
| B102 | exec used | `exec()` call |
| B105 | hardcoded password | `password = "secret"` |
| B608 | SQL injection | String concatenation in SQL |
| B602 | subprocess shell | `subprocess.call(shell=True)` |

### 5. Complexity Analysis

```bash
# All functions graded C or worse
radon cc <package>/ -a -s -n C

# All functions with grades
radon cc <package>/ -a -s
```

| Grade | Complexity | Limit |
|---|---|---|
| A | 1–5 | ✅ Always acceptable |
| B | 6–10 | ✅ Domain core maximum |
| C | 11–15 | ⚠️ Adapters only |
| D | 16–20 | ❌ Must refactor |
| F | 21+ | ❌ Immediate refactor |

### 6. Dead Code Detection

```bash
# Find unused code
vulture <package>/ --min-confidence 80
```

### Full Pipeline (CI Order)

```bash
ruff check <package>/ && \
ruff format --check <package>/ && \
mypy <package>/ && \
bandit -r <package>/ -ll && \
radon cc <package>/ -a -s -n D
```

## Quality Gates

| Gate | Threshold | Action on Failure |
|---|---|---|
| Lint errors | 0 | Block merge |
| Format compliance | 100% | Block merge |
| Type errors | 0 | Block merge |
| Security (high/critical) | 0 | Block merge |
| Cyclomatic complexity | ≤ 10 (domain), ≤ 15 (adapters) | Block merge |
| Dead code (new) | 0 | Flag for removal |

## Editor Integration

### VS Code (Recommended)

- **Ruff extension** — real-time lint + format on save
- **Pylance** — type checking, import resolution, symbol analysis
- **Python extension** — test runner, debugging

Settings in `.vscode/settings.json`:
```jsonc
{
  "python.analysis.typeCheckingMode": "basic",
  "[python]": {
    "editor.defaultFormatter": "charliermarsh.ruff",
    "editor.formatOnSave": true,
    "editor.codeActionsOnSave": {
      "source.fixAll.ruff": "explicit",
      "source.organizeImports.ruff": "explicit"
    }
  }
}
```

## Suppression Policy

Suppressions (`# noqa`, `# type: ignore`) are allowed only with justification:

```python
# Acceptable — documented reason
result = legacy_function()  # noqa: E501 — legacy API returns long string

# Unacceptable — no reason
result = legacy_function()  # noqa
```

**Rules:**
- Every suppression must include the specific rule code
- Every suppression must include a reason comment
- Suppressions are audited in code review
- Blanket `# type: ignore` without error code is not allowed

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Suppressing everything** | `# noqa` scattered everywhere | Require justification per suppression |
| **Warning fatigue** | Hundreds of warnings treated as noise | Start strict, fix all or reclassify |
| **Inconsistent config** | Each developer uses different rules | Commit config to repo, enforce in CI |
| **Running only in CI** | Slow feedback loop | Configure editor integration |
| **Outdated rules** | Old lint config misses modern patterns | Review rules quarterly |

## Governance References

- **R-SD-04** — Quality gates must be automated and verifiable
- **R-SD-05** — Auto-check as first step before semantic analysis
- **R-SD-11** — Security scanning (Bandit integration)
