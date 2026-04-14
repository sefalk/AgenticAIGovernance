---
name: 'Git Workflow'
description: 'Branch lifecycle, atomic commit strategy, and planning document workflow for agent-driven development.'
applyTo: '**'
---

# Git Workflow

These rules define how agents interact with git. They consolidate and extend
the git conventions from the [Agent Team Manifest](../MANIFEST.md).

## Cardinal Rule

**Local git is coordinator-executed; remote git is human-controlled.**

The coordinator autonomously executes local, reversible git operations
(branch creation, staging specific files, committing) at reviewed
checkpoints. Operations with remote or irreversible effects require
explicit human approval.

### Autonomy Boundary

| Operation | Executor | Rationale |
|---|---|---|
| `git checkout -b agent/{id}` | Coordinator | Local, fully reversible |
| `git add <specific-files>` | Coordinator | Explicit files only — never `git add .` or `-A` |
| `git commit -m "..."` | Coordinator | Local, reversible via `git reset --soft` |
| `git status`, `git diff` | Coordinator | Read-only |
| `git branch --show-current` | Coordinator | Read-only |
| `git branch --list` | Coordinator | Read-only |
| `git checkout {existing-branch}` | Coordinator | Only when human-directed |
| `git push` (any form) | **Human** | Crosses local→remote boundary |
| `git merge` | **Human** | Topology change; main protection |
| `git branch -d / -D` | **Human** | Irreversible deletion |
| `git reset --hard` | **Human** | Destructive state rewrite |
| `git rebase` | **Human** | History rewrite risk |

The `block-dangerous` hook enforces this boundary as a safety net
independent of coordinator instructions. No worker agent (test-writer,
implementer, refactorer, etc.) executes git commands — only the
coordinator does.

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

### Branch Cleanup

After merge, the human deletes the feature branch. Agents do not delete
branches.

### Branch Relevance

Before committing to an **existing** branch (not freshly created), the
coordinator must verify that the task is semantically related to the
branch's purpose:

1. Parse the branch slug for intent (e.g., `feat/006-pipeline-performance`
   → "pipeline performance").
2. Compare against the current task description.
3. If **clearly unrelated**: halt and escalate to the human. Do not commit.
4. If **related or ambiguous**: proceed.

This prevents cross-contamination of unrelated changes and ensures each
branch maintains a coherent history.

## Atomic Commit Strategy

Each commit represents **one logical unit of work**. The coordinator
executes commits at defined checkpoints after reviewer gates clear.

### Phase-to-Commit Mapping

| Phase | Agent | Commit Message | What Is Committed |
|---|---|---|---|
| Plan | planner | `[agent:planner] implementation plan` | Plan file in `docs/plans/` |
| Red | test-writer | `[agent:test-writer] failing tests` | New test files, `conftest.py` updates |
| Green | implementer | `[agent:implementer] make tests pass` | Production code changes |
| Refactor | refactorer | `[agent:refactorer] cleanup` | Structural improvements (tests still green) |
| Document | documenter | `[agent:documenter] workflow log` | Updated plan file, workflow log YAML |

### Commit Rules

1. **One commit per phase** — do not bundle Red + Green into one commit.
2. **Tests must pass** before committing (except Red phase, where tests
   must fail for the right reason).
3. **No partial commits** — each commit is self-contained and leaves the
   codebase in a consistent state.
4. **Commit messages** follow the format: `[agent:{agent-name}] {description}`.
5. **WIP checkpoints** -- if a phase is interrupted, commit a `WIP.md`
   with message: `[agent:coordinator] WIP checkpoint -- {phase}`.
   WIP.md lives in the plan directory (e.g., `docs/plans/WIP.md`).
6. **Ignore statements are standalone commits** — each new `# type: ignore`,
   `# pyright: ignore`, or `# noqa` added to production code must be its own
   isolated atomic commit. It must not be bundled with code changes or with
   other ignore additions. Commit message format:
   `[agent:{agent-name}] justify ignore: {file}:{line} {rule} -- {reason}`.
   The reason must explain *why* the suppression is warranted and why it cannot
   be avoided. The implementer/refactorer stop-hook enforces this mechanically.

## Planning Document

Every mid-to-high complexity task produces a **persisted planning document**
that serves as the living record of intent, progress, and decisions.

### Naming Convention

Plan files use a unique, descriptive filename:

```
{type}-{YYYY-MM-DD}-{slug}.md
```

- **type**: `feat`, `fix`, `refactor`, `adr`, or `review`
- **YYYY-MM-DD**: the date the plan was created
- **slug**: extracted from the branch name
  (`agent/fix-alignment-nulls` -> `fix-alignment-nulls`)

Examples:
- `feat-2026-03-10-bucketing-v2.md`
- `fix-2026-03-11-alignment-nulls.md`
- `refactor-2026-03-12-extract-ports.md`

The **coordinator** determines the filename (it knows the date and branch).

### Location

Plan files are stored in a project-specific plans directory. The default
is `docs/plans/`. The coordinator discovers the convention at Step 0:

1. If `docs/plans/` exists, use it.
2. If another `docs/` subdirectory contains prior plans, adopt that.
3. Otherwise, create `docs/plans/`.

Plans remain in this directory permanently as human-readable documentation.
There is no separate archival step.

### Lifecycle

1. **Created** by the planner (using the template in `templates/PLAN.md`)
2. **Reviewed** by the coordinator — presented to human if ≥ 4 subtasks
   or any high-risk items
3. **Committed** as the first commit on the feature branch
4. **Updated** by the implementer as subtasks complete (checked off, notes added)
5. **Finalised** by the documenter at end-of-workflow (status → COMPLETED,
   metrics filled in)

### When to Skip

Skip the planning document for:
- Trivial fixes (≤ 2 files, mechanical, no domain insight)
- Review-only workflows (no code changes)
- Plan-only workflows (the coordinator's chat output suffices)

### WIP Checkpoint

The `WIP.md` file is a recovery checkpoint, not a plan. It always uses
the literal name `WIP.md` and lives in the same directory as plan files
(e.g., `docs/plans/WIP.md`). It is deleted when the workflow completes
successfully. See `templates/WIP.md` for the template.

## Human Commit Format

Human commits follow conventional commits:

```
type(scope): description

feat(bucketing): add window-based aggregation
fix(alignment): handle null CRC values
refactor(movements): extract batch boundary repair
docs(adr): ADR-005 schema management
```
