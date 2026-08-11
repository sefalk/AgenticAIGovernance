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
| `RETRO_DIR` at its default `.github/retros/auto/*.md` | documenter agent | **No** — ignored by `auto/.gitignore` |
| `RETRO_DIR` pointed at a tracked directory, e.g. `docs/retros` | documenter agent | **Yes** — the project's decision |

### Why this is a choice and not a rule

This directory's contents used to be classed with `.github/logs/`, on the
reasoning that both are self-improvement instrumentation rather than project
output. Measurement did not support the equivalence.

The workflow log quotes the user request **verbatim** — that is what makes it
unsafe to publish, and it is a property of the log, not of the retro. A retro
snippet is a lesson: what was retried, which gate blocked, what to do
differently. Across a real 55-file consumer corpus, the agent retros contained
no credentials, no personal or absolute paths and no URLs. Nothing in them
argued for keeping them out of version control; what argued for it was the
category they had been filed under.

So the default stays local — an existing project must not have its history
change under it on upgrade — but the destination is now `RETRO_DIR` in
`af-env.conf`. Point it at a tracked directory and retros become reviewable
project history: they survive a fresh clone, they are visible in review, and
the lessons stop being an artifact only the machine that produced them can see.

What does **not** become a choice: there is still exactly one destination. The
gates resolve the same key the documenter writes to, so a retro in the wrong
place is still detected rather than quietly accepted (issue #98). And the logs
stay local, unconditionally — the verbatim-request argument is true of them.

Related: issues #98, #27, #109, #117.

