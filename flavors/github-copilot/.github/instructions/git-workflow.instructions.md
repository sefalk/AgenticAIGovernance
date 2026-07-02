---
name: 'Git Workflow'
description: 'Branch lifecycle, atomic commit strategy, and planning document workflow for agent-driven development.'
applyTo: '**'
---

# Git Workflow

These rules define how agents interact with git. They consolidate and extend
the git conventions from the [Agent Team Manifest](../MANIFEST.md).

## Cardinal Rule

**Local git is coordinator-executed; integration follows the configured path.**

The coordinator autonomously executes local, reversible git operations
(branch creation, staging specific files, committing) at reviewed
checkpoints. **Integration** into shared branches follows one of two paths
(see *Integration Paths* below):

- **Pure git (default):** remote push and merge are human-controlled.
- **Request-based (optional):** when a PR/MR provider capability is enabled,
  the coordinator pushes the feature branch and an integration worker manages
  the request; merge into shared branches happens through the request, not
  local `git merge`.

### Autonomy Boundary

| Operation | Executor | Rationale |
|---|---|---|
| `git checkout -b agent/{id}` | Coordinator | Local, fully reversible |
| `git add <specific-files>` | Coordinator | Explicit files only — never `git add .` or `-A` |
| `git commit -m "..."` | Coordinator | Local, reversible via `git reset --soft` |
| `git status`, `git diff` | Coordinator | Read-only |
| `git branch --show-current` | Coordinator | Read-only |
| `git branch --list` | Coordinator | Read-only |
| `git checkout {existing-branch}` | Coordinator | Reversible switch; verified ref only (file pathspec still prompts) |
| `git switch {branch}` | Coordinator | Branch switch never touches files |
| `git push` (pure-git default) | **Human** | Crosses local→remote boundary |
| `git push origin agent/{id}` (request-based path only) | Coordinator | Publishes feature branch for the request; never a protected branch |
| `git push` to protected branches (`dev`/`main`/`master`) | **Forbidden** | Integration is request-based, never a direct push |
| `git push --force` (any) | **Forbidden** | Destructive remote rewrite |
| `git pull` / `git merge` / `cherry-pick` / `revert` (local) | Coordinator | Reversible topology change (reflog / `ORIG_HEAD`); protected-branch push still gated |
| `git branch -d {merged, non-protected}` | Coordinator | git deletes only merged branches; ref recreatable |
| `git branch -D` (force) / delete protected | **Forbidden** | Deletes unmerged commits / protected branch |
| `git reset --hard` | **Human** | Destructive state rewrite (loses uncommitted work) |
| `git rebase` | **Human** | History rewrite risk |
| `git worktree add ../wt/{id} -b agent/{id}` | Coordinator | Local, fully reversible |
| `git worktree remove ../wt/{id}` | Coordinator | Local cleanup after human merge |
| `git worktree prune` | Coordinator | Read-write, but only prunes stale entries |
| `git worktree list` | Coordinator | Read-only |

The `block-dangerous` hook enforces this boundary as a safety net
independent of coordinator instructions. No worker agent (test-writer,
implementer, refactorer, etc.) executes git commands — only the
coordinator does. The hook is a three-tier classifier: feature-branch git
ops (`commit`, staging specific files, creating and pushing `agent/*`
branches), reversible topology changes (`pull`, `merge`, `cherry-pick`,
`revert`), merged non-protected branch deletion (`git branch -d`), and
read-only/test commands are **auto-approved** per the autonomy policy in
`.github/af-env.conf`; force pushes, pushes naming a protected branch,
`git reset --hard`, `git rebase`, force/protected branch deletion (`-D`),
and destructive shell commands are **hard-denied** (with an agent notice on
how to override deliberately).

## Integration Paths

Integration into shared branches follows exactly one path, selected by
configuration. **Pure git is the safe default.**

### Pure Git (default)

No request provider configured (`ADO_CAPABILITY_MODE=off` or no PR capability).
The coordinator commits locally; **push and merge are human-controlled**. The
workflow ends with a "ready for push" note to the human. No integration
worker runs. Most projects use this path.

### Request-Based Integration (optional)

A PR/MR provider capability is enabled (e.g. Azure DevOps via
`ado-pr-manager`). Then:

- The coordinator pushes the **feature branch** `agent/{id}` (only) to the
  remote, from the active work location (main checkout or worktree per
  `WORKTREE_ENABLED`). Never a protected branch, never force.
- An **integration worker** (no terminal/git access) opens/updates the
  request via the provider API and applies the **branch-scoped completion
  policy**:
  - **Integration branch** (e.g. `dev`): autonomous — the worker may set
    auto-complete; the platform merges once branch policies pass.
  - **Protected/release branch** (e.g. `main`): human-only — the worker
    creates the request; a human completes it.
- Merge into shared branches happens **through the request**, never via local
  `git merge`.

The completion control is a **server-side branch policy plus permission
scoping** (no policy-bypass on the agent identity) — agent prompts are
conventions, not the security boundary.

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

### Branch-to-Work-Item Association (R-SD-08)

Operationalizes core rule R-SD-08 (changes linked to a tracked work item).
Applies to Standard and Deep workflows **when tracker capability is active**
(`ADO_CAPABILITY_MODE != off`). With tracker capability off, the association
falls back to local traceability artifacts (plan/log) per R-SD-08.

1. The branch slug must contain the resolved work item id.
2. The related work item must include a branch artifact link **or** an
   explicit branch-reference comment.
3. The work item must reference the implementation plan path.
4. Missing association is a **HARD** gate failure in compliance post-flight.

### Branch Cleanup

After merge, the human deletes the feature branch. Agents do not delete
branches.

## Worktree Lifecycle

Every branch-based task runs in its own **git worktree** — an isolated
working directory backed by the same repository. This enables 3–5 tasks
to execute in parallel without branch-switching overhead or interference
with the developer's main checkout.

### Path Convention

Worktrees live **outside** the repository to avoid repo pollution:

```
{repo-root}/../wt/{workflow-id}/
```

Example: if the repo is at `~/projects/myapp`, worktrees are at
`~/projects/wt/feat-auth/`, `~/projects/wt/fix-db-pool/`, etc.

The path root is configured via `WORKTREE_DIR` in `.github/af-env.conf`
(default: `../wt`). Project `.gitignore` should include `../wt/`.

### Create (Coordinator — Step 0d)

Before the Red phase, the coordinator creates the worktree:

```bash
# Read WORKTREE_DIR from af-env.conf (default: ../wt)
git worktree add "$WORKTREE_DIR/$WORKFLOW_ID" -b "agent/$WORKFLOW_ID" dev
```

Preconditions (verified by `coordinator-pretooluse` hard gate):
1. Branch name matches `^agent/[a-z0-9-]+$`.
2. Target path does not already exist.
3. Base branch (`dev`) exists and is reachable.
4. Main repo `.git` is healthy (`git status` exits 0).

After creation:
- Verify `.github/` hooks are present in the worktree (inherited via the
  shared `.git`).
- Record worktree path in the plan metadata (`worktree: ../wt/{id}`).
- Run venv bootstrap if needed (see `scripts/setup-worktree.ps1/.sh`).

### Work (Agents run inside the worktree)

All subagents (test-writer, implementer, refactorer) execute **within the
worktree directory**. The coordinator passes the absolute worktree path
in the subagent context block:

```
Worktree: {absolute_path_to_worktree}
Branch:   agent/{workflow-id}
```

Context proof gates (enforced by `block-dangerous` and stop hooks):
- `git branch --show-current` must return `agent/{id}`.
- `git rev-parse --git-common-dir` must point to the shared `.git`.
- PWD must be inside the worktree directory.

Violation → immediate halt + escalate to human with context dump.

### Merge (Human)

The human merges from the main checkout — not from the worktree:

```bash
# In main checkout (on dev):
git merge --no-ff agent/{workflow-id}
```

**Agents do not merge, rebase, or push.** The coordinator narrates:
`"Branch agent/{id} ready for merge. Run: git merge --no-ff agent/{id}"`

### Cleanup (Coordinator — Step 8)

After the human confirms merge:

1. Verify worktree is clean: `git status --porcelain` in worktree must be empty.
2. Remove: `git worktree remove "$WORKTREE_DIR/$WORKFLOW_ID"`
3. Prune dangling references: `git worktree prune`
4. Verify removal: `git worktree list` must not contain the path.
5. Record cleanup in the workflow log.

If the worktree is dirty (uncommitted changes): **halt, escalate to human.**
Do not force-remove. Human can either commit, stash, or manually clean.

If `git worktree remove` fails with "is locked": suggest
`git worktree unlock ../wt/{id}` then retry.

### Stale Worktree Audit

At the start of each new workflow (Step 0), the coordinator:

1. Runs `git worktree list --porcelain`.
2. Checks for entries with `prunable` or missing HEAD.
3. If any found: warns the human and runs `git worktree prune` to clean them.
4. Lists remaining active worktrees so the human can see parallel workload.

### Recovery Procedures

| Problem | Diagnosis | Resolution |
|---------|-----------|------------|
| Worktree locked | `git worktree list` shows `locked` | `git worktree unlock ../wt/{id}` then `git worktree remove` |
| Worktree dirty after task | Uncommitted changes found | Human: commit, stash, or `git checkout -- .` then coordinator removes |
| Stale entry (dir missing) | `git worktree list` shows prunable | `git worktree prune` |
| Branch diverged | Long-lived worktree; base updated | Human merge `dev` into `agent/{id}` in the worktree, then continue |
| Path collision | Worktree already exists | Investigate: is an old task still running? Check with human before force-delete |

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
| Plan | planner | `[agent:planner] implementation plan: {slug — what is planned}` | Plan file in `docs/plans/` |
| Red | test-writer | `[agent:test-writer] failing tests: {module/suite — what scenarios are covered}` | New test files, `conftest.py` updates |
| Green | implementer | `[agent:implementer] make tests pass: {what was implemented, key changes}` | Production code changes |
| Refactor | refactorer | `[agent:refactorer] cleanup: {what was refactored and why}` | Structural improvements (tests still green) |
| Document | documenter | `[agent:documenter] workflow log: {workflow-id}` | Updated plan file, workflow log YAML |

### Commit Rules

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

## Worktree and VS Code

Each worktree is a valid VS Code workspace root. To open a worktree in VS Code:

```bash
code ../wt/{workflow-id}
```

Or add it as a workspace folder (`File > Add Folder to Workspace`). Hooks
from `.github/` work because they reference the shared `.git` directory —
no hook duplication needed.

Recommended `.gitignore` additions:

```gitignore
# Git worktree directories (outside repo root)
../wt/
/worktrees/
/.worktrees/
```

## Human Commit Format

Human commits follow conventional commits:

```
type(scope): description

feat(bucketing): add window-based aggregation
fix(alignment): handle null CRC values
refactor(movements): extract batch boundary repair
docs(adr): ADR-005 schema management
```
