---
category: devops
applies_to: [all]
complexity: intermediate
maturity: draft
version: "1.1"
last_reviewed: 2026-06-25
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

### Acceptance-Criteria Closure Gate (two-stage, post-merge)

Closure must never rest on unmerged work or acceptance-criteria assumptions.

- **Stage 1 (finalize, pre-merge):** the integration request is not yet
  merged. Post an **AC coverage map** (each acceptance criterion -> evidence
  or `UNMET`) and set at most **Resolved** — never **Closed**.
- **Stage 2 (post-merge):** only after the request is merged and every AC
  maps to merged evidence, set **Closed**. If the merge cannot be confirmed,
  defer closure (`CLOSE_PENDING_MERGE`).
- **Never bulk-close** linked items; verify acceptance criteria per item.
- The AC coverage map is the **checkable** artifact; the mapping's
  correctness is a reviewer (SOFT) judgment.

### Multi-Phase Spec Modeling

- Detect a multi-phase **container** deterministically: tracker item is an
  epic/feature type, carries a `multi-phase` tag, or already has child
  stories. Do not infer from free-text alone.
- A single user story spanning multiple phases is **mis-typed** — keep it
  open, flag the smell, and propose a feature with phase child stories
  (confirmation required) instead of closing it.
- Close the delivered phase's **child story**, never the parent; the parent
  stays open until all children are closed.

## Quality Gates

| Gate | Threshold | Notes |
|------|-----------|-------|
| Work item resolved or created | 100% | Required for tracker-enabled workflows |
| Confidence policy applied | 100% | Decision path logged |
| Type-specific fields complete | 100% | Or blocked with reason |
| Non-destructive policy respected | 100% | Reviewer check |
| References valid or pending-sync | 100% | No fabricated links |
| AC coverage map before closure | 100% | Map artifact posted before any close/resolve transition |
| Closure only against merged evidence | 100% | No Close pre-merge; defer or block otherwise |
| Multi-phase closes child not parent | 100% | Deterministic detection; parent stays open |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| Blind auto-linking | Wrong ticket updates and audit drift | Use confidence bands and confirmation |
| Description-only updates | Loses semantic structure | Map to dedicated fields where possible |
| Forced relation guesses | Creates false dependency graph | Ask/flag advisory instead |
| Silent degraded mode | Hidden integration failure | Explicitly mark pending-sync/degraded |
| Premature / bulk closure | Closes items whose AC are unmet; multi-phase work vanishes in a closed parent | Two-stage post-merge AC gate; per-item verification; close child stories, not the feature |

## See Also

- [CI/CD](../devops/ci_cd.md)
- [Configuration Management](../devops/configuration_management.md)
- [Documentation](../code_quality/documentation.md)

## References

- Azure DevOps Work Items API: https://learn.microsoft.com/azure/devops/integrate/concepts/work-items/work-item-concepts
- WIQL reference: https://learn.microsoft.com/azure/devops/boards/queries/wiql-syntax
