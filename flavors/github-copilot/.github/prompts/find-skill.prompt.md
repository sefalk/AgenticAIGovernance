---
name: find-skill
description: 'Search the AF skill library by topic keyword and return matching skills with usage guidance.'
tools:
  - search
  - read
---

# /find-skill — Skill Discovery

Find relevant AF skills for a given topic, task, or question.

## Input

The user provides a topic keyword or phrase, e.g.:
- `/find-skill testing`
- `/find-skill how to validate data quality`
- `/find-skill security`

## Steps

### Step 1 — Read the Skill Index

Read `skills/INDEX.md` to get the full list of skills with descriptions
and agent assignments.

### Step 2 — Match Skills

Compare the user's query against skill names and descriptions.
Use semantic similarity, not just exact string matching.

Return **all skills** that are relevant, ranked by relevance.

### Step 3 — Present Results

For each matching skill, show:

```
### <skill-name>
- **Description:** <one-line description>
- **Referenced by:** <agent list, or "none — available on demand">
- **File:** `skills/<skill-name>/SKILL.md`
```

If no skills match, say so and suggest the user check `skills/INDEX.md`
directly or consider whether a new skill should be created.

### Step 4 — Usage Hint

After listing matches, add a brief note:

> To use a skill, ask the relevant agent to read it, or reference it
> directly with `read_file skills/<name>/SKILL.md`. Skills assigned to an
> agent are automatically available to that agent during workflows.
