---
name: code-review
description: Structured code review guidance for the code-critic agent. Diff analysis, blast radius, automation-first review, anti-pattern detection, and review artifact templates.
argument-hint: '[file or PR to review] [focus: architecture|security|quality|all]'
disable-model-invocation: true
---

# Code Review Skill

Guidance for performing rigorous, systematic code reviews. This skill
is consumed by the **code-critic** agent and referenced by the coordinator
when requesting reviews.

## When to Use

- After the implementer delivers code changes
- After the refactorer completes restructuring
- When the coordinator requests a targeted review of specific files

## Principles

1. **Automation over Opinions** — formatting, linting, and basic security
   checks must be automated (Ruff, Pylance, Bandit). Do not spend tokens
   debating style that tools can enforce.
2. **Review the Diff, Not Just the Code** — assess the *delta*. Verify it
   solves the stated objective and doesn't introduce regressions in
   unmodified files.
3. **Architectural Compliance** — changes must respect the dependency rule,
   hexagonal architecture, and existing ADRs. New dependencies or structural
   changes require an ADR.
4. **Test Corroboration** — code that introduces new logic but zero new tests
   is incomplete by default.

## Review Procedure

### Phase 1: Automated Gates (Before Semantic Review)

Run these checks first. If any fail, the review stops:

```bash
# Lint + format
ruff check <package>/ --statistics
ruff format --check <package>/

# Type checking
# Use Pylance or: mypy <package>/

# Security scan
bandit -r <package>/ -ll

# Tests
pytest tests/ -x -q
```

| Gate | Must Pass | Notes |
|---|---|---|
| Ruff lint (errors) | 0 errors | Warnings are acceptable |
| Format check | 100% | Automated, not debatable |
| Type check | 0 errors | New code must have type hints |
| Security scan | 0 high/critical | Blocks review immediately |
| Tests | All passing | Red tests = no review |

### Phase 2: Diff Analysis

1. **Scope** — list all modified/created/deleted files
2. **Blast radius** — trace which modules import from changed files:
   ```bash
   grep -rn "from <changed_module> import\|import <changed_module>" <package>/
   ```
3. **Downstream impact** — verify downstream modules are covered by
   the test suite
4. **ADDED vs CHANGED** — new files get full review; changed files focus
   on the delta

### Phase 3: Architecture Check

Verify against these rules:

| Rule | Check |
|---|---|
| Domain purity | No runtime I/O imports in domain core modules |
| Dependency rule | Inward-only (adapters → domain, not reverse) |
| No logic in adapters | Adapters only wrap I/O calls |
| Injection | Orchestrators inject dependencies, no global singletons |
| ADR compliance | New deps or structure changes have a matching ADR |

### Phase 4: Code Quality

| Item | What to Check |
|---|---|
| **Naming** | `snake_case` functions/vars, `PascalCase` classes, `UPPER_CASE` constants |
| **Type hints** | All public function signatures (params + return) |
| **Docstrings** | All public functions, NumPy-style |
| **Complexity** | ≤ 10 cyclomatic (domain), ≤ 15 (adapters) |
| **Provenance markers** | `copilot:generated` on new files, `copilot:modified` on substantial changes |
| **Error handling** | Specific exceptions, no bare `except:` |

### Phase 5: Security Review

| Check | What to Look For |
|---|---|
| Secrets | Hardcoded passwords, API keys, tokens, connection strings |
| Injection | String concatenation for SQL, `eval()`/`exec()` on external input |
| Input validation | User data validated at system boundaries |
| Dependencies | New packages flagged via `pip-audit` for known CVEs |

A critical security finding → **REJECT**, regardless of all other results.

### Phase 6: Anti-Gaming Detection

| Pattern | Description | Verdict |
|---|---|---|
| Trivial tests | `assert True`, `assert 1 == 1` | REJECT |
| Vacuous assertions | Negative check whose subject can be empty or `None` — it passes when the code produced nothing | REJECT |
| Coverage padding | Function called but result not asserted | REJECT |
| Dead code | Unreachable branches or unused functions | Flag |
| Artificial splits | One function split into always-called-together parts | Flag |

## Anti-Patterns in Reviews

| Anti-Pattern | Problem | Better |
|---|---|---|
| **Rubber stamping** | Approving because syntax is valid | Check architecture, tests, security |
| **"LGTM" reviews** | Zero actionable feedback, no audit trail | Every review includes structured checklist |
| **Reviewing 1000+ lines** | Exhausts context, misses issues | Reject PRs exceeding 500 lines of logic |
| **Arguing over formatting** | Wastes tokens on enforceable rules | Fail in the pipeline, not in review |
| **Re-reviewing passing gates** | Manually checking what tools already verified | Trust automated gates, focus on semantics |

## Review Verdict Template

```markdown
## Code Review Verdict: {APPROVED | REJECTED | ESCALATE}

### Summary
{1–3 sentence overview}

### Automated Gates
- [x] Lint: 0 errors
- [x] Format: compliant
- [x] Type check: clean
- [x] Tests: all pass

### Architecture & Quality
- [x] Domain core purity
- [x] Dependency rule respected
- [x] Type hints complete
- [x] Complexity within limits

### Security
- [x] No secrets in code
- [x] No vulnerable dependencies
- [x] Input validation at boundaries

### Metrics
- Line coverage: {X}% (threshold: {Y}%)
- Branch coverage: {X}% (threshold: {Y}%)

### Issues Found (if REJECTED)
1. **{file}:{line}** — {description}
   - Severity: {Critical | High | Medium | Low}
   - Suggested fix: {guidance}
```

## Governance References

- **R-SD-01** — Maker-Checker: code-critic reviews implementer output
- **R-SD-04** — Quality gates must be automated and verifiable
- **R-SD-05** — Auto-check before semantic review
- **R-SD-11/12/13** — Security checks (secrets, CVEs, injection)
