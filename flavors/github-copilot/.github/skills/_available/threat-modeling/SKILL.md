---
name: threat-modeling
description: Systematically identify security threats, attack surfaces, and mitigations during design — STRIDE methodology, data flow diagrams, risk assessment, and documentation templates.
argument-hint: '[system or feature to model] [methodology: STRIDE]'
---

# Threat Modeling

## When to Use

- When designing new systems or features
- When evaluating security posture of existing architecture
- When preparing for security audits or compliance reviews
- When architecture changes trigger a security review

## Principles

1. **Design-Time, Not Afterthought** — Threat modeling happens during
   architecture design, not after deployment.
2. **Systematic, Not Ad Hoc** — Use structured methodologies, not
   brainstorming.
3. **Safety & Security** — All systems handling user data or external
   input must undergo threat modeling.
4. **Transparency** — Threat models must be documented and reviewed.

## Techniques & Patterns

### STRIDE Methodology

| Threat | Violates | Example |
|--------|----------|---------|
| **S**poofing | Authentication | Attacker impersonates another user |
| **T**ampering | Integrity | Data modified in transit or at rest |
| **R**epudiation | Non-repudiation | User denies action (no audit trail) |
| **I**nformation Disclosure | Confidentiality | Sensitive data exposed |
| **D**enial of Service | Availability | System overwhelmed |
| **E**levation of Privilege | Authorization | Unauthorized admin access |

### Threat Modeling Process

1. Define scope (system, component, or feature).
2. Create a data flow diagram (DFD).
3. Identify threats using STRIDE at each element and trust boundary.
4. Assess risk (probability × impact).
5. Define mitigations.
6. Document in a Threat Model / ADR.
7. Update when architecture changes.

### Data Flow Diagram

```
[External User] --HTTPS--> [Web App] --SQL--> [Database]
                              |
                              |--HTTP--> [Payment API]
                              |
                              |--AMQP--> [Message Queue] --> [Email Service]

Trust boundaries:
  ─── Internet ↔ DMZ
  ─── DMZ ↔ Internal
  ─── Internal ↔ External (payment API)
```

**Threats concentrate at trust boundaries.** Focus analysis there.

### STRIDE-per-Element

| Element Type | Applicable Threats |
|-------------|-------------------|
| External entity | Spoofing |
| Process | S, T, R, I, D, E (all) |
| Data store | Tampering, Info Disclosure, DoS |
| Data flow | Tampering, Info Disclosure, DoS |

### Risk Assessment

| Probability \ Impact | Low | Medium | High |
|---------------------|-----|--------|------|
| **High** | Medium | High | Critical |
| **Medium** | Low | Medium | High |
| **Low** | Info | Low | Medium |

### Common Threats & Mitigations

| Threat | Mitigation |
|--------|------------|
| Credential theft | MFA, strong password policies, OAuth/OIDC |
| Data tampering in transit | TLS everywhere, message signing |
| Action repudiation | Comprehensive audit logging |
| Data exposure in logs | Secrets redaction, structured logging |
| DDoS | Rate limiting, CDN, auto-scaling, WAF |
| Privilege escalation | RBAC, least privilege, input validation |
| SQL injection | Parameterized queries, ORM |
| SSRF | URL allowlisting, network segmentation |

### Tools

| Tool | Type |
|------|------|
| **OWASP Threat Dragon** | Open-source, visual DFD-based |
| **Microsoft Threat Modeling Tool** | Free, STRIDE-based |
| **Threagile** | YAML-based, code-driven |

### Threat Model Document Template

```markdown
# Threat Model: [System/Feature Name]
**Version:** X | **Date:** YYYY-MM-DD | **Author:** [name]

## System Overview
[Brief description and DFD diagram]

## Trust Boundaries
1. [Boundary description]

## Threats
| ID | Threat | STRIDE | Element | Risk | Mitigation | Status |
|----|--------|--------|---------|------|------------|--------|

## Assumptions
## Out of Scope
```

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Threat model exists** | For all critical systems | Before production deployment |
| **All high/critical mitigated** | 0 unaddressed | Before launch |
| **Updated on arch change** | Yes | Triggers review |
| **Peer-reviewed** | Yes | By someone other than author |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Theater threat model** | 100-page doc nobody reads. | Keep concise. Focus on high-risk threats. |
| **Post-deployment modeling** | Done after the system is built. | Model during design. |
| **Only obvious threats** | Missing subtle attack vectors. | Use STRIDE systematically per element. |
| **No follow-through** | Threats identified, mitigations never done. | Track as tasks in risk register. |

## References

- Adam Shostack, *Threat Modeling: Designing for Security* (2014)
- OWASP Threat Modeling: https://owasp.org/www-community/Threat_Modeling
- Microsoft STRIDE: https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool
