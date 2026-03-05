# Domain Rules — Manifest & Selection Guide

**Version: 1.1 | Date: 2026-03-05**

## Purpose

This directory contains Level-2 Domain Rule documents derived from `L1_Core_Principles.md`. Each document translates universal L1 principles into concrete `SHALL / SHALL NOT` constraints for a specific professional domain.

## How Agents Should Use This Directory

1. **Full-Spectrum Deployment:** During L0 Assimilation (Phase 3), **all** L2 domain files in this directory are deployed into the environment. This ensures governance capabilities are always available, even as project requirements evolve.
2. **Active Specializations:** The User selects which domains are actively prioritized via the **Specialization Prompt** during assimilation. Active domains are recorded in the L4 Contract. Non-selected domains remain deployed but dormant.
3. **On-Demand Activation:** At any time, a dormant domain can be activated by the agent or User without re-running the Assimilation Protocol. Simply reference the domain and update the L4 Contract's Active Specializations list.
4. **Monorepo Context:** In monorepos where multiple stacks co-exist, the agent notes the primary service directory for the current task context, but the full domain set remains available.

## Domain Selection Guide

| If the project contains... | Load | Rule Prefix |
|---|---|---|
| Application source code, tests, CI/CD pipelines | [L2_Software_Development.md](L2_Software_Development.md) | `R-SD-` |
| ETL/ELT pipelines, dbt models, data warehouses, Airflow DAGs | [L2_Data_Engineering.md](L2_Data_Engineering.md) | `R-DE-` |
| ML model training, experiment tracking, model serving | [L2_ML_Operations.md](L2_ML_Operations.md) | `R-ML-` |
| Terraform/Pulumi/CloudFormation, cloud resource management | [L2_Infrastructure.md](L2_Infrastructure.md) | `R-IF-` |
| Documentation tasks (READMEs, API docs, ADRs, changelogs) | [L2_Technical_Writing.md](L2_Technical_Writing.md) | `R-TW-` |
| Security audits, vulnerability scanning, incident response | [L2_Security_Operations.md](L2_Security_Operations.md) | `R-SO-` |
| Firmware, C/C++/Rust, RTOS, microcontroller, ARM, CMake, embedded | [L2_Embedded_Systems.md](L2_Embedded_Systems.md) | `R-ES-` |

## Domain Catalog

| Domain | File | Rules | Key Themes | Workflows |
|--------|------|-------|------------|-----------|
| Software Development | `L2_Software_Development.md` | 27 | Code review, testing, identity, escalation, dep pinning | Feature Dev, Bug Fix, Code Review |
| Data Engineering | `L2_Data_Engineering.md` | 15 | Idempotency, lineage, PII masking, freshness SLAs | Data Pipeline |
| ML Operations | `L2_ML_Operations.md` | 15 | Reproducibility, bias/fairness, drift monitoring | ML Model Dev |
| Infrastructure | `L2_Infrastructure.md` | 15 | IaC-only, plan-before-apply, drift detection | Deployment |
| Technical Writing | `L2_Technical_Writing.md` | 12 | Tested examples, `[VERIFY]` markers, ADR templates | Technical Writing |
| Security Operations | `L2_Security_Operations.md` | 15 | Authorized scanning, forensic preservation, retrospectives | Incident Response, Security Audit |
| Embedded Systems | `L2_Embedded_Systems.md` | 15 | WCET, HIL testing, watchdog, HAL, memory safety | Feature Dev (Refactoring Mode) |

## Adding New Domains

1. Create a new `L2_<DomainName>.md` file in this directory.
2. Follow the structure of existing L2 documents: Version header, Derived-from link, rules grouped by L1 principle, and a Skills Toolbox mapping.
3. Choose a unique rule prefix (e.g., `R-XX-`) to avoid collisions.
4. Add an entry to the catalog above.
5. Submit for review per the AAIG Review Principle.
