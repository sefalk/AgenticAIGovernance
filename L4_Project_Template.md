# Level 4 — Project Instantiation Template
**Version: 1.0 | Date: 2026-03-04**
**Level: 4 | Domain: [Your Domain]**
**Derived from:** [L2_Software_Development.md](domains/L2_Software_Development.md) (Level 2)

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
| R-SD-05 (Static Analysis) | [e.g., `ruff check .` + `mypy src/` in pre-commit hooks] |
| R-SD-06 (Quality Gates) | [e.g., GitHub Actions required status checks on `main`] |
| R-SD-09 (Commit Format) | [e.g., `commitlint` with Conventional Commits] |
| R-SD-10 (Lockfile) | [e.g., `pnpm-lock.yaml` checked into VCS] |
| R-SD-12 (CVE Scan) | [e.g., `npm audit --audit-level=high` / Snyk] |

## 5. Loaded Skills

List the skills from the `skills/` toolbox that are active for this project. Derived from the Skill Selection Heuristic in `skills/_index.md`:

| Skill | Reason |
|-------|--------|
| [e.g., `unit_testing`] | [e.g., Core testing for all modules] |
| [e.g., `api_design`] | [e.g., REST API is the primary interface] |
| [e.g., `containerization`] | [e.g., Deployed via Docker on AWS ECS] |
| [e.g., `secrets_management`] | [e.g., Handles Stripe API keys] |

## 6. Project-Specific Overrides

Document any deviations from default AAIG rules with justification:

| Override | Default | Project Value | Justification |
|----------|---------|---------------|---------------|
| [e.g., R-SD-08 work-item linking] | Mandatory | Optional for `chore:` commits | [e.g., Trivial formatting commits don't need tickets] |

---

*This Level-4 file was generated during the AAIG Assimilation Protocol (Phase 3). It binds the generic framework to this specific project context.*
