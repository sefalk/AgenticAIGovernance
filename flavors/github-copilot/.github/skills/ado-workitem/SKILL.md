---
name: ado-workitem
description: Azure DevOps work item lifecycle guidance — matching confidence, field completeness, non-destructive updates, and link strategy.
argument-hint: '[operation: resolve|create|update|link] [item-type: bug|story|task]'
disable-model-invocation: true
---

# ADO Work Item Skill

Provider-specific guidance for Azure DevOps work item operations.

## Matching Confidence

- >= 0.75: proceed with candidate and rationale.
- 0.45-0.74: request confirmation.
- < 0.45: require explicit id or create new item.

## Clarification by Type

- Bug: observed, expected, repro, impact.
- User Story: business goal, value hypothesis, acceptance criteria.
- Task: technical objective, constraints, done criteria.

## Update Strategy

- Append or targeted rewrite only.
- Preserve prior context and ownership unless explicitly instructed.
- Prefer dedicated fields over generic description text.

## Linking Strategy

- Use native artifact links where available.
- Add related item links only when relation semantics are clear.
- If link creation is blocked by missing identifiers, mark degraded and log fallback.
