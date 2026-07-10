---
name: af-quick-fix
description: 'Run the quick fix workflow (Investigate → Implement → Review → Document) for bug fixes where root-cause insight matters, via the coordinator agent.'
argument-hint: 'Describe the bug or small change to fix'
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

# Quick Fix Workflow

Run the **Quick Fix pipeline** for this change. This workflow includes a
lightweight root-cause investigation via the planner before implementation.
Scope: ≤ 5 files, simple code change, but the *why* matters.

For purely mechanical fixes (≤ 2 files, no domain insight), use `/af-trivial-fix`
instead.

**Proof of Failure (R-SD-24):** For bug fixes, the implementer must write a
test that **fails** in the current code **before** writing the fix. This proves
the bug exists and the test is valid. The commit sequence must be:
1. `[agent:planner] investigation doc`
2. `fix: <bug-description> [GREEN]`

**Hotfix Exception:** In a declared P1 production emergency (active data loss
or complete service outage), the two-commit Proof of Failure may be skipped if
the human User explicitly authorizes it. The missing RED test **must** be
backfilled before the next feature work begins.

Use the **Quick Fix Workflow**:

1. **Investigate** — use the planner subagent to produce an investigation doc
   (root cause, fix rationale, alternatives considered)
2. **Implement** — use the implementer subagent to fix the bug and add tests
3. **Code Review** — use the code-critic subagent to verify quality
4. **Document** — use the documenter subagent to write the workflow log

This workflow is for changes affecting ≤ 5 files with root-cause or domain
insight worth documenting. If the scope is larger or more complex, switch to
the full TDD workflow instead.

Bug / change description: ${input:bug:Describe the bug or small change}
