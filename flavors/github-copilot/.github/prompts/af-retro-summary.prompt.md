---
name: af-retro-summary
description: 'Summarise recent auto-generated retro snippets to surface patterns and lessons for the current task.'
tools:
  - search
  - read
---

# /af-retro-summary — Pull Workflow History

Aggregate and summarise recent retro snippets from `.github/retros/auto/` to inform
the current workflow. This is a **pull model** — only invoked on demand, not
auto-injected into every session.

## When to Use

- Before starting a workflow in an area that previously had issues
- When the coordinator is at YELLOW context budget and wants a quick recap
- When the human asks "what went wrong last time?"
- During planning to check for recurring patterns

## Steps

### Step 1 — Discover Snippets

Search for all files in `.github/retros/auto/`:

```
file_search: .github/retros/auto/*.md
```

If no snippets exist, report "No auto-retro snippets found yet" and stop.

### Step 2 — Read and Aggregate

Read all snippets (or the most recent 10 if there are many).
For each, extract:
- Workflow ID and date
- Outcome (COMPLETED, COMPLETED-WITH-ISSUES, FAILED, ESCALATED)
- Lessons learned

### Step 3 — Identify Patterns

Look for recurring themes across snippets:
- Same files causing repeated issues
- Same agents getting rejected repeatedly
- Same quality gates being blocked
- Common "what didn't go well" items

### Step 4 — Present Summary

Format the output as:

```markdown
## Retro Summary ({count} workflows reviewed)

### Recent Outcomes
| Workflow | Date | Outcome |
|----------|------|---------|
| {id} | {date} | {outcome} |

### Recurring Patterns
- {Pattern 1 — e.g. "code-critic rejected 3/5 workflows for missing type hints"}
- {Pattern 2}

### Actionable Lessons
1. {Lesson that should influence the current task}
2. {Lesson}

### Recommendation
{1-2 sentences on what to watch for in the upcoming workflow}
```

If the user asked about a specific area (e.g., "retro for movements module"),
filter the summary to relevant workflows only.
