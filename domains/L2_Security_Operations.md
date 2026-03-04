**Version: 1.0 | Date: 2026-03-04**
**Level: 2 | Domain: Security Operations**
**Derived from:** [L1_Core_Principles.md](../L1_Core_Principles.md) (Level 1, v3.8)

---

# Level 2 — Security Operations Domain Rules

## Purpose

This artifact derives domain-specific rules for security auditing, incident response, penetration testing, and security monitoring from the Level-1 Core Principles. These rules apply when agents are explicitly tasked with security-focused operations (not merely writing secure code — that is covered by `L2_Software_Development.md`). They are declarative constraints (SHALL/SHALL NOT) that Level-3 workflows must operationalize.

> **Note:** Rule IDs are grouped by their parent L1 principle, not assigned sequentially.

---

## Derived Rules

### From: Verifiability & Quality Assurance (L1)

**R-SO-01:** Security audits SHALL produce a structured findings report containing: finding ID, severity (Critical/High/Medium/Low/Informational), affected component, evidence, remediation recommendation, and verification steps.

**R-SO-02:** All reported vulnerabilities SHALL be verified as exploitable (or assessed for exploitability) before being classified as Critical or High. Theoretical vulnerabilities without demonstrated impact SHALL be classified as Informational until validated.

**R-SO-03:** Remediation of Critical and High severity findings SHALL be verified through re-testing. A finding SHALL NOT be marked as "Resolved" until the fix has been independently verified.

### From: Transparency/Traceability (L1)

**R-SO-04:** All security scanning activities (SAST, DAST, dependency scanning, secret scanning) SHALL produce timestamped, versioned reports stored alongside the codebase or in a dedicated security registry.

**R-SO-05:** Incident response actions SHALL be logged in a structured incident timeline: timestamp, action taken, actor (human or agent), outcome. Post-incident reviews SHALL produce a retrospective document.

**R-SO-06:** All security exceptions (accepted risks, deferred remediation) SHALL be documented with: justification, approving authority (must be a human), expiration date, and compensating controls.

### From: Safety & Security (L1)

**R-SO-07:** Penetration testing and active vulnerability scanning SHALL ONLY be performed against environments explicitly authorized for testing. Agents SHALL NOT scan production systems unless explicitly authorized by the human User with documented approval.

**R-SO-08:** Agents performing security testing SHALL NOT exfiltrate, store, or log actual customer data discovered during testing. If real data exposure is found, the agent SHALL immediately escalate per the Human Escalation Protocol (R-SD-26).

**R-SO-09:** Security scanning tools SHALL be kept updated to their latest signature/rule databases. Scans performed with outdated signatures SHALL be flagged as incomplete.

### From: Identity & Least Privilege (L1)

**R-SO-10:** Agents performing security operations SHALL use dedicated security-scoped credentials, separate from development credentials. Security tooling credentials SHALL NOT have write access to production application code.

**R-SO-11:** Access to security findings and vulnerability reports SHALL follow need-to-know. Agents SHALL NOT include vulnerability details in public-facing documentation, commit messages, or PR descriptions.

### From: Fail-Safe & Ask First (L1)

**R-SO-12:** If an agent discovers an actively exploited vulnerability or evidence of a breach during routine operations, it SHALL immediately halt its current task, escalate to the human User, and refrain from any remediation action that could alert the attacker or destroy forensic evidence.

**R-SO-13:** Automated remediation of security findings (e.g., auto-patching dependencies) SHALL only be performed for Low and Medium severity findings. High and Critical findings SHALL require human review before remediation.

### From: Continuous Improvement (L1)

**R-SO-14:** Security scanning SHALL be integrated into the CI/CD pipeline and run on every merge to the primary branch. Security SHALL NOT be treated as a periodic, manual activity.

**R-SO-15:** After each security incident, a blameless retrospective SHALL identify root causes and produce actionable improvements to prevent recurrence.

---

## Applicability

These rules apply to all security operations performed by agents governed by the AAIG framework: vulnerability assessments, penetration tests, dependency audits, incident response, and compliance checks.

## Relationship to Skills Toolbox

- R-SO-01, R-SO-02, R-SO-03 → `security_testing.md`
- R-SO-04, R-SO-09, R-SO-14 → `ci_cd.md`, `dependency_management.md`
- R-SO-07 → `threat_modeling.md`
- R-SO-08, R-SO-12 → `human_escalation.md`
- R-SO-10, R-SO-11 → `secrets_management.md`
- R-SO-06, R-SO-15 → `compliance_regulatory.md`
