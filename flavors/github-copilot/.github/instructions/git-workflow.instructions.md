---
name: 'Git Workflow'
description: 'Core git rules every agent must know: who may run git, branch naming, and the atomic commit contract. Operational depth lives in the git-workflow skill.'
applyTo: '**'
---

# Git Workflow

How agents interact with git, consolidating and extending the conventions in
the [Agent Team Manifest](../MANIFEST.md). Only what **every** agent needs
lives here. The operational depth — autonomy boundary table, integration paths,
work-item association, planning document lifecycle, pre-commit guards, LFS — is
in the **git-workflow** skill; worktree lifecycle and troubleshooting are in
**git-worktrees**. The coordinator reads both.

## Cardinal Rule

**Only the coordinator runs git.** No worker agent (test-writer, implementer,
refactorer, critics, documenter, provider workers) executes git commands —
they change files; the coordinator stages and commits them at reviewed
checkpoints.

The coordinator autonomously executes local, reversible operations (branch
creation, staging specific files, committing). **Integration** into shared
branches is never a local push:

- **Pure git (default):** remote push and merge are human-controlled.
- **Request-based (optional):** with a PR/MR provider enabled, the coordinator
  pushes only the feature branch; an integration worker manages the request.

Hard-denied for all agents, enforced by the `block-dangerous` hook
independently of these instructions: `git push --force`, any push naming a
protected branch (`dev`/`main`/`master`), `git reset --hard`, `git rebase`,
`git branch -D`, and `git add .` / `-A`.

Full autonomy boundary and integration paths: **git-workflow** skill § 1–2.

## Branch Lifecycle

### When to Branch

Create a branch for any task that modifies code. Skip branching only for
documentation-only changes or trivial edits (< 3 lines, single file).

### Branch Naming

```
agent/{workflow-id}
```

- `{workflow-id}` is a short, descriptive slug: `fix-alignment-nulls`,
  `feat-bucketing-v2`, `refactor-extract-ports`
- The **planner** suggests the branch name; the **coordinator** creates it
- One branch per workflow — do not reuse branches across unrelated tasks
- **When tracker capability is active** (`ADO_CAPABILITY_MODE != off`), prefix
  the slug with the resolved work item id:
  `agent/{work-item-id}-{workflow-id}` (e.g. `agent/2885-fix-pipeline-pythonpath`).
  Resolve the work item **before** the branch — see the **git-workflow** skill
  § 3 (R-SD-08).

### Branch Cleanup

After merge, the human deletes the feature branch. Agents do not delete
branches.

## Atomic Commit Strategy

Each commit represents **one logical unit of work**. The coordinator
executes commits at defined checkpoints after reviewer gates clear.
Per-phase commit messages: **git-workflow** skill § 5.

1. **One commit per phase** — do not bundle Red + Green into one commit.
2. **Tests must pass** before committing (except Red phase, where tests
   must fail for the right reason).
3. **No partial commits** — each commit is self-contained and leaves the
   codebase in a consistent state.
4. **Commit messages** follow the format: `[agent:{agent-name}] {phase}: {description}`.
   The `{description}` after the colon must be specific (≥ 10 chars). Generic
   phase-only labels such as `failing tests` or `make tests pass` with no
   colon-separated description are rejected by the `coordinator-pretooluse` hook.
5. **WIP checkpoints** -- if a phase is interrupted, commit a `WIP.md`
   with message: `[agent:coordinator] WIP checkpoint -- {phase}`.
   WIP.md lives in the plan directory (e.g., `docs/plans/WIP.md`).
6. **Ignore statements are standalone commits** — each new `# type: ignore`,
   `# pyright: ignore`, or `# noqa` added to production code is its own
   isolated atomic commit, never bundled with code changes or with another
   ignore. Message format:
   `[agent:{agent-name}] justify ignore: {file}:{line} {rule} -- {reason}`,
   where the reason explains *why* the suppression is warranted and why it
   cannot be avoided. The implementer/refactorer stop-hook enforces this
   mechanically.

## Planning Document

Every mid-to-high complexity task produces a **persisted planning document** in
the project's plans directory (default `docs/plans/`), named
`{type}-{YYYY-MM-DD}-{slug}.md`. The planner creates it, the implementer
updates it, the documenter finalises it. Skip it for trivial fixes,
review-only, and plan-only workflows. Full naming, location discovery,
lifecycle, and WIP checkpoint rules: **git-workflow** skill § 6.
