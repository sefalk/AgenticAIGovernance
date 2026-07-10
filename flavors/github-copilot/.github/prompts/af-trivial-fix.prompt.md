---
name: af-trivial-fix
description: 'Run the trivial fix workflow (Implement → Review) for mechanical fixes with no domain insight.'
argument-hint: 'Describe the trivial change (typo, rename, config edit)'
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

# Trivial Fix Workflow

Run the **Trivial Fix pipeline** for a purely mechanical change. No planning
document is produced — the YAML workflow log is sufficient.

Scope: ≤ 2 files, no logic insight, purely mechanical (rename, format,
config edit, typo fix, doc correction).

Boundary heuristic: if you could explain the fix in a commit message and lose
nothing, it's a Trivial Fix. If the commit message would need a paragraph,
use `/af-quick-fix` instead.

Use the **Trivial Fix Workflow**:

1. **Implement** — use the implementer subagent to apply the mechanical fix
2. **Code Review** — use the code-critic subagent to verify quality
3. **Document** — use the documenter subagent to write the workflow log

Complexity tier is always **Trivial**. Single commit:
`[agent:coordinator] trivial fix: {description}`.

Change description: ${input:change:Describe the trivial change}
