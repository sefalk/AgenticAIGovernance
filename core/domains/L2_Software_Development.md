**Version: 1.1 | Date: 2026-06-11**
**Level: 2 | Domain: Software Development**
**Derived from:** [L1_Core_Principles.md](../L1_Core_Principles.md) (Level 1, v3.9)

---

# Level 2 — Software Development Domain Rules

## Purpose

This artifact derives domain-specific rules for software development from the Level-1 Core Principles. These rules apply to all software development projects regardless of language, framework, or project size. They are declarative constraints (SHALL/SHALL NOT) that Level-3 workflows must operationalize.

---

## Derived Rules

> **Note:** Rule IDs are grouped by their parent L1 principle, not assigned sequentially. Gaps in numbering (e.g., no R-SD-16 through R-SD-20) are intentional and do not indicate missing rules.

### From: Review Principle (L1)

**R-SD-01:** All code changes SHALL be reviewed before integration into the primary deliverable branch. The review must produce a reviewable artifact (e.g., PR review comments, review document, self-review log).

**R-SD-02:** Architecture Decision Records (ADRs) SHALL be created for any decision that affects system structure, technology selection, or cross-cutting concerns. ADRs are subject to the review process.

**R-SD-03:** Code review SHALL NOT be limited to correctness alone. Reviews must also assess maintainability, testability, security, and adherence to project conventions.

### From: Verifiability & Quality Assurance (L1)

**R-SD-04:** All production code SHALL have automated tests. The minimum acceptable coverage threshold is defined at Level 4, but SHALL NOT be lower than 60% line coverage.

**R-SD-05:** All code SHALL pass static analysis (linting, type checking where applicable) with zero errors before integration. Warning thresholds are defined at Level 4.

**R-SD-06:** Quality gates SHALL be enforced programmatically via CI/CD pipelines. Manual-only quality enforcement SHALL NOT be accepted as the sole verification method.

**R-SD-07:** All builds SHALL be reproducible. Given the same source code and dependency versions, the build output must be identical (or functionally equivalent for non-deterministic compilers).

**R-SD-24:** Proof of Failure (Testing Validity): To prevent "hallucinated success," an agent SHALL NOT write the implementation code to fix a bug unless it first writes a test that *fails* in the current environment, proving both the bug's existence and the test's validity.

**R-SD-28:** GitFlow Quality Gates: Merging into higher-level branches SHALL be guarded by strict, level-dependent quality gates. A branch SHALL ONLY be merged to a higher branch if its corresponding quality gates are met. The higher the target branch, the stricter the gates. When merging into the `main` (or production) branch, the highest quality gates (all of them) MUST be fulfilled, and only productive/finished features SHALL be merged.

### From: Transparency/Traceability (L1)

**R-SD-08:** Every code change SHALL be linked to a tracked work item (issue, ticket, or task) when a project tracker integration is available or marked required at Level 4. If tracker integration is marked optional and unavailable, the change SHALL be linked via a local traceability artifact (decision log/plan/log entry) and synchronized later when access is restored.

**R-SD-09:** Commit messages SHALL follow a structured format that includes: type of change (feat, fix, refactor, docs, test, chore), scope, and a concise description. The specific format (e.g., Conventional Commits) is defined at Level 4.

**R-SD-10:** All third-party dependencies SHALL be declared explicitly in a lockfile or equivalent deterministic dependency specification. Implicit or unversioned dependencies SHALL NOT be used.

### From: Safety & Security (L1)

**R-SD-11:** Secrets and credentials SHALL NOT appear in source code, configuration files committed to version control, or log output. All secrets must be managed through a dedicated secret management mechanism.

**R-SD-12:** All third-party dependencies SHALL be scanned for known vulnerabilities. Dependencies with critical or high severity CVEs SHALL NOT be used without documented mitigation or explicit exception approved by the human User.

**R-SD-13:** User input SHALL be validated and sanitized at the system boundary. No user-provided data SHALL be used in SQL queries, shell commands, or template rendering without parameterization or escaping.

### From: Identity & Least Privilege (L1)

**R-SD-21:** When an agent is provisioned to execute a workflow, it SHALL ONLY be provided with API tokens scoped precisely to that repository and that specific task (e.g., a GitHub `GITHUB_TOKEN` scoped only to `repo:read` and `pull_requests:write`). Global Personal Access Tokens (PATs) SHALL NOT be used.

**R-SD-22:** An agent operating in a development or CI/CD context SHALL NOT be granted credentials capable of mutating the production environment unless explicitly undergoing a certified Level-3 Deployment Workflow.

**R-SD-23:** All commits, PRs, and systemic actions generated by the AI SHALL be clearly attributed to the specific Agent ID (e.g., `Author: AAIG-Review-Bot <bot@company.com>`), distinguishing its actions from human developers in the version history.

### From: Fail-Safe & Ask First (L1)

**R-SD-14:** Error handling SHALL distinguish between recoverable and unrecoverable errors. Unrecoverable errors SHALL fail fast with clear diagnostics. Recoverable errors SHALL be handled with appropriate retry or fallback strategies.

**R-SD-15:** All external service calls SHALL have timeouts configured. Calls without timeouts SHALL NOT be permitted in production code.

**R-SD-26:** Human Escalation Protocol: When an agent encounters an unrecoverable error, unresolvable ambiguity, or exceeds its computational budget, it SHALL NOT continuously retry or hallucinate solutions. It SHALL immediately halt execution, generate a structured `ESCALATION.md` detailing the blocker, and explicitly request human intervention.

### From: Separation of Concern (L1)

**R-SD-16:** Application layers (presentation, business logic, data access) SHALL be separated. Direct database queries from presentation layer code SHALL NOT be permitted.

**R-SD-17:** Configuration SHALL be separated from code. Environment-specific values (URLs, ports, feature flags) SHALL be injectable without code changes.

### From: Continuous Improvement (L1)

**R-SD-18:** Technical debt SHALL be tracked explicitly (e.g., via tagged issues, TODO comments with ticket references, or a dedicated debt register). Untracked technical debt accumulation SHALL be flagged during retrospectives.

**R-SD-19:** Deprecated code paths SHALL be marked with a removal timeline and tracked to completion. Deprecated code without a removal plan SHALL be treated as untracked technical debt.

### From: Efficiency / Pragmatism (L1)

**R-SD-20:** Code duplication SHALL be removed when it crosses the "Rule of Three" threshold (three or more identical or near-identical implementations). Premature extraction of single-use abstractions SHALL be avoided.

**R-SD-25:** Resource Governance & Iteration Limits: Agents SHALL NOT execute open-ended action loops. If a pre-defined iteration limit or computational token budget is reached without success, the task SHALL fail with an escalation per R-SD-26.

**R-SD-27:** Dependency Upgrade Policy: When a dependency upgrade causes cascading test failures that cannot be resolved within the iteration limit (R-SD-25), the agent SHALL: (1) revert to the last fully-green state, (2) prepare a **targeted upgrade plan** documenting each package, its current version, its proposed version, and the reason for the change, (3) present the plan to the human User for approval before re-attempting. Wholesale `upgrade-all` commands SHALL NOT be used without a rollback plan. A partial upgrade that leaves some packages at their previous version is an acceptable outcome when approved by the human User.

---

## Applicability

These rules apply to all software development projects governed by the AAIG framework. They are refined at Level 3 (workflows) and Level 4 (project bindings). Level-3 workflows must reference the specific R-SD rules they operationalize.

## Relationship to Skills Toolbox

The Skills Toolbox provides detailed implementation guidance for many of these rules:
- R-SD-01, R-SD-03 → `code_review.md`
- R-SD-04, R-SD-24 → `unit_testing.md`, `integration_testing.md`, `mutation_testing.md`
- R-SD-05 → `static_analysis.md`
- R-SD-06 → `ci_cd.md`
- R-SD-10, R-SD-12 → `dependency_management.md`
- R-SD-11 → `secrets_management.md`
- R-SD-13 → `secure_coding.md`
- R-SD-14 → `error_handling.md`
- R-SD-17 → `configuration_management.md`
- R-SD-21, R-SD-22, R-SD-23 → `version_control.md`, `code_review.md`
- R-SD-25, R-SD-26 → `human_escalation.md`
