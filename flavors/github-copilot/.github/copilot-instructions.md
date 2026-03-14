# Project Instructions for Copilot

> These instructions apply to **all** chat requests in this workspace.
> Customise the TODO sections for your project.

## Project Overview

<!-- TODO: Replace with your project description -->

- **Project name:** YOUR_PROJECT_NAME
- **Tech stack:** Python 3.10+, TODO: add your frameworks
- **Repo:** TODO: add your repo URL

## Repository Structure

<!-- TODO: Replace with your actual structure -->

```
src/              # Source code
  domain/         # Pure business logic (no I/O)
  ports/          # Protocol interfaces
  adapters/       # I/O implementations
tests/            # Test suite
  domain/         # Domain core tests (no external deps)
  adapters/       # Adapter tests (may use external deps)
  properties/     # Property-based tests (hypothesis)
  contracts/      # Port-adapter contract tests
docs/             # Documentation
  adrs/           # Architecture Decision Records
.github/          # Copilot agents, instructions, logs
```

## Governing Manifest

All agents follow the principles in [MANIFEST.md](MANIFEST.md):

1. **Test-Driven Development** — Red → Green → Refactor as separate steps
2. **Layered Architecture** — domain core has no I/O dependencies
3. **Maker-Checker** — every output is reviewed by a critic agent
4. **Metrics as Proof** — coverage, complexity, lint are quality gates
5. **Traceability** — provenance markers + workflow logs
6. **Human-in-the-Loop** — agents escalate, humans decide

## Coding Standards

### Naming Conventions

- Functions and variables: `snake_case`
- Classes: `PascalCase`
- Constants: `UPPER_CASE`
- Private/internal: prefix with `_`

### Code Style

- Python 3.10+ features allowed (`X | None`, match statements)
- Type hints on **all** function signatures
- Docstrings on all public functions (NumPy-style)
- No wildcard imports (`from module import *`)
- Use `from __future__ import annotations` for forward references
- Use **Pydantic `BaseModel`** for domain models, value objects, and DTOs;
  use `dataclass` only for simple internal data carriers with no validation

### Error Handling

- Raise specific exceptions, never bare `except:`
- Domain core raises domain-specific exceptions
- Adapters catch infrastructure exceptions and translate

### Git Conventions

- Agent branches: `agent/{workflow-id}`
- Agent commits: `[agent:{agent-name}] {action summary}`
- Human commits: conventional commits format

## What NOT to Do

<!-- TODO: Customise these for your project -->

- Do **not** introduce module-level side effects (no code that runs at import)
- Do **not** put business logic in adapters or orchestrators
- Do **not** write tests that depend on external services for domain logic
- Do **not** create trivial tests (`assert True`, coverage padding)

## Available Skills

Skills provide domain-specific guidance. Agents should consult relevant
skills when their task falls within the skill's scope.

> Canonical source: `skills/INDEX.md` — consult it for descriptions
> and the full agent-skill matrix.

| Skill | Directory | Primary Consumer |
|---|---|---|
| **code-review** | `skills/code-review/` | test-critic, code-critic |
| **dependency-management** | `skills/dependency-management/` | implementer, code-critic |
| **design-patterns** | `skills/design-patterns/` | planner, implementer, refactorer, arbiter |
| **documentation** | `skills/documentation/` | documenter |
| **error-handling** | `skills/error-handling/` | test-writer, implementer |
| **hexagonal-architecture** | `skills/hexagonal-architecture/` | implementer, refactorer, code-critic, arbiter |
| **human-escalation** | `skills/human-escalation/` | test-writer, implementer, refactorer, arbiter |
| **metrics** | `skills/metrics/` | code-critic |
| **property-testing** | `skills/property-testing/` | test-writer, test-critic |
| **pydantic** | `skills/pydantic/` | implementer, refactorer |
| **refactoring** | `skills/refactoring/` | refactorer |
| **risk-management** | `skills/risk-management/` | planner |
| **secure-coding** | `skills/secure-coding/` | code-critic |
| **static-analysis** | `skills/static-analysis/` | implementer, code-critic |
| **task-decomposition** | `skills/task-decomposition/` | planner |
| **unit-testing** | `skills/unit-testing/` | test-writer, test-critic |

## Pre-Delivery Checklist (Mandatory)

> Every agent must verify these before presenting code to the human.

### For any code change:

- [ ] **Variable/import check:** Every name referenced is defined or imported.
- [ ] **No regressions:** Existing tests still pass.
- [ ] **Provenance marker:** New files have `copilot:generated` header;
      substantially modified functions have `copilot:modified` note.

### For new features or refactoring:

- [ ] **Tests exist:** Code is accompanied by tests.
- [ ] **Architecture check:** New code follows the dependency rule.

### When skipping items:

- State: "⚠️ Skipping [item] because [reason]. Backfill required."
