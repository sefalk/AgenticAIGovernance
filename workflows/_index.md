# Workflows — Manifest & Selection Guide

**Version: 1.0 | Date: 2026-03-04**

## Purpose

This directory contains Level-3 Workflow templates derived from Level-2 Domain Rules. Each workflow is a generic, step-by-step procedure with explicit phases, entry/exit criteria, and quality gates. Agents adapt these workflows to their specific project during L4 Project Instantiation by binding `[L4-DEFINED]` placeholders.

## How Agents Should Use This Directory

1. **Classify the task** the user has requested (new feature, bug fix, infra change, etc.).
2. **Select the matching workflow** using the trigger table below.
3. **Load only the selected workflow.** Do not load all workflows — this preserves token budget.
4. **Bind placeholders** to project-specific values from the L4 Project Instantiation file.

## Workflow Selection Guide

| If the user asks to... | Use Workflow | Domain |
|---|---|---|
| Build a new feature, add functionality, implement a user story | [L3_Feature_Development.md](L3_Feature_Development.md) | Software Dev |
| Fix a bug, resolve an issue, patch a defect | [L3_Bug_Fix.md](L3_Bug_Fix.md) | Software Dev |
| Review a PR, evaluate code changes, assess a merge request | [L3_Code_Review.md](L3_Code_Review.md) | Software Dev |
| Deploy infrastructure, provision resources, apply IaC changes | [L3_Deployment.md](L3_Deployment.md) | Infrastructure |
| Build a data pipeline, create a dbt model, add an ETL job | [L3_Data_Pipeline.md](L3_Data_Pipeline.md) | Data Engineering |
| Train an ML model, build a recommendation engine, evaluate predictions | [L3_ML_Model_Development.md](L3_ML_Model_Development.md) | ML Operations |
| Respond to a security incident, investigate a breach | [L3_Incident_Response.md](L3_Incident_Response.md) | Security Ops |
| Audit for security, scan for vulnerabilities, assess security posture | [L3_Security_Audit.md](L3_Security_Audit.md) | Security Ops |
| Write docs, create API reference, draft ADR or runbook, update changelog | [L3_Technical_Writing.md](L3_Technical_Writing.md) | Technical Writing |
| Refactor existing code (no new behavior) | Use [L3_Feature_Development.md](L3_Feature_Development.md) **Refactoring Mode** section | Software Dev |
| Conduct a GDPR / HIPAA / SOC2 compliance audit, map PII data flows | ⚠️ **No dedicated workflow.** Use generic fallback. Read `skills/security/compliance_regulatory.md`. `L3_Compliance_Audit.md` is a known planned workflow. | Security Ops |

> **Fallback:** If no workflow matches, use the generic default sequence: **Plan → Review Plan → Execute → Verify → Review Output** (defined in `L1_Framework_Architecture.md`).

## Workflow Catalog

| Workflow | File | Phases | Key Feature | Derived From |
|----------|------|--------|-------------|--------------|
| Feature Development | `L3_Feature_Development.md` | 5 | Workflow Bypass for trivial tasks | `L2_Software_Development.md` |
| Bug Fix | `L3_Bug_Fix.md` | 5 | Red→Green two-commit audit trail (Proof of Failure) | `L2_Software_Development.md` |
| Code Review | `L3_Code_Review.md` | 4 | Structured Review Artifact Template | `L2_Software_Development.md` |
| Deployment | `L3_Deployment.md` | 5 | Rollback protocol (stateless vs. stateful) | `L2_Infrastructure.md` |
| Data Pipeline | `L3_Data_Pipeline.md` | 5 | Layer separation diagram (Raw→Staging→Mart) | `L2_Data_Engineering.md` |
| ML Model Dev | `L3_ML_Model_Development.md` | 6 | Baseline comparison & bias evaluation | `L2_ML_Operations.md` |
| Incident Response | `L3_Incident_Response.md` | 5 | Agent Autonomy Boundaries table | `L2_Security_Operations.md` |
| Security Audit | `L3_Security_Audit.md` | 5 | Proactive SAST/SCA/DAST scanning | `L2_Security_Operations.md` |
| Technical Writing | `L3_Technical_Writing.md` | 5 | Mandatory code-example verification | `L2_Technical_Writing.md` |

## Adding New Workflows

1. Create a new `L3_<WorkflowName>.md` file in this directory.
2. Include the standard header: Version, Level, Domain, Derived-from link, and Operationalizes (list of R-XX rules).
3. Structure the workflow as numbered Phases with explicit **Entry Criteria** and **Exit Criteria**.
4. Use `[L4-DEFINED]` placeholders for any project-specific values.
5. Add an entry to the catalog above.
6. Submit for review per the AAIG Review Principle.
