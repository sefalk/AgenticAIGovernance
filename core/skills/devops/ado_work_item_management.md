---
category: devops
applies_to: [all]
complexity: intermediate
maturity: draft
version: "1.0"
last_reviewed: 2026-06-11
related: [ci_cd, version_control, configuration_management, documentation]
---
# Azure DevOps Work Item Management

## Purpose

Provide provider-specific guidance for managing Azure DevOps work item
lifecycle operations (resolve, create, clarify, update, link) while
preserving AAIG traceability and fallback behavior.

## Principles

- **Traceability (AAIG L1):** Every meaningful change should map to a work
  item when tracker capability is available.
- **Fail-Safe (AAIG L1):** If required tracker integration is unavailable,
  halt and escalate. If optional, use fallback traceability artifacts.
- **Least Privilege (AAIG L1):** Use minimally scoped credentials and API
  permissions for read/write operations.

## Techniques & Patterns

### Matching Confidence Bands

- >= 0.75: auto-link candidate with rationale.
- 0.45-0.74: request confirmation.
- < 0.45: require explicit id or create.

### Clarification by Work Item Type

- Bug: observed, expected, repro, impact.
- User Story: business goal, value hypothesis, acceptance criteria.
- Task: technical objective, constraints, done definition.

### Non-Destructive Update Strategy

- Append missing context; do not erase prior audit-relevant history.
- Preserve assigned owner unless explicit evidence requires reassignment.
- Prefer dedicated fields over generic description blocks when available.

### Linking Strategy

- Prefer native artifact links for branch/revision associations.
- Add relationship links only when relation semantics are clear.
- If unresolved identifiers block native linking, record explicit degraded mode.

## Quality Gates

| Gate | Threshold | Notes |
|------|-----------|-------|
| Work item resolved or created | 100% | Required for tracker-enabled workflows |
| Confidence policy applied | 100% | Decision path logged |
| Type-specific fields complete | 100% | Or blocked with reason |
| Non-destructive policy respected | 100% | Reviewer check |
| References valid or pending-sync | 100% | No fabricated links |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| Blind auto-linking | Wrong ticket updates and audit drift | Use confidence bands and confirmation |
| Description-only updates | Loses semantic structure | Map to dedicated fields where possible |
| Forced relation guesses | Creates false dependency graph | Ask/flag advisory instead |
| Silent degraded mode | Hidden integration failure | Explicitly mark pending-sync/degraded |

## See Also

- [CI/CD](../devops/ci_cd.md)
- [Configuration Management](../devops/configuration_management.md)
- [Documentation](../code_quality/documentation.md)

## References

- Azure DevOps Work Items API: https://learn.microsoft.com/azure/devops/integrate/concepts/work-items/work-item-concepts
- WIQL reference: https://learn.microsoft.com/azure/devops/boards/queries/wiql-syntax
