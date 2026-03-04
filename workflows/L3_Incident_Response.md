**Version: 1.0 | Date: 2026-03-04**
**Level: 3 | Domain: Security Operations**
**Derived from:** [L2_Security_Operations.md](../domains/L2_Security_Operations.md) (Level 2)
**Operationalizes:** R-SO-01, R-SO-02, R-SO-03, R-SO-05, R-SO-07, R-SO-08, R-SO-12, R-SO-13, R-SO-15

---

# L3 Workflow — Incident Response

## Purpose

This workflow defines the standard procedure for responding to security incidents, from initial detection through post-mortem. It enforces forensic preservation (R-SO-12), ensures evidence integrity, and mandates blameless retrospectives (R-SO-15).

> **Adaptation Note:** Bind `[L4-DEFINED]` placeholders during L4 Project Instantiation.

> **CRITICAL:** This workflow involves production systems and potentially sensitive data. Agent autonomy is heavily restricted. Human User approval is required at multiple gates.

---

## Phases

### Phase 1: Detect & Classify
**Entry Criteria:** An anomaly is observed (alert, log anomaly, user report, automated scan finding).

1. **Gather initial evidence:** Collect relevant logs, alerts, and metrics. Do NOT modify any production resources at this stage.
2. **Classify severity:**

| Severity | Criteria | Response Time |
|----------|----------|---------------|
| **P1 — Critical** | Active data breach, service fully compromised, PII exposure confirmed | Immediate |
| **P2 — High** | Vulnerability actively exploited, partial compromise, service degraded | `[L4-DEFINED: ≤ 4 hours]` |
| **P3 — Medium** | Vulnerability discovered but not yet exploited, potential exposure | `[L4-DEFINED: ≤ 24 hours]` |
| **P4 — Low** | Informational finding, best-practice deviation, no active risk | `[L4-DEFINED: next sprint]` |

3. **Escalate immediately** for P1/P2 incidents. Agents SHALL NOT attempt autonomous remediation of Critical or High severity incidents (R-SO-13). Notify the human User and await instructions.

**Exit Criteria:** Incident is classified, initial evidence is preserved, human is notified for P1/P2.

---

### Phase 2: Contain
**Entry Criteria:** Phase 1 classification is complete. Human User has acknowledged P1/P2 incidents.

1. **Isolate the affected component** to prevent further damage:
   - Revoke compromised credentials/tokens.
   - Block malicious IP ranges at the firewall/WAF.
   - Disable compromised accounts.
   - Isolate affected containers/instances from the network.
2. **Preserve forensic evidence** (R-SO-12):
   - Take snapshots of affected systems BEFORE remediation.
   - Export and archive relevant logs to an immutable store.
   - Do NOT destroy or overwrite any evidence.
3. **Communicate:** Update the incident timeline with all containment actions (R-SO-05).

**Exit Criteria:** Threat is contained, evidence is preserved, timeline is updated.

---

### Phase 3: Investigate & Remediate
**Entry Criteria:** Phase 2 containment is successful.

1. **Root Cause Analysis:** Determine how the breach/vulnerability occurred:
   - Identify the attack vector (e.g., unpatched dependency, misconfigured IAM, phished credentials).
   - Determine the blast radius (which systems/data were affected).
   - Assess data exposure (what was accessed, exfiltrated, or modified).
2. **Remediate:**
   - For P3/P4: Agents may apply fixes autonomously (patch dependencies, update configurations) with standard review.
   - For P1/P2: All remediation actions require **human User approval** before execution (R-SO-13).
3. **Verify the fix:** Re-test the attack vector to confirm it is no longer exploitable (R-SO-03).

**Exit Criteria:** Root cause identified, fix applied and verified, attack vector is closed.

---

### Phase 4: Recover & Validate
**Entry Criteria:** Phase 3 remediation is verified.

1. Restore affected services to normal operation.
2. Run comprehensive security scans against the remediated environment: `[L4-DEFINED: security scan commands]`.
3. Monitor the affected systems for `[L4-DEFINED: monitoring window, default 72 hours]` for signs of re-compromise or persistence mechanisms.
4. Rotate all credentials that may have been exposed during the incident.

**Exit Criteria:** Services are restored, security scans are clean, monitoring window passes.

---

### Phase 5: Post-Mortem
**Entry Criteria:** Phase 4 recovery is complete.

1. Produce a **blameless retrospective** document (R-SO-15) containing:

```markdown
# Incident Post-Mortem: [Incident Title]

**Incident ID:** [ID]
**Severity:** [P1-P4]
**Duration:** [detection time → resolution time]
**Affected Systems:** [list]

## Timeline
| Time | Action | Actor |
|------|--------|-------|

## Root Cause
[Detailed technical root cause]

## Impact
- Data affected: [description]
- Users affected: [count/scope]
- Service downtime: [duration]

## Lessons Learned
1. What went well?
2. What could be improved?
3. Where did we get lucky?

## Action Items
| # | Action | Owner | Due Date | Status |
|---|--------|-------|----------|--------|
```

2. Review the post-mortem with the team and extract **actionable preventive measures** (updated firewall rules, new monitoring alerts, patching policies).
3. Archive the incident record in the security registry.

**Exit Criteria:** Post-mortem is published, action items are tracked, incident is archived.

---

## Agent Autonomy Boundaries

| Action | Agent Can Do Autonomously | Requires Human Approval |
|--------|--------------------------|------------------------|
| Classify severity | ✅ | |
| Collect/archive logs | ✅ | |
| Block IPs at WAF | | ✅ (P1/P2) |
| Revoke credentials | | ✅ (always) |
| Patch P3/P4 vulnerabilities | ✅ | |
| Remediate P1/P2 | | ✅ (always) |
| Write post-mortem | ✅ | |
| Rotate all credentials | | ✅ (always) |
