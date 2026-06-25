# Skills Toolbox -- Manifest & Usage Guide

**Version: 2.7 | Date: 2026-06-25**

## Purpose

This directory contains optional, detailed skill templates that agents may invoke during Level-2, Level-3, or Level-4 artifact derivation. Each skill provides state-of-the-art guidance for a specific practice area.

## How Agents Should Use This Toolbox

1. **Full-Spectrum Deployment:** During L0 Assimilation (Phase 3), the **entire** `skills/` directory is deployed into the environment. 
2. **Active Specializations:** During assimilation, the User selects which skills are actively prioritized via the **Specialization Prompt**. These are recorded in the L4 Contract and integrated into the agent's active context.
3. **On-Demand Activation:** Non-selected skills remain deployed but dormant. Use the Skill Selection Heuristic (below) to identify newly relevant skills as the project evolves, and activate them on-demand by updating the L4 Contract.
4. **Partial reading:** If you only need specific guidance (e.g., tool recommendations, CI thresholds) from a dormant skill without fully activating it, you may read just that section. Each skill's sections are independently useful:
   - **Quality Gates** -- for threshold definitions only
   - **Techniques & Patterns** -- for implementation guidance
   - **Anti-Patterns** -- for review/validation
   - **References** -- for tool/library discovery
5. **Apply:** Use active and referenced skills as expert guidance when producing Level-2 rules, Level-3 workflows, or Level-4 project bindings.
6. **Override:** Skills may be refined or overridden at Level 3 or Level 4 to match project-specific requirements.

## When to Skip Skills

Skills add value for design decisions, new patterns, and quality-critical work. **Do not invoke skills for:** single-file bug fixes, configuration changes, documentation-only edits, dependency version bumps, or straightforward refactors where the pattern is already known. If the task is trivial and well-understood, skills are overhead.

## Applies-To Taxonomy

Skills use a controlled vocabulary for their `applies_to` tags. Match project characteristics against these tags:

| Tag | Meaning |
|-----|---------|
| `all` | Universal, applies to any project type |
| `web` | Web applications (frontend + backend) |
| `api` | HTTP/gRPC/GraphQL services |
| `mobile` | iOS, Android, React Native, Flutter |
| `cli` | Command-line tools and scripts |
| `library` | Reusable packages / SDKs |
| `microservice` | Distributed service architectures |
| `data` | Data pipelines, warehouses, analytics |
| `cloud` | Cloud-deployed infrastructure |
| `desktop` | Desktop applications |
| `ml` | Machine learning / data science projects |

Language-specific guidance (Python, JavaScript, Java, Go, Rust, C#) is provided within each skill's body text, not via tags. Filter by project type, not programming language.

## Skill Selection Heuristic

Use this mapping to quickly identify relevant skills for your project type:

| Project Type | Start With | Add If Needed |
|-------------|------------|---------------|
| **Web application** | unit_testing, e2e_testing, api_design, ci_cd, static_analysis | security_testing, performance_testing, containerization |
| **REST/GraphQL API** | unit_testing, integration_testing, api_design, ci_cd, contract_testing | performance_testing, security_testing, monitoring_observability |
| **Microservice system** | unit_testing, integration_testing, contract_testing, containerization, monitoring_observability, ci_cd | api_design, system_design, performance_testing |
| **Data pipeline** | data_pipeline_design, data_quality, data_modeling, ci_cd | monitoring_observability, documentation, performance_testing |
| **CLI tool / Library** | unit_testing, property_based_testing, static_analysis, documentation, ci_cd | mutation_testing, snapshot_testing |
| **Mobile app** | unit_testing, e2e_testing, ci_cd, snapshot_testing | performance_testing, security_testing |
| **New project (any)** | task_decomposition, documentation, ci_cd, unit_testing, code_review | risk_management, system_design, dependency_management |
| **Security-sensitive** | threat_modeling, secure_coding, secrets_management, security_testing | dependency_management, code_review |
| **ML / Data Science** | exploratory_data_analysis, experiment_tracking, model_evaluation, feature_engineering, unit_testing | ml_pipeline_design, data_quality, ci_cd, monitoring_observability |
| **Accessible web app** | unit_testing, e2e_testing, accessibility_testing, ci_cd, static_analysis | performance_testing, security_testing |

## Skill Compositions (Bundles)

Named bundles for common multi-skill scenarios. Load the entire bundle when the scenario applies:

| Bundle | Skills | Scenario |
|--------|--------|----------|
| **New Service Setup** | api_design, unit_testing, ci_cd, containerization, monitoring_observability, documentation | Bootstrapping a new backend service |
| **Quality Hardening** | static_analysis, code_review, mutation_testing, dependency_management, refactoring | Improving an existing codebase's quality |
| **Security Audit** | threat_modeling, secure_coding, secrets_management, security_testing, dependency_management | Comprehensive security review |
| **Data Platform** | data_pipeline_design, data_quality, data_modeling, monitoring_observability, ci_cd | Building or auditing a data platform |
| **Production Readiness** | performance_testing, monitoring_observability, ci_cd, containerization, infrastructure_as_code, security_testing | Preparing for production launch |
| **ML Platform** | exploratory_data_analysis, experiment_tracking, feature_engineering, model_selection, model_evaluation, ml_pipeline_design, monitoring_observability | End-to-end ML project setup |

## Maturity Levels

Each skill carries a maturity indicator in its frontmatter:

| Level | Meaning | Implication |
|-------|---------|-------------|
| **draft** | Newly created, not yet peer-reviewed | Use as guidance but verify independently. May have gaps. |
| **reviewed** | Passed review process | Reliable for general use. |
| **proven** | Applied in real projects with positive outcomes | High confidence. Established best practice. |

**Promotion process:** `draft` -> `reviewed` requires passing the review process (see Review Principle) with another agent or via structured self-review. `reviewed` -> `proven` requires evidence of successful application in at least one real project, documented in a retrospective or Decision Log. Update the `maturity` and `last_reviewed` fields in the skill's frontmatter upon promotion.

## Skill Template

All skill files must follow this structure, starting with YAML frontmatter:

```markdown
---
category: [category_directory_name]
applies_to: [tags from Applies-To Taxonomy]
complexity: foundational | intermediate | advanced  # learning curve and implementation difficulty, NOT frequency of use
maturity: draft | reviewed | proven
version: "1.0"
last_reviewed: YYYY-MM-DD
related: [list of related skill filenames without path]  # source of truth for ## See Also
---
# [Skill Name]

## Purpose
## Principles
## Techniques & Patterns
## Quality Gates
## Anti-Patterns
## See Also          # render the `related` frontmatter field as links
## References
```

**Conventions:**
- In `## Principles`, connect at least one principle to an AAIG Level-1 principle using the format: `**PrincipleName (AAIG L1):** [explanation]`. This maintains traceability to the governing framework.
- The `related` frontmatter field is the source of truth for cross-references. The `## See Also` section renders these as relative links. When adding a related skill, update the `related` field first; keep See Also in sync.

## Adding New Skills

1. Create a new `.md` file in the appropriate category subdirectory.
2. Follow the Skill Template above, including YAML frontmatter. Use only tags from the Applies-To Taxonomy for the `applies_to` field.
3. Add an entry to the catalog below. Keep it in sync with the skill's frontmatter.
4. Submit the new skill for review per the AAIG Review Principle.

---



## Skill Catalog

> **Maintenance:** If a skill's frontmatter is updated (e.g., `applies_to` or `complexity` changes), update the corresponding catalog entry to match. Periodically reconcile the catalog with actual frontmatter values.

### Testing (`testing/`)

| Skill | File | Applies To | Complexity | Description |
|-------|------|------------|------------|-------------|
| Unit Testing | `unit_testing.md` | `all` | foundational | When writing any testable code. Isolation, mocking, AAA pattern, coverage |
| Mutation Testing | `mutation_testing.md` | `all` | intermediate | When you suspect tests pass but don't truly verify behavior |
| Property-Based Testing | `property_based_testing.md` | `all` | advanced | When input space is large or edge cases matter. Generators, shrinking |
| Integration Testing | `integration_testing.md` | `all`, `api`, `microservice` | foundational | When testing across service/database boundaries |
| E2E Testing | `e2e_testing.md` | `web`, `mobile` | intermediate | When validating complete user flows through the UI |
| Performance Testing | `performance_testing.md` | `api`, `web`, `microservice` | intermediate | When you need to validate latency, throughput, or scalability |
| Security Testing | `security_testing.md` | `all` | intermediate | When assessing vulnerability exposure. SAST/DAST, OWASP Top 10 |
| Contract Testing | `contract_testing.md` | `microservice`, `api` | advanced | When multiple services must agree on API shape |
| Snapshot Testing | `snapshot_testing.md` | `web`, `cli`, `library` | foundational | When detecting unintended output changes |
| Accessibility Testing | `accessibility_testing.md` | `web`, `mobile` | intermediate | When building user-facing UIs. WCAG, axe-core, screen readers |

### Code Quality (`code_quality/`)

| Skill | File | Applies To | Complexity | Description |
|-------|------|------------|------------|-------------|
| Code Review | `code_review.md` | `all` | foundational | When any code changes need human/agent evaluation |
| Static Analysis | `static_analysis.md` | `all` | foundational | When enforcing code standards automatically. Linters, type checkers |
| Refactoring | `refactoring.md` | `all` | intermediate | When improving code structure without changing behavior |
| Documentation | `documentation.md` | `all` | foundational | When writing or structuring project documentation. ADRs, READMEs |
| Dependency Management | `dependency_management.md` | `all` | foundational | When managing third-party packages. Lockfiles, updates, licenses |
| Error Handling | `error_handling.md` | `all` | intermediate | When designing failure modes. Retry, circuit breaker, fallbacks |

### Architecture & Design (`architecture/`)

| Skill | File | Applies To | Complexity | Description |
|-------|------|------------|------------|-------------|
| API Design | `api_design.md` | `api`, `web`, `microservice` | intermediate | When designing or evolving HTTP/gRPC/GraphQL interfaces |
| Database Design | `database_design.md` | `api`, `web`, `data` | intermediate | When designing schemas, indexes, or migrations |
| System Design | `system_design.md` | `microservice`, `cloud`, `web` | advanced | When making architectural decisions about scalability and reliability |
| Frontend Architecture | `frontend_architecture.md` | `web`, `mobile` | intermediate | When designing component hierarchies and state management |
| Hexagonal Architecture | `hexagonal_architecture.md` | `api`, `microservice`, `web` | advanced | When implementing Ports and Adapters to isolate core domain logic |
| Context Curation | `context_curation.md` | `all` | advanced | Teaching agents how to manage LLM token limits and context boundaries |
| Idempotent Operations | `idempotent_operations.md` | `api`, `microservice`, `data`, `cloud` | intermediate | Teaching agents to design retry-safe mutations |
| Design Patterns | `design_patterns.md` | `all` | intermediate | When choosing structural solutions. GoF, SOLID, DDD, hexagonal |
| Event-Driven Architecture | `event_driven_architecture.md` | `microservice`, `cloud`, `api` | advanced | When building async/event-based systems. Kafka, CQRS, sagas |
| Authentication & Authorization | `authentication_authorization.md` | `web`, `api`, `mobile`, `microservice` | intermediate | When implementing login, permissions, or identity flows |
| Multi-Agent Coordination | `multi_agent_coordination.md` | `all` | advanced | Protocols for concurrent agents: branch isolation, advisory locks, context handoffs |

### DevOps & Deployment (`devops/`)

| Skill | File | Applies To | Complexity | Description |
|-------|------|------------|------------|-------------|
| Azure DevOps Work Item Management | `ado_work_item_management.md` | `all` | intermediate | Provider-specific lifecycle for ADO work items with confidence matching and non-destructive updates |
| Azure DevOps Wiki Management | `ado_wiki_management.md` | `all` | intermediate | Provider-specific lifecycle for ADO wiki page updates with traceable change summaries |
| Pull / Merge Request Integration | `pr_integration_management.md` | `all` | intermediate | Provider-agnostic request-based integration: path separation, branch-scoped completion policy, and orchestrator/worker split |
| CI/CD | `ci_cd.md` | `all` | foundational | When setting up or improving build/deploy pipelines |
| Containerization | `containerization.md` | `api`, `web`, `microservice`, `cloud` | intermediate | When packaging apps in containers. Dockerfile, multi-stage, Compose |
| Infrastructure as Code | `infrastructure_as_code.md` | `cloud` | advanced | When managing cloud resources declaratively. Terraform, Pulumi |
| Mobile Development | `mobile_development.md` | `mobile` | intermediate | When building pipelines, distributing, or fixing architecture for iOS/Android apps |
| Monitoring & Observability | `monitoring_observability.md` | `api`, `web`, `microservice`, `cloud` | intermediate | When you need visibility into production. Logs, metrics, traces, SLOs |
| LLM Observability | `llm_observability.md` | `all` | intermediate | Instrumenting autonomous workflows to trace prompt and token data |
| Structured Logging | `structured_logging.md` | `all` | foundational | When standardizing log outputs. JSON logs, correlation IDs, log levels |
| Configuration Management | `configuration_management.md` | `all` | foundational | When managing runtime settings. Env vars, feature flags, 12-factor |
| Version Control | `version_control.md` | `all` | foundational | When interacting with Git. Atomic commits, branch strategy, squashing history |

### Data Engineering (`data_engineering/`)

| Skill | File | Applies To | Complexity | Description |
|-------|------|------------|------------|-------------|
| Data Pipeline Design | `data_pipeline_design.md` | `data` | intermediate | ETL/ELT, orchestration (Airflow/Dagster/dbt), idempotency, error handling |
| Data Quality | `data_quality.md` | `data` | intermediate | Quality dimensions, Great Expectations, dbt tests, anomaly detection |
| Data Modeling | `data_modeling.md` | `data` | intermediate | Star/snowflake schema, SCDs, dbt conventions, metrics layer, Data Vault |

### Project Management (`project_management/`)

| Skill | File | Applies To | Complexity | Description |
|-------|------|------------|------------|-------------|
| Task Decomposition | `task_decomposition.md` | `all` | foundational | WBS, INVEST criteria, estimation techniques, dependency mapping |
| Stakeholder Communication | `stakeholder_communication.md` | `all` | foundational | Stakeholder maps, status reports, escalation framework |
| Risk Management | `risk_management.md` | `all` | intermediate | Risk register, scoring matrix, response strategies, contingency planning |
| Human Escalation Protocol | `human_escalation.md` | `all` | foundational | Agent-specific workflow for cleanly halting tasks and requesting human unblocking via ESCALATION.md |

### Security (`security/`)

| Skill | File | Applies To | Complexity | Description |
|-------|------|------------|------------|-------------|
| Threat Modeling | `threat_modeling.md` | `system`, `architecture` | advanced | When designing new systems. STRIDE, attack vector mapping |
| Secure Coding | `secure_coding.md` | `all` | intermediate | Input validation, injection prevention, auth patterns, cryptography |
| Secrets Management | `secrets_management.md` | `all`, `cloud` | intermediate | Storage hierarchy, managed services, rotation, detection, emergency response |
| Compliance & Regulatory | `compliance_regulatory.md` | `all`, `cloud`, `web`, `data` | advanced | When building systems subject to GDPR, SOC2, HIPAA, or residency laws |

### Embedded Systems (`embedded/`)

| Skill | File | Applies To | Complexity | Description |
|-------|------|------------|------------|-------------|
| Embedded Systems Development | `embedded_systems.md` | `embedded`, `iot`, `c`, `cpp`, `rust` | advanced | When building firmware for resource-constrained, real-time devices |

### Data Science & ML (`data_science/`)

| Skill | File | Applies To | Complexity | Description |
|-------|------|------------|------------|-------------|
| Exploratory Data Analysis | `exploratory_data_analysis.md` | `ml`, `data` | foundational | EDA workflow, profiling tools, notebook discipline, statistical tests |
| Experiment Tracking | `experiment_tracking.md` | `ml` | intermediate | MLflow/W&B, data versioning, reproducibility, naming conventions |
| Feature Engineering | `feature_engineering.md` | `ml`, `data` | intermediate | Encoding, leakage prevention, feature stores, feature selection |
| Model Evaluation | `model_evaluation.md` | `ml` | intermediate | Metrics, validation strategies, bias/fairness auditing, explainability |
| ML Pipeline Design | `ml_pipeline_design.md` | `ml`, `cloud` | advanced | Training pipelines, model serving, registry, deployment, monitoring |
| Model Selection | `model_selection.md` | `ml` | intermediate | Problem-to-model decision tree, classical vs deep learning, transfer learning, frameworks |
