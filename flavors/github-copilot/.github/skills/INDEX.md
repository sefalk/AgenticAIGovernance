# Skill Index

> Auto-generated index of all AF skills. Use `/find-skill <topic>` to search.
> Regenerate with `/validate-framework` (step 7 — skill directory structure).

| # | Skill | Description | Referenced by |
|---|-------|-------------|---------------|
## Active Skills (referenced by ≥1 agent)

| # | Skill | Description | Referenced by |
|---|-------|-------------|---------------|
| 1 | `code-review` | Structured code review guidance. Diff analysis, blast radius, automation-first review, anti-pattern detection, and review artifact templates. | test-critic, code-critic |
| 2 | `dependency-management` | Dependency selection, version pinning, lockfiles, vulnerability scanning, and license compliance. | implementer, code-critic |
| 3 | `design-patterns` | Proven design patterns — creational, structural, behavioural, DDD, architecture. When to use, when NOT to use, and Python-idiomatic examples. | planner, implementer, refactorer, arbiter |
| 4 | `documentation` | Documentation standards — code comments, docstrings, READMEs, ADRs, changelogs. | documenter |
| 5 | `error-handling` | Error hierarchies, retry strategies, resilience patterns, and structured error responses. | test-writer, implementer |
| 6 | `hexagonal-architecture` | Ports and Adapters to isolate core business logic from frameworks and infrastructure. Domain isolation, dependency inversion, and testability by design. | implementer, refactorer, code-critic, arbiter |
| 7 | `human-escalation` | Protocol for agents to gracefully halt execution and transfer context to a human when progress is blocked, ambiguous, or exceeding retry limits. | test-writer, implementer, refactorer, arbiter |
| 8 | `metrics` | Collect and report code quality metrics — coverage, complexity, mutation score, lint violations. | code-critic |
| 9 | `property-testing` | Write property-based tests with hypothesis. Invariant templates, strategy patterns, and best practices for functions with wide input spaces. | test-writer, test-critic |
| 10 | `pydantic` | Pydantic for Python domain models, configuration, and data validation — BaseModel, field validators, serialization, settings, and hexagonal architecture integration. | implementer, refactorer |
| 11 | `refactoring` | Disciplined code restructuring without behaviour change. Code smells, refactoring catalog, safe workflow, and IDE-assisted moves. | refactorer |
| 12 | `risk-management` | Systematically identify, assess, and mitigate project risks — risk registers, scoring matrices, response strategies, contingency planning, and review cadence. | planner |
| 13 | `secure-coding` | Prevent vulnerabilities during development — input validation, injection prevention, authentication, authorization, cryptography, and error handling. | code-critic |
| 14 | `static-analysis` | Run and interpret static analysis tools — Ruff, mypy, Bandit, Radon. Covers configuration, complexity thresholds, editor integration, and failure handling. | implementer, code-critic |
| 15 | `task-decomposition` | Break complex objectives into manageable, estimable, and assignable units of work using WBS, INVEST criteria, and vertical slicing. | planner |
| 16 | `unit-testing` | Verify correctness of individual units of code in isolation. AAA pattern, test doubles, language-specific guidance, edge cases, and coverage quality gates. | test-writer, test-critic |

## Agent Skill Matrix

| Agent | Skills |
|-------|--------|
| **planner** | task-decomposition, risk-management, design-patterns |
| **test-writer** | unit-testing, property-testing, error-handling, human-escalation |
| **test-critic** | unit-testing, code-review, property-testing |
| **implementer** | hexagonal-architecture, pydantic, error-handling, design-patterns, static-analysis, dependency-management, human-escalation |
| **code-critic** | code-review, static-analysis, metrics, secure-coding, hexagonal-architecture, dependency-management |
| **refactorer** | refactoring, design-patterns, hexagonal-architecture, pydantic, human-escalation |
| **documenter** | documentation |
| **arbiter** | human-escalation, design-patterns, hexagonal-architecture |
| **researcher** | data-pipeline-design, data-modeling, data-quality |
| **compliance-checker** | *(no skills — process checkpoint agent)* |
| **coordinator** | *(no skills — orchestrates agents)* |

## Available for Activation (22 skills in `skills/_available/`)

Skills in the library — not assigned to any agent. To activate one, move
it from `skills/_available/{name}/` to `skills/{name}/`, add it to the
relevant agent's Skills section, and update this index.

Use `/onboard-project` to evaluate which available skills match your tech
stack, or `/find-skill <topic>` to search.

ci-cd, configuration-management, containerization, context-curation,
contract-testing, data-modeling, data-pipeline-design, data-quality,
experiment-tracking, exploratory-data-analysis, feature-engineering,
idempotent-operations, integration-testing, ml-pipeline-design,
model-evaluation, model-selection, multi-agent-coordination,
performance-testing, secrets-management, security-testing, threat-modeling,
version-control

Each contains a `SKILL.md` in `skills/_available/{name}/SKILL.md`.
`/validate-framework` only deeply scans active skills (step 7).
