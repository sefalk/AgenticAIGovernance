# Level 4 — Project Instantiation Template
**Version: 1.1 | Date: 2026-03-05**
**Level: 4 | Domain: [Your Domain]**
**Derived from:** [L2_Software_Development.md](domains/L2_Software_Development.md) (Level 2)

> **Deployment:** During L0 Assimilation (Phase 3), this file must be placed at **`.aaig/L4_Config.md`** in the repository root so CI pipeline bots and non-interactive agents can discover project-specific configuration without terminal access. It may also be placed at a native IDE path (e.g., `.cursor/rules/L4_Config.md`) in addition.

---

> This is a **template**. Copy this file into your project and fill in the bracketed values to bind the AAIG framework to your specific tech stack, team, and CI environment.

## 1. Project Identity

| Field | Value |
|-------|-------|
| **Project Name** | [e.g., `acme-billing-api`] |
| **Primary Language** | [e.g., TypeScript 5.4] |
| **Framework** | [e.g., Next.js 14, FastAPI 0.110, Spring Boot 3.2] |
| **Package Manager** | [e.g., pnpm 9.x, uv 0.5, Maven 3.9] |
| **Repository URL** | [e.g., `github.com/acme/billing-api`] |

## 2. Agent Configuration

| Field | Value |
|-------|-------|
| **Agent Engine** | [e.g., Cursor, Copilot Workspace, Antigravity, Devin] |
| **Agent Identity** | [e.g., `AAIG-BillingBot <bot@acme.com>`] |
| **Scoped Permissions** | [e.g., `repo:read`, `pull_requests:write`, `actions:read`] |
| **Coordination Mode** | [e.g., `single-agent` / `branch-per-agent` / `advisory-locks`] |

## 3. Quality Gate Thresholds

These override the defaults defined in the L2/L3 skills:

| Gate | Project Threshold | Skill Default | Justification |
|------|------------------|---------------|---------------|
| **Line Coverage** | [e.g., 85%] | 80% | [e.g., Critical financial logic requires higher coverage] |
| **Branch Coverage** | [e.g., 75%] | 70% | |
| **Mutation Score** | [e.g., 70%] | 60% | |
| **Max PR Size** | [e.g., 300 lines] | 500 lines | [e.g., Team prefers smaller PRs] |
| **Static Analysis Errors** | 0 | 0 | |
| **Static Analysis Warnings** | [e.g., < 10] | [project-defined] | |
| **Retry Limit (Escalation)** | [e.g., 3] | 3 | |

## 4. CI/CD Pipeline Mapping

Map R-SD rules to your specific CI tooling:

| Rule | Enforcement Mechanism |
|------|-----------------------|
| R-SD-04 (Tests) | [e.g., `pytest --cov=src --cov-fail-under=85` in GitHub Actions] |
| R-SD-05 (Static Analysis) | [e.g., ruff check . + mypy src/ in pre-commit hooks] |
| R-SD-06 (Quality Gates) | [e.g., GitHub Actions required status checks on `main`] |
| R-SD-09 (Commit Format) | [e.g., `commitlint` with Conventional Commits] |
| R-SD-10 (Lockfile) | [e.g., `pnpm-lock.yaml` checked into VCS] |
| R-SD-12 (CVE Scan) | [e.g., `npm audit --audit-level=high` / Snyk] |

## 5. Tool Mapping

Explicitly map the tools your project uses to resolve ambiguity for the agent:

| Category | Tool / Command |
|----------|----------------|
| **Unit Testing** | [e.g., `pytest`, `npm test`, `cargo test`] |
| **Linting** | [e.g., `flake8`, `eslint`, `rustfmt`] |
| **Static Analysis** | [e.g., `mypy`, `sonarqube`] |
| **Type Checking** | [e.g., `tsc`, `pyright`] |
| **Security Audit** | [e.g., `npm audit`, `snyk`] |

## 6. Active Specializations

List the domains and skills selected by the User during the **Specialization Prompt** (L0 Phase 3, Step 3). These are actively prioritized by the agent:

| Domain / Skill | Reason |
|----------------|--------|
| [e.g., `L2_Software_Development`] | [e.g., Primary project domain] |
| [e.g., `unit_testing`] | [e.g., Core testing for all modules] |
| [e.g., `api_design`] | [e.g., REST API is the primary interface] |
| [e.g., `containerization`] | [e.g., Deployed via Docker on AWS ECS] |
| [e.g., `secrets_management`] | [e.g., Handles Stripe API keys] |

## 7. Project-Specific Overrides

Document any deviations from default AAIG rules with justification:

| Override | Default | Project Value | Justification |
|----------|---------|---------------|---------------|
| [e.g., R-SD-08 work-item linking] | Mandatory | Optional for `chore:` commits | [e.g., Trivial formatting commits don't need tickets] |

## 8. Deployed Capabilities (Dormant)

All AAIG domains and skills are deployed during Full-Spectrum Assimilation. Those not selected in the Specialization Prompt are listed here for reference. They can be activated on-demand without re-assimilation:

| Domain / Skill | Status | Notes |
|----------------|--------|-------|
| [e.g., `L2_ML_Operations`] | Dormant | [e.g., No ML workload currently; available if needed] |
| [e.g., `L2_Data_Engineering`] | Dormant | |
| [e.g., `L2_Infrastructure`] | Dormant | |

---

*This Level-4 file was generated during the AAIG Assimilation Protocol (Phase 3). It binds the generic framework to this specific project context.*
