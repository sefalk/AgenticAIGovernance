---
name: af-tdd-feature
description: 'Run the full TDD workflow (Plan → Red → Green → Refactor → Review → Document) via the coordinator agent.'
argument-hint: 'Describe the feature to implement'
agent: coordinator
tools:
  - agent
  - todo
  - search
  - read
  - edit
  - execute/runInTerminal
  - execute/getTerminalOutput
  - read/terminalLastCommand
  - read/terminalSelection
---

# Full TDD Feature Workflow

Run the **complete TDD pipeline** for this feature request.

**Before starting:** Check for `WIP.md` on the current branch. If found with
status `IN_PROGRESS`, resume from the last completed phase instead of starting
from scratch.

Use the **Full TDD Workflow**:

1. **Plan** — use the planner subagent to decompose into subtasks
2. **Red** — use the test-writer subagent to write failing tests
3. **Test Review** — use the test-critic subagent to review test quality
4. **Green** — use the implementer subagent to make tests pass
5. **Refactor** — use the refactorer subagent to clean up
6. **Code Review** — use the code-critic subagent to verify quality gates
7. **Document** — use the documenter subagent to write the workflow log

**If this is a pure refactor** (no new behaviour): use Refactoring Mode —
baseline green → refactor → verify green. Skip Steps 2–3.

**If the session must end early:** Commit a `WIP.md` checkpoint with the
current phase and next step.

Track progress with the todo tool. Escalate to the human if any critic
rejects 3 times or if requirements are ambiguous.

Feature request: ${input:feature:Describe the feature to implement}
