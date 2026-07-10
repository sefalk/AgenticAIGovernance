---
name: af-workflow-summary
description: 'Generate a human-readable summary from a workflow handoff log YAML file.'
argument-hint: 'Optionally provide the workflow log filename (without path or extension)'
agent: coordinator
tools:
  - search
  - read
---

# Workflow Summary Generator

Read the specified workflow log YAML file and produce a concise, human-readable
summary. If no file is specified, find the most recent log in `.github/logs/`.

## Instructions

1. **Find the log file:**
   - If the user provides a filename, read it from `.github/logs/{filename}.yaml`
   - If not, list `.github/logs/` and pick the most recent `.yaml` file

2. **Read the log** and extract key information

3. **Generate a summary** using the template below (keep under 40 lines)

## Output Template

````markdown
## Workflow Summary: <workflow_id>

**Trigger:** <trigger>
**Status:** <status> | **Duration:** <duration>
**Branch:** <git_branch>

### Timeline

| Step | Agent | Action | Verdict |
|---|---|---|---|
| 1 | <agent> | <action> | n/a |
| 2 | <agent> | <action> | <verdict> |

### Files Changed
- <path> (created/modified)

### Metrics
- Tests: <passing>/<total>
- Line coverage: <line_coverage>%
- Branch coverage: <branch_coverage>%

### Retries & Escalations
- Retries: <count>
- Escalations: <count>

### Key Decisions
- <Notable decisions or rejections>
````
