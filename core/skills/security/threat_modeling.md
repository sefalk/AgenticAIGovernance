---
category: security
applies_to: [all]
complexity: advanced
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [secure_coding, secrets_management, security_testing, authentication_authorization]
---
# Threat Modeling

## Purpose

Threat modeling systematically identifies security threats, attack surfaces, and mitigations during the design phase -- before code is written. It answers: "What can go wrong?" and "What are we doing about it?" Invoke this skill when designing new systems, evaluating security posture, or defining Level-3 security workflows.

## Principles

- **Design-time, not afterthought:** Threat modeling happens during architecture design, not after deployment.
- **Systematic, not ad hoc:** Use structured methodologies, not "what threats can we think of."
- **Safety & Security (AAIG L1):** All systems handling user data or external input must undergo threat modeling.
- **Transparency (AAIG L1):** Threat models must be documented and reviewed.

## Techniques & Patterns

### STRIDE Methodology

Categorize threats by what they violate:

| Threat | Violates | Example |
|--------|----------|---------|
| **S**poofing | Authentication | Attacker impersonates another user |
| **T**ampering | Integrity | Attacker modifies data in transit or at rest |
| **R**epudiation | Non-repudiation | User denies performing an action (no audit trail) |
| **I**nformation Disclosure | Confidentiality | Sensitive data exposed (logs, error messages, API responses) |
| **D**enial of Service | Availability | Attacker overwhelms the system |
| **E**levation of Privilege | Authorization | User gains admin access without authorization |

### Threat Modeling Process

```
1. Define scope (system, component, or feature under analysis)
2. Create a data flow diagram (DFD)
3. Identify threats using STRIDE (at each element and trust boundary)
4. Assess risk (probability x impact)
5. Define mitigations for each threat
6. Document in a Threat Model document / ADR
7. Review and update when architecture changes
```

### Data Flow Diagram

```
[External User] --HTTPS--> [Web App] --SQL--> [Database]
                              |
                              |--HTTP--> [Payment API]
                              |
                              |--AMQP--> [Message Queue] --> [Email Service]

Trust boundaries:
  â"€â"€â"€ Internet â†" DMZ (between user and web app)
  â"€â"€â"€ DMZ â†" Internal (between web app and database)
  â"€â"€â"€ Internal â†" External (between app and payment API)
```

**Threats concentrate at trust boundaries.** Focus analysis where data crosses boundaries.

### STRIDE-per-Element

Apply STRIDE to each DFD element:

| Element Type | Applicable STRIDE Threats |
|-------------|--------------------------|
| **External entity** | Spoofing |
| **Process** | Spoofing, Tampering, Repudiation, Info Disclosure, DoS, Elevation |
| **Data store** | Tampering, Info Disclosure, DoS |
| **Data flow** | Tampering, Info Disclosure, DoS |

### Risk Assessment

| Probability \ Impact | Low | Medium | High |
|---------------------|-----|--------|------|
| **High** | Medium | High | Critical |
| **Medium** | Low | Medium | High |
| **Low** | Info | Low | Medium |

### Common Threats and Mitigations

| Threat | Mitigation |
|--------|------------|
| Credential theft (Spoofing) | MFA, strong password policies, OAuth/OIDC |
| Data tampering in transit | TLS everywhere, message signing |
| Action repudiation | Comprehensive audit logging |
| Data exposure in logs/errors | Secrets redaction, structured logging, no stack traces to users |
| DDoS | Rate limiting, CDN, auto-scaling, WAF |
| Privilege escalation | RBAC, principle of least privilege, input validation |
| SQL injection | Parameterized queries, ORM, input sanitization |
| SSRF | URL allowlisting, network segmentation |
| Insecure deserialization | Use safe serialization formats (JSON, not pickle/Java serialization) |

### Tools

| Tool | Type | Description |
|------|------|-------------|
| **OWASP Threat Dragon** | Open-source | Visual DFD-based threat modeling |
| **Microsoft Threat Modeling Tool** | Free | STRIDE-based, Windows desktop app |
| **IriusRisk** | Commercial | Automated threat modeling, CI integration |
| **Threagile** | Open-source | YAML-based, code-driven threat modeling |

### Threat Model Document Template

```markdown
# Threat Model: [System/Feature Name]
**Version:** [version]  |  **Date:** [date]  |  **Author:** [name]

## System Overview
[Brief description and DFD diagram]

## Trust Boundaries
1. [Boundary 1: description]
2. [Boundary 2: description]

## Threats

| ID | Threat | STRIDE | Element | Risk | Mitigation | Status |
|----|--------|--------|---------|------|------------|--------|
| T1 | [desc] | S | [element] | High | [mitigation] | Implemented |
| T2 | [desc] | I | [element] | Med | [mitigation] | Planned |

## Assumptions
- [Assumption 1]
- [Assumption 2]

## Out of Scope
- [What was NOT analyzed and why]
```

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Threat model exists** | For all critical systems | Required before production deployment. |
| **All high/critical threats mitigated** | 0 unaddressed | High/critical threats must be mitigated before launch. |
| **Updated on architecture change** | Yes | Any architectural change triggers threat model review. |
| **Peer-reviewed** | Review Principle | Threat models reviewed by someone other than the author. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Theater threat model** | 100-page document nobody reads or maintains. | Keep it concise. Focus on high-risk threats. Update iteratively. |
| **Post-deployment modeling** | Threat model done after the system is built. | Model during design. Retrofit if necessary but prevent for new systems. |
| **Only obvious threats** | "Attackers might guess passwords." Missing subtle threats. | Use STRIDE systematically. Walk through each DFD element. |
| **No follow-through** | Threats identified but mitigations never implemented. | Track mitigations as tasks. Review in risk register. |


## See Also

- [Secure Coding](../security/secure_coding.md)
- [Secrets Management](../security/secrets_management.md)
- [Security Testing](../testing/security_testing.md)

## References

- Adam Shostack, *Threat Modeling: Designing for Security* (2014) -- the canonical reference.
- OWASP Threat Modeling: https://owasp.org/www-community/Threat_Modeling
- Microsoft STRIDE: https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool
