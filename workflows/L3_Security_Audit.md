**Version: 1.0 | Date: 2026-03-04**
**Level: 3 | Domain: Security Operations**
**Derived from:** [L2_Security_Operations.md](../domains/L2_Security_Operations.md) (Level 2)
**Operationalizes:** R-SO-01, R-SO-02, R-SO-03, R-SO-04, R-SO-06, R-SO-07, R-SO-09, R-SO-13, R-SO-14

---

# L3 Workflow — Security Audit (Proactive)

## Purpose

This workflow defines the standard procedure for a **proactive** security assessment — a planned, systematic evaluation of a codebase's security posture. This is distinct from `L3_Incident_Response.md`, which handles reactive incident management. Use this workflow when the user asks for a security review, vulnerability scan, or compliance check.

> **Adaptation Note:** Bind `[L4-DEFINED]` placeholders during L4 Project Instantiation.

---

## Phases

### Phase 1: Scope & Authorization
**Entry Criteria:** User requests a security audit or assessment.

1. Define the **audit scope**:
   - Which components/repositories are in scope?
   - Which environments? (dev, staging, production)
   - What compliance frameworks apply? (e.g., OWASP Top 10, SOC2, GDPR)
2. **Verify authorization** (R-SO-07): Confirm with the user that scanning is permitted against the target environment. Log the authorization.
3. Check that scanning tools have up-to-date signatures/rules (R-SO-09).

**Exit Criteria:** Scope is documented, authorization is confirmed, tools are current.

---

### Phase 2: Automated Scanning
**Entry Criteria:** Phase 1 scope is approved.

1. Run **Static Application Security Testing (SAST)**: `[L4-DEFINED: SAST tool]` (e.g., CodeQL, Semgrep, SonarQube).
2. Run **Dependency/SCA scanning**: `[L4-DEFINED: SCA tool]` (e.g., `npm audit`, Snyk, Dependabot).
3. Run **Secret scanning**: `[L4-DEFINED: secret scanner]` (e.g., trufflehog, gitleaks) across the full Git history.
4. If applicable, run **Dynamic Application Security Testing (DAST)**: `[L4-DEFINED: DAST tool]` (e.g., OWASP ZAP) against a staging environment.
5. Collect all raw scan outputs as timestamped reports (R-SO-04).

**Exit Criteria:** All applicable scan types have completed and raw reports are archived.

---

### Phase 3: Finding Classification
**Entry Criteria:** Phase 2 scans are complete.

1. **Deduplicate** findings across tools (the same CVE may appear in multiple scanners).
2. **Verify exploitability** for each finding (R-SO-02):
   - Is the vulnerable code path actually reachable?
   - Is the vulnerable dependency actually used at runtime (vs. dev-only)?
   - Does the finding have a known exploit in the wild?
3. **Classify severity** using a standard framework (CVSS or project-defined):

| Severity | Criteria |
|----------|----------|
| **Critical** | Actively exploitable, high impact (RCE, auth bypass, data exfiltration) |
| **High** | Exploitable with some prerequisites, significant impact |
| **Medium** | Exploitable but limited impact, or requires unlikely conditions |
| **Low** | Theoretical risk, best-practice deviation, defense-in-depth |
| **Informational** | No direct risk, but worth noting for future reference |

4. For Critical/High findings, provide **evidence of exploitability** (R-SO-02). Theoretical findings without demonstrated impact MUST be downgraded.

**Exit Criteria:** All findings are deduplicated, verified, and classified.

---

### Phase 4: Report Generation
**Entry Criteria:** Phase 3 classification is complete.

1. Produce a **structured security audit report** (R-SO-01):

```markdown
# Security Audit Report

**Date:** [timestamp]
**Auditor:** [Agent ID]
**Scope:** [components/repos audited]
**Tools Used:** [list with versions]

## Executive Summary
- Critical: [count]
- High: [count]
- Medium: [count]
- Low: [count]
- Informational: [count]

## Findings

### [Finding ID]: [Title]
**Severity:** [Critical/High/Medium/Low/Info]
**Component:** [affected file/package]
**Evidence:** [proof of exploitability or CVE reference]
**Remediation:** [specific fix recommendation]
**Verification:** [how to confirm the fix works]

## Accepted Risks
[Any previously accepted risks with their R-SO-06 documentation]
```

2. Sort findings by severity (Critical first).
3. Each finding MUST include a concrete remediation recommendation and verification steps (R-SO-03).

**Exit Criteria:** Report is generated and reviewed.

---

### Phase 5: Remediation Planning
**Entry Criteria:** Phase 4 report is approved.

1. For **Critical/High** findings: remediation requires **human User review** before implementation (R-SO-13).
2. For **Medium/Low** findings: the agent may create remediation PRs autonomously, following the standard `L3_Bug_Fix.md` workflow for each fix.
3. For findings that will NOT be remediated (accepted risk), document the **security exception** per R-SO-06:
   - Justification for acceptance.
   - Compensating controls in place.
   - Expiration date for re-evaluation.
   - **Human approval is mandatory** for exceptions.
4. Track all remediation items as work items in the project tracker.

**Exit Criteria:** All findings have a disposition (fix, accept, defer) with appropriate approvals.

---

## Quality Gates

| Gate | Threshold | Notes |
|------|-----------|-------|
| **All scan types executed** | Per scope definition | SAST + SCA + Secrets minimum; DAST if staging available |
| **Exploitability verified** | All Critical/High | R-SO-02: no theoretical-only Critical/High |
| **Report produced** | Structured format | R-SO-01: includes evidence and remediation |
| **Critical findings remediated** | 0 open Critical | Before release |
| **Exceptions documented** | All accepted risks | R-SO-06: with human approval and expiry |
