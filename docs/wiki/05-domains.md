---
title: Domain Rules (L2)
type: concept
description: The seven Level-2 domains, their rule prefixes, and how agents select and activate them.
tags: [aaig, governance, domains, l2]
updated: 2026-07-03
sources: [core/domains/_index.md]
---
<!-- copilot:generated | documenter | 2026-07-03 -->

# Domain Rules (L2)

Level 2 translates the universal [L1 principles](03-core-principles.md) into
concrete, testable **`SHALL / SHALL NOT`** constraints for a specific
professional domain. Each domain file uses a unique rule prefix (e.g. `R-SD-`)
so rules are individually citable in commits, reviews, and
[benchmarks](08-benchmark.md).

## Domain catalog

| Domain | File | Rule prefix | Rules | Key themes |
|---|---|---|---|---|
| Software Development | `L2_Software_Development.md` | `R-SD-` | 27 | Code review, testing, identity, escalation, dependency pinning |
| Data Engineering | `L2_Data_Engineering.md` | `R-DE-` | 15 | Idempotency, lineage, PII masking, freshness SLAs |
| ML Operations | `L2_ML_Operations.md` | `R-ML-` | 15 | Reproducibility, bias/fairness, drift monitoring |
| Infrastructure | `L2_Infrastructure.md` | `R-IF-` | 15 | IaC-only, plan-before-apply, drift detection |
| Technical Writing | `L2_Technical_Writing.md` | `R-TW-` | 12 | Tested examples, `[VERIFY]` markers, ADR templates |
| Security Operations | `L2_Security_Operations.md` | `R-SO-` | 15 | Authorized scanning, forensic preservation, retrospectives |
| Embedded Systems | `L2_Embedded_Systems.md` | `R-ES-` | 15 | WCET, HIL testing, watchdog, HAL, memory safety |

## Selecting a domain

Agents match project characteristics to domains:

| If the project contains… | Load |
|---|---|
| Application source, tests, CI/CD | Software Development (`R-SD-`) |
| ETL/ELT, dbt models, warehouses, Airflow DAGs | Data Engineering (`R-DE-`) |
| Model training, experiment tracking, serving | ML Operations (`R-ML-`) |
| Terraform/Pulumi/CloudFormation, cloud resources | Infrastructure (`R-IF-`) |
| READMEs, API docs, ADRs, changelogs | Technical Writing (`R-TW-`) |
| Security audits, vuln scanning, incident response | Security Operations (`R-SO-`) |
| Firmware, C/C++/Rust, RTOS, microcontrollers | Embedded Systems (`R-ES-`) |

A monorepo may activate several domains at once; the agent notes the primary
service directory for the current task context.

## Active vs dormant

During [L0 assimilation](04-assimilation.md), **all** domains are deployed. The
User's Specialization Prompt selection marks some **Active** (prioritized in the
agent's context); the rest stay **Deployed (Dormant)** and can be activated on
demand by updating the L4 contract — no re-assimilation needed.

## Relationship to workflows

Each domain maps to one or more [L3 workflows](06-workflows.md) that
operationalize its rules — e.g. Software Development → Feature Development, Bug
Fix, Code Review. Rules also point into the [Skills Toolbox](07-skills-toolbox.md)
for detailed technique guidance.

> **Extending.** New domains add an `L2_<Name>.md` with a version header, a
> derived-from link to L1, rules grouped by principle, a unique prefix, a
> catalog entry, and a review pass. See `core/domains/_index.md`.

## See also

- [Core Principles (L1)](03-core-principles.md) · [Workflows (L3)](06-workflows.md) · [Benchmark](08-benchmark.md)
