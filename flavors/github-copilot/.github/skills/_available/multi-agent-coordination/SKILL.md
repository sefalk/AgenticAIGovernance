---
name: multi-agent-coordination
description: Coordination protocols for multiple autonomous agents operating concurrently in a single repository — branch isolation, advisory locks, context handoffs, and commit sequencing.
argument-hint: '[scenario] — ask when multiple agents work on the same codebase'
---

# Multi-Agent Coordination

## When to Use

- When two or more agents are assigned to the same codebase simultaneously
- When planning how to avoid file conflicts between agents
- When designing handoff protocols between agent roles
- When resolving concurrent modification conflicts

## Principles

1. **Separation of Concern** — Each agent must have a clearly scoped area
   of responsibility. Two agents modifying the same file concurrently is a
   governance violation unless explicitly coordinated.
2. **Transparency / Traceability** — All agent-to-agent coordination events
   (lock acquisitions, context handoffs, conflict resolutions) must be logged.
3. **Fail-Safe** — If an agent detects that another agent has modified a
   file it is about to write, it must halt and resolve the conflict before
   proceeding.

## Techniques & Patterns

### 1. Branch-Per-Agent Isolation

The simplest coordination strategy. Each agent operates on its own feature
branch. Conflicts are resolved at merge time via standard Git flow.

**Rules:**

- Branch naming convention: `agent/<agent-id>/<task-slug>`.
- Agents must pull the latest `main` state before starting.
- Merge conflicts are resolved by the agent whose branch is merging
  *second*, or escalated to the human if the conflict is semantic.

### 2. File-Level Advisory Locks

For agents sharing a single branch (e.g., pair-programming mode), use
advisory lock files to signal intent.

**Protocol:**

1. Before modifying a file, check for `.agent/locks/<filepath>.lock`.
2. If no lock exists, create one containing your Agent ID and timestamp.
3. After committing your changes, delete the lock file.
4. If a lock exists from another agent, **do not modify the file**. Either
   wait, work on a different file, or escalate.

### 3. Context Handoff Protocol

When Agent A discovers information relevant to Agent B's task, it must
document the finding rather than silently fixing it.

**Handoff artifact:** Create a structured file containing:

- **Source Agent:** Who discovered the issue.
- **Target Agent/Role:** Who should act on it.
- **Finding:** What was discovered.
- **Recommendation:** Suggested action.

### 4. Commit Sequencing

When multiple agents contribute to the same branch:

- Each agent must `git pull --rebase` before committing.
- Commits must be atomic (one logical change per commit).
- If a rebase fails, the agent must not force-push. It must resolve the
  conflict locally or escalate.

## Quality Gates

| Gate | Threshold | Notes |
|------|-----------|-------|
| **No concurrent file modifications** | 0 conflicts | Two agents must not modify the same file without the lock protocol. |
| **Lock cleanup** | 0 stale locks | All lock files must be removed after the associated commit. |
| **Handoff acknowledgment** | All reviewed | Every handoff artifact must be read by the target agent. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Silent Overwrite** | Agent B overwrites Agent A's changes without checking. | Enforce advisory locks or branch-per-agent isolation. |
| **Shared Mutable State** | Agents communicate through undocumented side channels. | All coordination must go through versioned artifacts (locks, handoffs, Git). |
| **Heroic Merge Resolution** | An agent auto-resolves complex semantic merge conflicts. | Escalate semantic conflicts to the human. Only auto-resolve trivial textual conflicts. |
| **Context Hoarding** | Agent A discovers a bug relevant to Agent B but fixes it silently. | Use the Handoff Protocol to share findings. |

## References

- Martin Fowler, ["Feature Branch"](https://martinfowler.com/bliki/FeatureBranch.html)
- Trunk-Based Development: https://trunkbaseddevelopment.com/
