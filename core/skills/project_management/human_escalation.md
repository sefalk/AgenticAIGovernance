---
category: project_management
applies_to: [all]
complexity: foundational
maturity: draft
version: "1.0"
last_reviewed: 2026-03-04
related: [stakeholder_communication, error_handling]
---
# Human Escalation Protocol

## Purpose

Autonomous AI agents inevitably encounter scenarios they cannot or should not resolve alone -- ambiguous requirements, missing credentials, paradoxical legacy code, or exceeding token budgets. The Human Escalation Protocol defines how an agent gracefully halts execution ("fails safe") and transfers context to a human engineer. Invoke this skill whenever progress is blocked or an iteration limit is breached.

## Principles

- **Fail-Safe & Ask First (AAIG L1):** guessing intent or forcing a brittle solution is forbidden. Halting is a valid, expected, and highly valued outcome.
- **Context Preservation:** An escalation without context is useless. The human must be able to resume exactly where the agent left off without re-reading the entire conversation history.
- **No Infinite Loops (Efficiency):** Agents must never enter a state of endless self-debate or blind retries. Reach your iteration limit, then escalate.

## Techniques & Patterns

### 1. The Iteration / Budget Check (Resource Governance)
Before executing a new step or retrying a failed test, an agent must evaluate its internal budget. If you have attempted to fix the same failing test or compile error 3 times without material progress, **you must halt**.

### 2. Generating the `ESCALATION.md`
Do not simply output "I failed" into the chat. Generate a structured text file in the repository (e.g., at the project root or in the `.aaig/` directory) named `ESCALATION.md`. This artifact persists the context for asynchronous human review.

The `ESCALATION.md` MUST contain:
1. **The Goal:** What was the original objective?
2. **The Blocker:** Specifically, what is preventing progress? (e.g., "Missing API Key", "Contradictory Business Logic in `Billing.java`").
3. **Attempted Solutions:** Briefly list what you tried that did *not* work.
4. **The Ask:** Formulate a direct, multiple-choice, or binary question for the human.

### Example Escalation File

```markdown
# ESCALATION REQUIRED: Database Migration Blocked

**Agent ID:** AAIG-Refactor-Bot
**Timestamp:** 2026-03-04

## 1. Goal
Migrate the `users` table to include the new `tier_level` column.

## 2. The Blocker
The legacy staging database contains duplicate user records that violate the new `UNIQUE` constraint on emails. I cannot proceed without mutating production data or dropping the constraint.

## 3. Attempted Solutions
- Attempted to add the constraint. Fails with `duplicate key error`.
- Attempted to write a migration script to merge users, but business logic for merge conflict resolution is undefined.

## 4. The Ask (Human Input Required)
How should I handle the duplicate legacy records?
[A] Delete the older duplicates based on `created_at`.
[B] Drop the `UNIQUE` constraint requirement for the migration.
[C] Do not proceed. Revert the migration files.
```

### 3. The Handoff
After generating the `ESCALATION.md`, the agent must notify the user, summarize the blocker in one sentence, point them to the `ESCALATION.md` file, and **stop execution** until input is received.

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Retry Limit** | Max 3 attempts | If a specific test or compilation step fails 3 times, escalate. |
| **Escalation Artifact** | Exists | Formal `ESCALATION.md` must be written to disk. |
| **Actionable Ask** | Yes | The ask must require a specific human decision, not just general help. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Silent Paralysis** | The agent stops working but doesn't explain why, leaving the human guessing. | Always generate an `ESCALATION.md` and explicitly ping the user. |
| **The "Boy-Who-Cried-Wolf"** | Escalating over trivial syntax errors easily fixed by reading a MANIFEST. | Exhaust independent research (within the 3-retry limit) before escalating. |
| **Infinite Retries** | The agent runs a failing test 45 times, burning token and compute budget. | Enforce the Hard Iteration Limit (R-SD-25) religiously. |

## See Also

- [Stakeholder Communication](../project_management/stakeholder_communication.md)
- [Error Handling](../code_quality/error_handling.md)
