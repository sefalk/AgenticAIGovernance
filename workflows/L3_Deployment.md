**Version: 1.0 | Date: 2026-03-04**
**Level: 3 | Domain: Infrastructure**
**Derived from:** [L2_Infrastructure.md](../L2_Infrastructure.md) (Level 2)
**Operationalizes:** R-IF-01, R-IF-02, R-IF-03, R-IF-06, R-IF-07, R-IF-11, R-IF-12

---

# L3 Workflow — Deployment (Infrastructure Change)

## Purpose

This workflow defines the standard procedure for applying infrastructure changes to any environment. It enforces the plan-before-apply principle (R-IF-02), ensures destructive operations require confirmation (R-IF-11), and mandates post-deployment verification.

> **Adaptation Note:** Bind `[L4-DEFINED]` placeholders during L4 Project Instantiation.

---

## Phases

### Phase 1: Author & Validate
**Entry Criteria:** An infrastructure change request exists (feature ticket, capacity need, cost optimization).

1. Write or modify IaC code in a feature branch (R-IF-01, R-IF-06).
2. Run automated IaC validation: `[L4-DEFINED: validation command]` (e.g., `terraform validate`, `tflint`, `checkov`) (R-IF-03).
3. If security misconfigurations are detected (public buckets, open ports), fix before proceeding.

**Exit Criteria:** IaC code passes all validation checks.

---

### Phase 2: Plan (Dry Run)
**Entry Criteria:** Phase 1 passes.

1. Generate a change plan against the target environment: `[L4-DEFINED: plan command]` (e.g., `terraform plan`, `pulumi preview`) (R-IF-02).
2. **Review the plan output.** The agent MUST read and summarize:
   - Resources to be **created** (count and types).
   - Resources to be **modified** (highlight in-place vs. replacement).
   - Resources to be **destroyed** (critical attention required).
3. If any **destructive operations** are present (resource deletion, replacement), flag them explicitly and require confirmation:
   - For non-production environments: agent self-confirmation is acceptable.
   - For production environments: **human User approval is MANDATORY** (R-IF-11).

**Exit Criteria:** Plan is reviewed, destructive operations are acknowledged, production changes have human approval.

---

### Phase 3: Apply
**Entry Criteria:** Phase 2 plan is approved.

1. Apply the changes: `[L4-DEFINED: apply command]`.
2. Monitor the apply output for errors. If the apply fails:
   - Assess the partial state.
   - Attempt rollback if safe, or escalate per R-SD-26.
3. Verify the state file is updated in the remote backend (R-IF-05).

**Exit Criteria:** Apply completes successfully, state is consistent.

---

### Phase 4: Smoke Test & Verify
**Entry Criteria:** Phase 3 apply succeeds.

1. Run smoke tests against the deployed infrastructure: `[L4-DEFINED: smoke test commands]`.
   - Example: HTTP health check against a new load balancer, DNS resolution for a new domain, connectivity test for a new VPC peering.
2. Check for **infrastructure drift** by running a fresh plan: if the plan shows any changes, the apply was not fully applied (R-IF-12).
3. Verify resource tagging compliance (R-IF-04).

**Exit Criteria:** Smoke tests pass, no drift detected, tags are compliant.

---

### Phase 5: Monitor & Document
**Entry Criteria:** Phase 4 passes.

1. Monitor the affected services for `[L4-DEFINED: monitoring window, default 30 minutes]` for anomalies.
2. Merge the infrastructure branch.
3. Update documentation if the change affects runbooks, architecture diagrams, or network topology.

**Exit Criteria:** Monitoring window passes without anomalies, branch is merged.

---

## Rollback Protocol

If issues are detected in Phases 4-5:

1. **Stateless resources** (Lambda functions, container images): redeploy the previous version.
2. **Stateful resources** (databases, storage): do NOT auto-rollback. Escalate to human User immediately — data loss risk.
3. **Network changes** (security groups, routes): revert the IaC code and re-apply.

All rollbacks must be executed through IaC (re-apply the previous code version), not via manual console actions (R-IF-01).
