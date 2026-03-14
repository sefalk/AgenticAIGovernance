---
name: human-escalation
description: Protocol for agents to gracefully halt execution and transfer context to a human when progress is blocked, ambiguous, or exceeding retry limits.
argument-hint: '[blocker description] — invoke when stuck or at iteration limit'
---

# Human Escalation Protocol

## When to Use

- When an agent's retry limit is reached (3 attempts on the same failure)
- When requirements are ambiguous and cannot be resolved by reading docs
- When a decision requires domain expertise the agent does not have
- When token budget is nearly exhausted on a complex task

## Principles

1. **Fail-Safe / Ask First** — Guessing intent or forcing a brittle
   solution is forbidden. Halting is a valid, expected, and highly valued
   outcome.
2. **Context Preservation** — An escalation without context is useless.
   The human must be able to resume exactly where the agent left off.
3. **No Infinite Loops** — Agents must never enter a state of endless
   self-debate or blind retries. Reach the iteration limit, then escalate.

## Techniques & Patterns

### 1. The Iteration / Budget Check

Before executing a new step or retrying a failed test, evaluate the
internal budget. If you have attempted to fix the same failing test or
compile error **3 times** without material progress, **you must halt**.

### 2. Structured Escalation

Do not simply output "I failed." Generate a structured escalation with:

1. **The Goal:** What was the original objective?
2. **The Blocker:** Specifically, what is preventing progress?
3. **Attempted Solutions:** What you tried that did *not* work.
4. **The Ask:** A direct, specific question for the human (multiple-choice
   or binary when possible).

#### Example

```markdown
# Escalation: Database Migration Blocked

## 1. Goal
Migrate the `users` table to include the new `tier_level` column.

## 2. The Blocker
The legacy database contains duplicate records violating the new
UNIQUE constraint on emails.

## 3. Attempted Solutions
- Attempted to add the constraint → fails with duplicate key error.
- Attempted to write a merge script → business logic for merge
  conflict resolution is undefined.

## 4. The Ask
How should I handle the duplicate legacy records?
[A] Delete the older duplicates based on `created_at`.
[B] Drop the UNIQUE constraint requirement.
[C] Do not proceed. Revert the migration files.
```

### 3. The Handoff

After generating the escalation, the agent must:
1. Summarize the blocker in one sentence.
2. Point the user to the detailed escalation.
3. **Stop execution** until input is received.

## Quality Gates

| Gate | Threshold | Notes |
|------|-----------|-------|
| **Retry Limit** | Max 3 attempts | Same test/step fails 3 times → escalate. |
| **Actionable Ask** | Yes | The ask must require a specific human decision, not just "help." |
| **Context Preserved** | Yes | Human can resume without re-reading the entire conversation. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Silent Paralysis** | Agent stops without explaining why. | Always generate a structured escalation and notify the user. |
| **Boy Who Cried Wolf** | Escalating over trivial syntax errors. | Exhaust independent research within the 3-retry limit first. |
| **Infinite Retries** | Running a failing test 45 times. | Enforce the hard iteration limit religiously. |

## References

- Fail-Safe principle — system design for graceful degradation.
