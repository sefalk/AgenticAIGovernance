---
name: review-code
description: 'Run a code review on specified files via the code-critic subagent.'
argument-hint: 'Which files or changes to review'
agent: coordinator
tools:
  - agent
  - search
  - read
  - execute/runInTerminal
  - execute/getTerminalOutput
  - read/terminalLastCommand
  - read/terminalSelection
---

# Code Review Workflow

Run a **Review Only** workflow — no code changes, just analysis.

Use the **Review Only Workflow**:

1. **Code Review** — use the code-critic subagent to review the specified
   files for architecture compliance, code quality, metrics, and quality gates

Report the verdict (APPROVED / REJECTED / ESCALATE) with findings.

Target: ${input:target:Which files or changes to review (e.g., 'recent changes' or 'src/utils.py')}
