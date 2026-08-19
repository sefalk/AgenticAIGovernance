# Skill Index

> Auto-generated index of all AF skills. Use `/af-find-skill <topic>` to search.
> Regenerate with `/af-validate-framework` (step 7 — skill directory structure).

| # | Skill | Description | Referenced by |
|---|-------|-------------|---------------|
## Active Skills (referenced by ≥1 agent)

| # | Skill | Description | Referenced by |
|---|-------|-------------|---------------|
| 1 | `ado-shared` | Shared Azure DevOps integration patterns — defaults, required/optional probe handling, and fallback traceability. | ado-work-item-manager, ado-wiki-manager, ado-pr-manager |
| 2 | `ado-workitem` | Azure DevOps work item lifecycle guidance — confidence matching, clarifications, and non-destructive updates. | ado-work-item-manager |
| 3 | `ado-wiki` | Azure DevOps wiki lifecycle guidance — target resolution, non-destructive updates, and change summaries. | ado-wiki-manager |
| 4 | `ado-pr` | Azure DevOps pull request lifecycle — branch publication precondition, PR create/update, work-item/plan linking, and branch-scoped autocomplete policy (integration branch autonomous, protected branch human-only). | ado-pr-manager |
| 5 | `code-review` | Structured code review guidance. Diff analysis, blast radius, automation-first review, anti-pattern detection, and review artifact templates. | test-critic, code-critic |
| 6 | `databricks-execution-patterns` | Deterministic Databricks workflow orchestration — metastore detection, run-type selection, output retrieval, evidence gating, cluster management. | coordinator, implementer, ado-work-item-manager |
| 7 | `dependency-management` | Dependency selection, version pinning, lockfiles, vulnerability scanning, and license compliance. | implementer, code-critic |
| 8 | `design-patterns` | Proven design patterns — creational, structural, behavioural, DDD, architecture. When to use, when NOT to use, and Python-idiomatic examples. | planner, implementer, refactorer, arbiter |
| 9 | `documentation` | Documentation standards — code comments, docstrings, READMEs, ADRs, changelogs. | documenter |
| 10 | `error-handling` | Error hierarchies, retry strategies, resilience patterns, and structured error responses. | test-writer, implementer |
| 11 | `hexagonal-architecture` | Ports and Adapters to isolate core business logic from frameworks and infrastructure. Domain isolation, dependency inversion, and testability by design. | implementer, refactorer, code-critic, arbiter |
| 12 | `human-escalation` | Protocol for agents to gracefully halt execution and transfer context to a human when progress is blocked, ambiguous, or exceeding retry limits. | test-writer, implementer, refactorer, arbiter |
| 13 | `metrics` | Collect and report code quality metrics — coverage, complexity, mutation score, lint violations. | code-critic |
| 14 | `property-testing` | Write property-based tests with hypothesis. Invariant templates, strategy patterns, and best practices for functions with wide input spaces. | test-writer, test-critic |
| 15 | `pydantic` | Pydantic for Python domain models, configuration, and data validation — BaseModel, field validators, serialization, settings, and hexagonal architecture integration. | implementer, refactorer |
| 16 | `refactoring` | Disciplined code restructuring without behaviour change. Code smells, refactoring catalog, safe workflow, and IDE-assisted moves. | refactorer |
| 17 | `risk-management` | Systematically identify, assess, and mitigate project risks — risk registers, scoring matrices, response strategies, contingency planning, and review cadence. | planner |
| 18 | `secure-coding` | Prevent vulnerabilities during development — input validation, injection prevention, authentication, authorization, cryptography, and error handling. | code-critic |
| 19 | `static-analysis` | Run and interpret static analysis tools — Ruff, mypy, Bandit, Radon. Covers configuration, complexity thresholds, editor integration, and failure handling. | implementer, code-critic |
| 20 | `task-decomposition` | Break complex objectives into manageable, estimable, and assignable units of work using WBS, INVEST criteria, and vertical slicing. | planner |
| 21 | `unit-testing` | Verify correctness of individual units of code in isolation. AAA pattern, test doubles, language-specific guidance, edge cases, and coverage quality gates. | test-writer, test-critic |
| 22 | `git-worktrees` | Create, manage, and remove git worktrees for parallel agent task execution. Lifecycle commands, context verification, troubleshooting, and recovery procedures. | coordinator |
| 23 | `notebook-execution` | Interact with local Jupyter / `.ipynb` notebooks via the VS Code notebook tools (run/edit cells, kernel selection, read outputs) instead of terminal scripts. | coordinator, implementer, refactorer, code-critic, test-writer |
| 24 | `git-workflow` | Git autonomy boundary, integration paths (pure git vs request-based), branch/work-item association (R-SD-08), phase-to-commit mapping, planning document lifecycle, and pre-commit guards. | coordinator, planner, documenter |
| 25 | `tdd-orchestration` | The coordinator's execution runbook — workflow state machine, git phase checkpoints, subagent context injection, the Step 1–7b delegation prompts with their retry and escalation policies, per-return protocols, and interruption/cancellation recovery. | coordinator |
| 26 | `test-execution` | Run tests and lint from an agent — pre-defined task labels, phase-specific scoping, expected runtimes, the per-workflow test budget, and the shared test log. | test-writer, test-critic, implementer, refactorer, code-critic |
| 27 | `copilot-authoring` | Reference depth for authoring Copilot customisation files — subagent pattern, model tiers, managed regions, built-in tool names, hooks JSON, prompt features, skill visibility, custom tool sets. | `copilot-authoring.instructions.md` (any agent editing a customisation file) |
| 28 | `gh-issue` | GitHub issue lifecycle — repository routing (project vs framework upstream), duplicate search before create, evidence-grounded framework defect reports, sub-issue linking, and degraded-mode fallback. | gh-issue-manager |

## Agent Skill Matrix

| Agent | Skills |
|-------|--------|
| **planner** | task-decomposition, risk-management, design-patterns, git-workflow |
| **coordinator** | tdd-orchestration, git-workflow, git-worktrees, databricks-execution-patterns, notebook-execution |
| **test-writer** | unit-testing, property-testing, test-execution, error-handling, human-escalation, notebook-execution |
| **test-critic** | unit-testing, code-review, property-testing, test-execution |
| **implementer** | hexagonal-architecture, pydantic, error-handling, design-patterns, static-analysis, dependency-management, test-execution, human-escalation, databricks-execution-patterns, notebook-execution |
| **code-critic** | code-review, static-analysis, metrics, secure-coding, hexagonal-architecture, dependency-management, test-execution, notebook-execution |
| **refactorer** | refactoring, design-patterns, hexagonal-architecture, pydantic, test-execution, human-escalation, notebook-execution |
| **documenter** | documentation, git-workflow |
| **arbiter** | human-escalation, design-patterns, hexagonal-architecture |
| **researcher** | data-pipeline-design, data-modeling, data-quality |
| **compliance-checker** | *(no skills — process checkpoint agent)* |
| **ado-work-item-manager** | ado-workitem, ado-shared, databricks-execution-patterns |
| **ado-wiki-manager** | ado-wiki, ado-shared |
| **ado-pr-manager** | ado-pr, ado-shared |
| **gh-issue-manager** | gh-issue |
| **gh-pr-manager** | git-workflow |

## Available for Activation (34 skills in `skills/_available/`)

Skills in the library — not assigned to any agent. To activate one, move
it from `skills/_available/{name}/` to `skills/{name}/`, add it to the
relevant agent's Skills section, and update this index.

Use `/af-onboard-project` to evaluate which available skills match your tech
stack, or `/af-find-skill <topic>` to search.

ci-cd, configuration-management, containerization, context-curation,
contract-testing, databricks-agent-bricks, databricks-apps,
databricks-bundles, databricks-connect, databricks-dbsql,
databricks-jobs, databricks-mlflow-eval, databricks-model-serving,
databricks-sdp, databricks-synthetic-data, databricks-unity-catalog,
data-modeling, data-pipeline-design, data-quality,
experiment-tracking, exploratory-data-analysis, feature-engineering,
idempotent-operations, integration-testing, ml-pipeline-design,
model-evaluation, model-selection, multi-agent-coordination,
performance-testing, python-dev, secrets-management, security-testing,
threat-modeling, version-control

Each contains a `SKILL.md` in `skills/_available/{name}/SKILL.md`.
`/af-validate-framework` only deeply scans active skills (step 7).
