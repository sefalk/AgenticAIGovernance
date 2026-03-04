**Version: 1.0 | Date: 2026-03-04**
**Level: 3 | Domain: Software Development**
**Derived from:** [L2_Software_Development.md](../L2_Software_Development.md) (Level 2)
**Operationalizes:** R-SD-01, R-SD-03, R-SD-04, R-SD-05, R-SD-21, R-SD-22, R-SD-23

---

# L3 Workflow — Code Review

## Purpose

This workflow defines the structured procedure for reviewing code changes (Pull Requests, merge requests, or equivalent). It transforms the Review Principle (L1) and the code review skill into an ordered sequence that agents must follow when acting as Reviewers.

> **Adaptation Note:** Bind `[L4-DEFINED]` placeholders during L4 Project Instantiation.

---

## Phases

### Phase 1: Pre-Review Checks (Automated)
**Entry Criteria:** A PR/MR has been submitted and CI has completed.

1. **CI Status Gate:** If the CI pipeline (build, test, lint) is not green, REJECT the review immediately. No code review begins until programmatic gates pass (R-SD-06).
2. **Size Gate:** If the PR exceeds `[L4-DEFINED: max PR size, default 500 lines]` of functional code changes, request decomposition. Monolithic PRs exhaust context windows and reduce review quality.
3. **Linked Work Item:** Verify the PR references a tracked issue/ticket (R-SD-08). If unlinked, flag for justification.

**Exit Criteria:** CI is green, PR is within size limits, work item is linked.

---

### Phase 2: Static & Security Analysis
**Entry Criteria:** Phase 1 passes.

1. Ingest static analysis results (e.g., SonarQube, CodeQL, `ruff`, `eslint`). If any Blocker or Critical findings exist, the review fails automatically (R-SD-05).
2. Run a **secret sweep** on the diff: check for credentials, API keys, PII patterns using `[L4-DEFINED: secret scanning tool]` (R-SD-11).
3. Verify **Identity & Scope**: confirm the PR author corresponds to a verifiable Agent Identity (R-SD-23). Check that any newly introduced CI tokens follow Least Privilege (R-SD-21).

**Exit Criteria:** No critical static analysis findings, no exposed secrets, identity is verified.

---

### Phase 3: Semantic Review
**Entry Criteria:** Phase 2 passes.

1. **Architectural Compliance:** Cross-reference the changes against project ADRs. New dependencies or structural changes must have an approved ADR (R-SD-02).
2. **Test Corroboration:** Verify that new logic is accompanied by new tests. Code introducing logic with zero new tests is incomplete by default (R-SD-04).
3. **Behavioral Analysis:** Review the diff for:
   - Correctness: Does the code do what the linked issue describes?
   - Maintainability: Is the code readable and well-structured? (R-SD-03)
   - Error handling: Are failure modes addressed? (R-SD-14)
   - Security: Are inputs validated at boundaries? (R-SD-13)
4. Document all findings as structured review comments.

**Exit Criteria:** All semantic concerns are documented.

---

### Phase 4: Decision
**Entry Criteria:** All findings from Phases 2-3 are documented.

1. **Approve:** If no blocking findings remain.
2. **Request Changes:** If there are blocking findings. The review artifact must list each required change with a clear rationale.
3. **Escalate:** If the reviewer and author cannot resolve a disagreement after `[L4-DEFINED: max review iterations, default 3]` rounds, escalate to the human User per R-SD-26.

**Exit Criteria:** Review decision is rendered with a documented artifact.

---

## Review Artifact Template

Every review MUST produce a structured summary:

```markdown
## Code Review Summary

**PR:** [link]
**Reviewer:** [Agent ID]
**Date:** [timestamp]

### Checks Performed
- [ ] CI/CD green
- [ ] Static analysis clean
- [ ] Secret sweep clean
- [ ] Identity & scope verified
- [ ] ADR compliance checked
- [ ] Test coverage adequate
- [ ] Error handling reviewed
- [ ] Security reviewed

### Findings
| # | Severity | File | Finding | Resolution |
|---|----------|------|---------|------------|

### Decision: [Approved / Changes Requested / Escalated]
```
