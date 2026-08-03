# Retrospectives

Post-iteration retrospective documents. Review what worked, what didn't,
and capture action items for the next cycle.

## Template

```markdown
# Retrospective — YYYY-MM-DD

## What Went Well
- ...

## What Didn't Go Well
- ...

## Action Items
- [ ] Item 1
- [ ] Item 2

## Key Learnings
- ...
```

## Convention

- One file per retrospective cycle: `YYYY-MM-DD-retro.md`
- Reference action items in subsequent workflow plans
- Update the project instructions when learnings produce new rules

## What is committed, and what is not

| Path | Author | Tracked |
|---|---|---|
| `retros/*.md` | Human / team | **Your choice** — a team retrospective is project documentation |
| `retros/auto/*.md` | documenter agent | **No** — ignored by `auto/.gitignore` |

The split is by author, not by topic. Agent-generated snippets are
self-improvement instrumentation of the same class as `.github/logs/`: they
quote workflow triggers and describe how the framework behaved, not what the
project does. A retrospective a team wrote and agreed on is a different
artifact, and the framework does not decide its fate.

