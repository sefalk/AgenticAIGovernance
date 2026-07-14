---
title: Workflows (L3)
type: concept
description: The Level-3 workflow templates, how agents classify a task and select one, and the fallback.
tags: [aaig, governance, workflow, l3]
updated: 2026-07-03
sources: [core/workflows/_index.md]
---

# Workflows (L3)

Level 3 workflows are generic, **step-by-step procedures** derived from
[L2 domain rules](05-domains.md). Each has explicit **phases**, **entry / exit
criteria**, and **quality gates**. Agents adapt a workflow to a project by
binding its `[L4-DEFINED]` placeholders during L4 instantiation.

## Workflow catalog

| Workflow | File | Phases | Key feature | Domain |
|---|---|---|---|---|
| Feature Development | `L3_Feature_Development.md` | 5 | Workflow bypass for trivial tasks; Refactoring Mode | Software Dev |
| Bug Fix | `L3_Bug_Fix.md` | 5 | Red→Green two-commit audit trail (proof of failure) | Software Dev |
| Code Review | `L3_Code_Review.md` | 4 | Structured review-artifact template | Software Dev |
| Deployment | `L3_Deployment.md` | 5 | Rollback protocol (stateless vs stateful) | Infrastructure |
| Data Pipeline | `L3_Data_Pipeline.md` | 5 | Raw→Staging→Mart layer separation | Data Engineering |
| ML Model Development | `L3_ML_Model_Development.md` | 6 | Baseline comparison & bias evaluation | ML Operations |
| Incident Response | `L3_Incident_Response.md` | 5 | Agent autonomy-boundary table | Security Ops |
| Security Audit | `L3_Security_Audit.md` | 5 | Proactive SAST/SCA/DAST scanning | Security Ops |
| Technical Writing | `L3_Technical_Writing.md` | 5 | Mandatory code-example verification | Technical Writing |
| Platform Capability Integration | `L3_Platform_Capability_Integration.md` | 4 | Required/optional provider probe + graceful degradation | Cross-domain |

## Selecting a workflow

The agent classifies the request and matches it to a workflow (a few examples):

| The user asks to… | Use |
|---|---|
| Build a feature / implement a user story | Feature Development |
| Fix a bug / patch a defect | Bug Fix |
| Review a PR / assess a merge request | Code Review |
| Provision resources / apply IaC | Deployment |
| Build a data pipeline / dbt model | Data Pipeline |
| Integrate an external tracker/wiki/API | Platform Capability Integration |
| Refactor existing code (no new behavior) | Feature Development → *Refactoring Mode* |

> **Fallback.** If no workflow matches, use the generic default sequence:
> **Plan → Review Plan → Execute → Verify → Review Output**.
> Some workflows (e.g. Compliance Audit, Database Migration) are *known planned*
> and currently use the fallback with domain-skill guidance.

## External integrations inside a workflow

When a workflow step touches an external system, the agent first runs the
project's **availability probe** (from the L4 contract). If the capability is
**required** and the probe fails → HALT and escalate; if **optional** →
continue via the documented fallback (local artifact/log + deferred sync). All
probe outcomes are logged. See [Platform Optionality](03-core-principles.md).

## In the Copilot flavor

L3 workflows are realized as **slash-command prompts** and the coordinator's
pipeline — e.g. `/tdd-feature`, `/quick-fix`, `/trivial-fix`, `/review-code`.
The [agent team](10-agents.md) executes the phases; [hooks](11-hooks-and-autonomy.md)
enforce the gates. Physically, L3 and L4 are often merged into the agent
prompts for token efficiency.

## See also

- [Domains (L2)](05-domains.md) · [Agent Team](10-agents.md) · [Skills Toolbox](07-skills-toolbox.md)
