---
name: git-workflow
description: Git autonomy boundary, integration paths (pure git vs request-based), branch/work-item association, atomic commit strategy, planning document lifecycle, and pre-commit guards. The operational depth behind the always-on git core rules.
argument-hint: '[operation] [branch]'
metadata:
  activation:
    agents: [coordinator, planner, documenter]
    priority: recommended
---

# Git Workflow

**Domain:** Git workflow / Integration / Traceability

This skill holds the operational depth behind
`instructions/git-workflow.instructions.md`, which keeps only the rules every
agent needs. Everything here is coordinator-facing (the only agent that runs
git), except *Planning Document*, which the planner and documenter also use.

For worktree creation, cleanup, and troubleshooting see the separate
**git-worktrees** skill.

## 1. Autonomy Boundary

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

## 2. Integration Paths

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

## 3. Branch-to-Work-Item Association (R-SD-08)

Operationalizes core rule R-SD-08 (changes linked to a tracked work item).
Applies to Standard and Deep workflows **when tracker capability is active**
(`ADO_CAPABILITY_MODE != off`). With tracker capability off, the association
falls back to local traceability artifacts (plan/log) per R-SD-08.

1. **Work-item first.** Resolve or create the work item **before** the branch,
   and set it to **Active** at work start. No branch is created without a
   resolved work item (tracker active).
2. **One work item per unit of work.** Each distinct unit of work gets its own
   work item — do not pin unrelated concerns (infra/dependency bumps, tooling
   fixes, analysis tasks) to whatever work item happens to be open. If a task
   spans several concerns, split them.
3. The branch slug must contain the resolved work item id.
4. The work item id in the branch slug **must equal** the work item linked by
   the pull request (no cross-attribution).
5. The related work item must include a branch artifact link **or** an explicit
   branch-reference comment, and must reference the implementation plan path.
6. Missing or mismatched association is a **HARD** gate failure in compliance
   post-flight.

### Work-Item Status Authority (Decoupling)

**Git/PR = code integration; the work-item-manager is the sole authority over
work-item status.** The two state machines are decoupled and reconnect at
exactly one point: post-merge, evidence-based reconciliation.

- The PR **never** transitions work items: the `ado-pr-manager` always passes
  `transitionWorkItems: false` in the same call that enables autocomplete (the
  azure-devops-mcp default is `true`). A fast autocomplete merge must not
  auto-close linked items or outrun a corrective call.
- Work-item lifecycle follows the commit lifecycle:
  **New → Active** (at work start, before the branch) **→ Resolved**
  (post-merge into the integration branch, with an AC→evidence map) **→ Closed**
  (only at verification / promotion, against merged evidence).
- The `ado-work-item-manager` performs every status transition; the coordinator
  triggers the post-merge reconciliation once the merge is confirmed.

## 4. Branch Relevance

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

## 5. Phase-to-Commit Mapping

| Phase | Agent | Commit Message | What Is Committed |
|---|---|---|---|
| Plan | planner | `[agent:planner] implementation plan: {slug — what is planned}` | Plan file in `docs/plans/` |
| Red | test-writer | `[agent:test-writer] failing tests: {module/suite — what scenarios are covered}` | New test files, `conftest.py` updates |
| Green | implementer | `[agent:implementer] make tests pass: {what was implemented, key changes}` | Production code changes |
| Refactor | refactorer | `[agent:refactorer] cleanup: {what was refactored and why}` | Structural improvements (tests still green) |
| Document | documenter | `[agent:documenter] workflow log: {workflow-id}` | Updated plan file, workflow log YAML |

## 6. Planning Document

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

### Size

Plans are budgeted per complexity tier in `af-env.conf` and the budget is
enforced on commit — see *Plan Budget Guard* in § 7. Trivial: no plan file at
all. Standard: subtasks with acceptance criteria, scope, risks. Deep adds the
current baseline, the implementation sequence and the rollback plan. Sections
the template does not define do not belong in a plan.

### Write Passes

The plan text is emitted **three times** before it reaches disk: the planner
returns it, the coordinator repeats it verbatim inside the documenter's
delegation prompt, and the documenter writes the file. Two of those three are
output tokens spent on text that already existed.

The cause is structural, not accidental: the planner is read-only by charter,
so the agent that produces the plan cannot be the agent that persists it, and
subagents do not share context — anything handed on must be re-emitted. This is
the price of the read-only rule, and it is charged per workflow at the full size
of the plan. Keeping the plan inside its budget is therefore worth roughly three
times its own size.

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

## 7. Pre-Commit Guards

A real git `pre-commit` hook (`.github/hooks/git/pre-commit`, enabled via
`git config core.hooksPath .github/hooks/git` — done automatically by
`bootstrap-python-env.ps1`/`.sh`) runs a set of checkers against the **staged
index blobs** (exactly what would be committed), not the working tree. This is
a real git hook, not a VS Code agent hook, so it enforces regardless of whether
a human or an agent runs `git commit`. Each checker is fail-closed on git
errors; the shim is fail-open if a checker or a Python interpreter is missing.

| Checker | Blocks | Override |
|---|---|---|
| `check-large-files.py` | Staged file above `LARGE_FILE_MAX_BYTES` | `ALLOW_LARGE_FILES=1` |
| `check-strict-json.py` | Staged `.vscode/tasks.json` that is not strict JSON | `ALLOW_JSONC=1` |
| `check-context-budget-staged.py` | Staged instruction/agent payload over the budgets in `af-env.conf` | `ALLOW_CONTEXT_BUDGET=1` |
| `check-plan-budget.py` | Staged plan document over the budget its complexity tier earns | `ALLOW_PLAN_BUDGET=1` |

**Existing clones** must re-run `bootstrap-python-env.ps1`/`.sh` (or run
`git config core.hooksPath .github/hooks/git` manually) to pick up the guards —
they are not retroactive for clones set up before this change.

**Design note:** the shim lives at `.github/hooks/git/pre-commit` (not a
repo-root `.githooks/`) so it deploys with the rest of `.github/` via the
existing `.af-manifest` `hooks/` entry — no change to the deploy payload scope
was needed.

### Large File Guard

Blocks commits that stage a file above **`LARGE_FILE_MAX_BYTES`**
(`.github/af-env.conf`, default 1 MB / 1,048,576 bytes).

**Rationale:** repo weight. Commit Plotly HTML exports in CDN mode
(~16 KB), never self-contained mode (~4.8 MB per file) — the latter was the
trigger for adding this guard.

- **Override (one-off):** `ALLOW_LARGE_FILES=1 git commit -m "..."`
  (accepts `1`/`true`/`yes`).
- **Allowlist (deliberate large files):** add a comma-separated fnmatch glob
  (repo-relative staged path) to `LARGE_FILE_ALLOWLIST` in
  `.github/af-env.conf` (e.g. `LARGE_FILE_ALLOWLIST=docs/wiki/assets/**`).
- Checker logic: `.github/hooks/scripts/check-large-files.py`. Regression
  suite: `.github/scripts/test-large-file-guard.ps1`.

### Strict JSON Guard

Blocks commits that stage a `.vscode/tasks.json` which is not parseable as
strict JSON (comments, trailing commas).

**Rationale:** VS Code accepts JSONC there, but the `createAndRunTask` agent
tool does not — a single `//` line silently disables the documented fallback
execution path for agents without terminal access. Authoring rules and where
the knowledge belongs instead: `instructions/tooling.instructions.md`.

- **Override (one-off):** `ALLOW_JSONC=1 git commit -m "..."`.
- Checker logic: `.github/hooks/scripts/check-strict-json.py`.

### Context Budget Guard

Blocks commits whose staged payload exceeds the budgets in
`.github/af-env.conf` (`AF_CONTEXT_BUDGET_TOKENS`,
`AF_CONDITIONAL_BUDGET_TOKENS`, `AF_AGENT_CONTEXT_BUDGET_TOKENS`).

**Rationale:** every always-on token is paid on every turn of every workflow.
The measurement always existed; nothing ever ran it, so the framework's own
conditional set drifted 273 tokens past its ceiling and stayed there. The
budgets carry deliberate headroom, which means the ceiling is meant to be
reached — by the change that crosses it, while its author still has the
context to decide what should have been narrowed or moved.

- **Scope:** runs only when the commit stages `copilot-instructions.md`,
  `instructions/*.md`, `agents/*.agent.md`, or the `af-env.conf` that sets the
  ceiling. Every other commit pays nothing.
- **Blind spot:** it measures the index, so a payload git does not track cannot
  be measured — and a guard with nothing to measure emits exactly what a
  passing guard emits. When the staged set is empty it checks whether git holds
  the payload at all and prints `NOT GATED` / `PARTIALLY GATED` instead of
  exiting silently, with the payload measured from disk (Copilot loads it from
  there regardless of tracking). Reported, never blocked: the exit code judges
  the commit, not the repository's configuration.
- **Override (one-off):** `ALLOW_CONTEXT_BUDGET=1 git commit -m "..."`.
- Checker logic: `.github/hooks/scripts/check-context-budget-staged.py`, which
  exports the staged payload out of the index and hands it to
  `.github/scripts/check-context-budget.py` — the measurement keeps exactly one
  definition. Regression suite: `.github/scripts/test-context-budget.ps1`.

### Plan Budget Guard

Blocks commits that stage a plan document larger than the budget its complexity
tier earns in `.github/af-env.conf` (`PLAN_BUDGET_TRIVIAL_TOKENS`,
`PLAN_BUDGET_STANDARD_TOKENS`, `PLAN_BUDGET_DEEP_TOKENS`).

**Rationale:** the plan is the largest artifact a workflow writes and the one
nobody re-reads. Measured across 29 plans in a consuming project, Standard tier
averaged ~5,100 tokens against a 4 KB template — so the size is not the
scaffolding, it is what gets written into it, and 45% of it sat in sections the
template never defines. A shorter template cannot hold a limit, because nothing
in a template says "and no more than this". A number does.

- **Scope:** every staged `*.md` under a `plans/` directory except `WIP.md`.
- **Tier:** read from the plan's own text. An unstated tier is charged the
  Standard budget — silence is not a licence for an unbounded document. The
  template's `<!-- Trivial / Standard / Deep -->` placeholder is a comment and
  states nothing.
- **Trivial is zero:** a Trivial fix is chartered to have no plan file. The rule
  predates the guard; nothing enforced it.
- **Override (one-off):** `ALLOW_PLAN_BUDGET=1 git commit -m "..."`.
- Checker logic: `.github/hooks/scripts/check-plan-budget.py`. Regression
  suite: `.github/scripts/test-plan-budget.ps1`.

### Handling Large Files with Git LFS

The allowlist is for **small, deliberate** exceptions. For *legitimately large*
binary assets that must be versioned (datasets, media, model weights, large
report bundles), do not allowlist them into the main repo — use **Git LFS**.
Git LFS stores the large file outside the main repository and commits a
lightweight **pointer** instead, keeping the repo fast and small:

```
git lfs install                 # once per machine
git lfs track "*.parquet"       # add patterns; updates .gitattributes
git add .gitattributes <file>   # commit the tracking rule + the asset
```

LFS-tracked files are replaced by a small pointer in the commit, so the
large-file guard does not trip on them. Prefer LFS over `LARGE_FILE_ALLOWLIST`
whenever the asset is genuinely large rather than an accidental oversized
export.

## 8. Human Commit Format

Human commits follow conventional commits:

```
type(scope): description

feat(bucketing): add window-based aggregation
fix(alignment): handle null CRC values
refactor(movements): extract batch boundary repair
docs(adr): ADR-005 schema management
```
