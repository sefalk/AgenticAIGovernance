---
name: resume
agent: coordinator
description: 'Discover paused workflows and resume via coordinator Step 0.'
tools:
  - agent
  - search
  - read
  - execute/runInTerminal
  - execute/getTerminalOutput
  - read/terminalLastCommand
  - read/terminalSelection
---

# /resume — Workflow Resume Discovery

Find all paused or in-progress workflows and present them so the human
can choose which one to resume. **Discovery only** — branch switching
stays human-controlled.

## Steps

### Step 1 -- Search for WIP Files

Look for `WIP.md` files in the project. Check the default plan directory
and any alternative conventions:

```
file_search: **/WIP.md
```

Common locations: `docs/plans/WIP.md`, or another `docs/` subdirectory
if the project uses a different convention.

Also check git branches for any that follow the `agent/*` naming pattern:

```bash
git branch --list "agent/*"
```

### Step 2 — Read Each WIP File

For each `WIP.md` found, extract:
- **Workflow ID** (from frontmatter or content)
- **Status** (`IN_PROGRESS` | `PAUSED` | `CANCELLED`)
- **Branch** name
- **Last completed step** and next action
- **Date** of last update

Skip any with status `CANCELLED` — mention them separately at the end.

### Step 3 -- Present Discovery

Format the output as:

```markdown
## Resumable Workflows

| # | Workflow ID | Branch | Status | Last Step | Next Action | Date |
|---|-------------|--------|--------|-----------|-------------|------|
| 1 | {id} | {branch} | {status} | {step} | {next} | {date} |

### How to Resume

1. Switch to the branch: `git checkout {branch}`
2. Run the coordinator: it will detect `WIP.md` at Step 0 and resume
   automatically from the recorded checkpoint.

### Cancelled Workflows
- {id} on {branch} — cancelled: {reason}
```

If no WIP files are found and no `agent/*` branches exist, report:

> No paused workflows found. All previous workflows completed or were
> never checkpointed.

### Step 4 -- Guidance

Remind the human:
- The coordinator's Step 0 automatically checks for `WIP.md` in the plan
  directory (default: `docs/plans/`)
- Branch switching is a human action -- this prompt does not switch branches
- If a WIP is stale (> 7 days), consider cancelling it and starting fresh
