---
category: architecture
applies_to: [all]
complexity: advanced
maturity: draft
version: "1.0"
last_reviewed: 2026-03-04
related: [human_escalation, version_control, system_design]
---
# Multi-Agent Coordination

## Purpose

When multiple autonomous agents operate concurrently within a single repository or workspace, they risk file conflicts, duplicated work, contradictory commits, and context fragmentation. This skill defines the coordination protocols that prevent these failure modes. Invoke this skill whenever two or more agents are assigned to the same codebase simultaneously.

## Principles

- **Separation of Concern (AAIG L1):** Each agent must have a clearly scoped area of responsibility. Two agents modifying the same file concurrently is a governance violation unless explicitly coordinated.
- **Transparency/Traceability (AAIG L1):** All agent-to-agent coordination events (lock acquisitions, context handoffs, conflict resolutions) must be logged in the action log.
- **Fail-Safe (AAIG L1):** If an agent detects that another agent has modified a file it is about to write, it must halt and resolve the conflict before proceeding.

## Techniques & Patterns

### 1. Branch-Per-Agent Isolation
The simplest coordination strategy. Each agent operates on its own feature branch. Conflicts are resolved at merge time via standard Git flow.

**Rules:**
- Branch naming convention: `agent/<agent-id>/<task-slug>` (e.g., `agent/aaig-refactor-bot/fix-auth-module`).
- Agents must pull the latest `main` state before starting.
- Merge conflicts are resolved by the agent whose branch is merging *second*, or escalated to the human User if the conflict is semantic (not just textual).

### 2. File-Level Advisory Locks
For agents sharing a single branch (e.g., pair-programming mode), use advisory lock files to signal intent.

**Protocol:**
1. Before modifying a file, check for `.aaig/locks/<filepath>.lock`.
2. If no lock exists, create one containing your Agent ID and timestamp.
3. After committing your changes, delete the lock file.
4. If a lock exists from another agent, **do not modify the file**. Either wait, work on a different file, or escalate.

```
# .aaig/locks/src__auth__login.ts.lock
agent_id: AAIG-Frontend-Bot
acquired: 2026-03-04T10:30:00Z
task: Refactoring login flow
```

### 3. Context Handoff Protocol
When Agent A discovers information relevant to Agent B's task (e.g., a latent bug in a shared module), it must document the finding rather than silently fixing it.

**Handoff artifact:** Create a `.aaig/handoffs/<timestamp>-<topic>.md` file containing:
- **Source Agent:** Who discovered the issue.
- **Target Agent/Role:** Who should act on it.
- **Finding:** What was discovered.
- **Recommendation:** Suggested action.

### 4. Commit Sequencing
When multiple agents contribute to the same branch:
- Each agent must `git pull --rebase` before committing.
- Commits must be atomic (one logical change per commit).
- If a rebase fails, the agent must not force-push. It must resolve the conflict locally or escalate per the Human Escalation Protocol.

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **No concurrent file modifications** | 0 conflicts | Two agents must not modify the same file without the lock protocol. |
| **Lock cleanup** | 0 stale locks | All lock files must be removed after the associated commit. |
| **Handoff acknowledgment** | All reviewed | Every handoff artifact must be read by the target agent before it is archived. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Silent Overwrite** | Agent B overwrites Agent A's changes without checking for concurrent modifications. | Enforce advisory locks or branch-per-agent isolation. |
| **Shared Mutable State** | Agents communicate through global variables, shared memory, or undocumented side channels. | All coordination must go through versioned artifacts (lock files, handoffs, Git). |
| **Heroic Merge Resolution** | An agent tries to auto-resolve complex semantic merge conflicts. | Escalate semantic conflicts to the human User. Only auto-resolve trivial textual conflicts. |
| **Context Hoarding** | Agent A discovers a bug relevant to Agent B but fixes it silently, causing Agent B to duplicate work. | Use the Handoff Protocol to share findings. |

## See Also

- [Human Escalation Protocol](../project_management/human_escalation.md)
- [Version Control](../devops/version_control.md)
- [System Design](../architecture/system_design.md)
