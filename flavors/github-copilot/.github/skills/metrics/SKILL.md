---
name: metrics
description: Collect and report code quality metrics — coverage, complexity, mutation score, lint violations. Use when validating quality gates or producing metrics snapshots.
argument-hint: '[module or package path] [metric type: coverage|complexity|lint|mutation]'
disable-model-invocation: true
---

# Metrics Collection Skill

Instructions for collecting, interpreting, and reporting code quality metrics.

## When to Use

- Validating quality gate thresholds after implementation
- Producing a metrics snapshot for a handoff log
- Comparing before/after metrics for a change

## Metric Collection Commands

### 1. Test Coverage (Line + Branch)

```bash
pytest tests/ --cov=<package> --cov-report=term-missing --cov-branch -q
```

Per-module:
```bash
pytest tests/domain/ --cov=<package>/<module> --cov-report=term-missing --cov-branch -q
```

HTML report:
```bash
pytest tests/ --cov=<package> --cov-report=html --cov-branch
```

### 2. Cyclomatic Complexity

```bash
radon cc <package>/ -a -s -n C
```

| Grade | Complexity | Interpretation |
|---|---|---|
| A | 1–5 | Simple, low risk |
| B | 6–10 | Moderate, acceptable for domain core |
| C | 11–15 | Complex, acceptable only for adapters |
| D | 16–20 | Too complex, must refactor |
| F | 21+ | Untestable, immediate refactor |

### 3. Lint Violations

```bash
ruff check <package>/ --statistics
```

### 4. Type Annotation Coverage

Use Pylance's `source.addTypeAnnotation` in `edits` mode. If the result
contains edits, there are unannotated functions.

### 5. Mutation Testing (Final Quality Gate Only)

**Warning:** Computationally expensive. Never in the inner development loop.

```bash
# Single module (recommended)
mutmut run --paths-to-mutate=<module> --tests-dir=tests/domain/ --runner="pytest tests/domain/test_<module>.py -x -q"

# View results
mutmut results

# Inspect surviving mutants
mutmut show <mutant-id>
```

| Status | Meaning |
|---|---|
| Killed | Test caught the mutation ✅ |
| Survived | Test missed the mutation ❌ |
| Timeout | Infinite loop (counted as killed) |

**Mutation score** = killed / (killed + survived) × 100%

### Analysing Surviving Mutants

| Category | Meaning | Action |
|---|---|---|
| Missing test | No test covers this behaviour | Write a new targeted test |
| Weak assertion | Test runs code but doesn't check result | Strengthen the assertion |
| Equivalent mutant | Mutation produces identical behaviour | Mark as equivalent |
| Dead code | Mutated code is unreachable | Remove dead code |

### 6. Test-to-Code Ratio

```powershell
# Production code lines (PowerShell)
(Get-ChildItem <package> -Recurse -Filter *.py | Get-Content | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' }).Count

# Test code lines
(Get-ChildItem tests -Recurse -Filter *.py | Get-Content | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' }).Count
```

```bash
# Linux/macOS
find <package>/ -name "*.py" | xargs cat | grep -v "^\s*$" | grep -v "^\s*#" | wc -l
find tests/ -name "*.py" | xargs cat | grep -v "^\s*$" | grep -v "^\s*#" | wc -l
```

## Quality Gate Thresholds

| Module Type | Line Cov | Branch Cov | Mutation | Max Complexity | Test:Code |
|---|---|---|---|---|---|
| Domain core | ≥ 90% | ≥ 85% | ≥ 80% | ≤ 10 | ≥ 1.5:1 |
| Ports | ≥ 80% | ≥ 75% | ≥ 70% | ≤ 5 | ≥ 1.0:1 |
| Adapters | ≥ 60% | ≥ 50% | N/A | ≤ 15 | ≥ 0.5:1 |
| Utilities | ≥ 85% | ≥ 80% | ≥ 75% | ≤ 8 | ≥ 1.2:1 |

### Delta Thresholds

| Metric | Requirement |
|---|---|
| Coverage delta | ≥ 0 (no regression) |
| Mutation score delta | ≥ 0 (no regression) |
| Lint violation delta | ≤ 0 (no new violations) |
| Complexity delta | ≤ 0 for refactoring tasks |
