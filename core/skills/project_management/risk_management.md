---
category: project_management
applies_to: [all]
complexity: intermediate
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [task_decomposition, stakeholder_communication]
---
# Risk Management

## Purpose

Risk management systematically identifies, assesses, and mitigates potential threats to project success. It shifts the team from reactive crisis handling to proactive threat reduction. Invoke this skill when planning projects, conducting risk assessments, or defining Level-3 governance workflows.

## Principles

- **Proactive, not reactive:** Identify risks before they become incidents. Prevention is cheaper than recovery.
- **Quantitative where possible:** Assess probability and impact with data, not gut feeling.
- **Fail-Safe (AAIG L1):** When risk materializes and the situation is uncertain, halt and ask.
- **Transparency (AAIG L1):** All identified risks, their assessments, and mitigation plans must be documented and visible.

## Techniques & Patterns

### Risk Identification

**Sources of risk:**

| Category | Examples |
|----------|---------|
| **Technical** | New technology, integration complexity, performance unknowns |
| **Schedule** | Aggressive deadlines, dependency delays, scope creep |
| **Resource** | Key person dependency, skill gaps, team availability |
| **External** | Third-party API changes, regulatory changes, vendor reliability |
| **Quality** | Insufficient testing, technical debt, unclear requirements |
| **Security** | Data breaches, vulnerabilities, compliance failures |

**Identification techniques:**
- Brainstorming in planning sessions.
- Reviewing lessons learned from similar past projects.
- Examining dependency map for fragile links.
- SWOT analysis (Strengths, Weaknesses, Opportunities, Threats).

### Risk Register

| ID | Risk | Probability | Impact | Score | Mitigation | Owner | Status |
|----|------|-------------|--------|-------|------------|-------|--------|
| R1 | Key developer leaves mid-project | Medium | High | 6 | Cross-train, document knowledge | Tech Lead | Active |
| R2 | Third-party API deprecation | Low | High | 4 | Abstract API behind adapter layer | Backend Lead | Active |
| R3 | Performance SLO not met | Medium | Medium | 4 | Early load testing, profiling sprint | SRE | Active |
| R4 | Scope creep from stakeholders | High | Medium | 6 | Formal change request process | PM | Active |

**Scoring:**

| | Low Impact (1) | Medium Impact (2) | High Impact (3) |
|---|---|---|---|
| **High Probability (3)** | 3 | 6 | 9 |
| **Medium Probability (2)** | 2 | 4 | 6 |
| **Low Probability (1)** | 1 | 2 | 3 |

Score 7-9: Immediate action required. Score 4-6: Mitigation plan needed. Score 1-3: Monitor.

### Risk Response Strategies

| Strategy | Description | When to Use |
|----------|-------------|-------------|
| **Avoid** | Eliminate the risk by changing the plan | Risk is high and avoidable (e.g., choose proven tech over experimental) |
| **Mitigate** | Reduce probability or impact | Most common strategy. Concrete actions to reduce risk. |
| **Transfer** | Shift risk to a third party | Insurance, SLAs with vendors, outsourcing |
| **Accept** | Acknowledge the risk and prepare contingency | Low-score risks, or risks where mitigation cost exceeds impact |

### Common Mitigations

| Risk | Mitigation |
|------|------------|
| Key person dependency | Cross-training, documentation, pair programming |
| New technology risk | Proof-of-concept spike, time-boxed evaluation |
| Integration risk | Early integration testing, contract tests |
| Performance risk | Load testing in CI, performance budgets |
| Scope creep | Formal change request process, prioritized backlog |
| Data loss | Automated backups, disaster recovery testing |
| Security breach | Security testing in CI, dependency scanning, penetration testing |

### Risk Review Cadence

| Activity | Frequency |
|----------|-----------|
| Risk register review | Weekly (in status meeting) |
| New risk identification | Every planning session |
| Mitigation effectiveness check | Bi-weekly |
| Full risk assessment | Per project phase / milestone |

### Contingency Planning

For high-impact risks, define a contingency plan:

```markdown
## Contingency: R1 -- Key Developer Leaves

**Trigger:** Developer gives notice or is unavailable for > 5 business days.

**Actions:**
1. Activate cross-trained backup (identified: [name]).
2. Review and prioritize open tasks; defer non-critical items.
3. Schedule knowledge transfer sessions from documentation.
4. If backup insufficient, escalate to hiring manager for temporary support.

**Owner:** Tech Lead
**Recovery time estimate:** 1-2 weeks to full productivity
```

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Risk register exists** | Yes | Maintained for every project with > 2 week duration. |
| **All high risks mitigated** | Score 7+ has active mitigation | No high-score risk without an action plan. |
| **Regular review** | Weekly minimum | Risks reviewed and updated regularly. |
| **Contingency for critical risks** | Score 9 has contingency plan | Written contingency for the highest-impact risks. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **"It won't happen to us"** | Ignoring obvious risks due to optimism bias. | Systematic risk identification. External review. |
| **Risk register as ceremony** | Created once, filed, never reviewed. | Review weekly. Update scores and mitigations. |
| **All risks, no action** | Risks identified but no mitigation assigned. | Every risk score >= 4 needs an owner and action. |
| **Crying wolf** | Everything is "high risk." Stakeholders tune out. | Use the scoring matrix honestly. Reserve "high" for genuine threats. |
| **Reactive only** | No risk management until something breaks. | Make risk identification part of every planning session. |


## See Also

- [Task Decomposition](../project_management/task_decomposition.md)
- [Stakeholder Communication](../project_management/stakeholder_communication.md)

## References

- Project Management Institute, *A Guide to the Project Management Body of Knowledge (PMBOK)* -- risk management chapter.
- Tom DeMarco & Timothy Lister, *Waltzing with Bears: Managing Risk on Software Projects* (2003).
- Hillson & Simon, *Practical Project Risk Management* (2020).
