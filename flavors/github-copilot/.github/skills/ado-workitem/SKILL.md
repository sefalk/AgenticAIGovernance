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

## Closure Discipline (two-stage, post-merge)

- Closure is **post-merge**. At finalize the integration PR is not yet merged,
  so set at most **Resolved** (delivered, pending merge) — never **Closed**.
- Always post an **AC coverage map** (each acceptance criterion -> evidence or
  `UNMET`) before any closure transition. It is the audit trail and the
  checkable artifact.
- Move to **Closed** only after the PR is merged and every AC maps to merged
  evidence; otherwise report `CLOSE_PENDING_MERGE` (deferred) or
  `BLOCKED_CLOSURE` (unmet AC).
- **Never bulk-close** linked items — verify AC per item.

## Multi-Phase Specs

- Detect a multi-phase **container** deterministically: WIT type `Feature`, a
  `multi-phase` tag, or existing child stories. Do not infer from prose.
- A **User Story** is a single increment; if its AC span multiple phases it is
  **mis-typed** — keep it open, flag the smell, and propose a Feature with
  phase child stories (`NEEDS_CONFIRMATION`).
- Close the delivered phase's **child story**, never the parent Feature; the
  Feature stays open until all children are Closed.
