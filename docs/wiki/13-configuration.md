---
title: Configuration
type: ops-note
description: Reference for af-env.conf — the L4 binding read by all hooks and the test runner.
tags: [aaig, flavor, config, reference]
updated: 2026-07-29
sources: [flavors/github-copilot/.github/af-env.conf]
---

# Configuration

`.github/af-env.conf` is the flavor's **L4 binding**: a `KEY=value` file read by
every hook script and the canonical test runner. It is marked `[customizable]`,
so [deploy](12-deployment.md) never overwrites it. This page groups the keys by
purpose; the file itself carries authoritative inline documentation.

## Project & language

| Key | Purpose |
|---|---|
| `SRC_DIR` | Source package directory (e.g. `src`, `mpusage`) |
| `PROJECT_LANGUAGE` | Active language profile (`python`) |
| `PY_ENV_BOOTSTRAP` | Behavior when no `.venv` exists: `ask` / `always` / `off` |

## Agent autonomy

Controls the [three-tier classifier](11-hooks-and-autonomy.md):

| Key | Purpose |
|---|---|
| `AUTONOMY_LEVEL` | Default tier set: `conservative` / `balanced` / `autonomous` |
| `AUTONOMY_CAT_*` | Per-category override (`GIT_READ`, `GIT_FEATURE`, `GIT_MERGE`, `TESTS`, `FS_READ`, `FS_WRITE`, `PKG_INSTALL`, `DATABRICKS`, `CLOUD_READ`) — `auto` / `ask` / `deny` |
| `PROTECTED_BRANCHES` | Branches never pushed/merged to directly (default `main,master,dev`) |
| `WEB_FETCH_ALLOWLIST` | Domains auto-approved for the researcher |

> `FS_WRITE` is opt-in: it auto-approves *non-destructive* local writes
> (`Set-Content`, `mkdir`, `cp`/`mv`, a `> file` redirect, a single-file delete).
> Recursive/force deletes stay hard-denied regardless of the setting.

## Agent model tiers

Resolved into each subagent's `model:` at [deploy time](12-deployment.md); the
coordinator stays unpinned.

| Key | Applies to |
|---|---|
| `AF_MODEL_TIER_PREMIUM` | arbiter, code-critic (deep reasoning) |
| `AF_MODEL_TIER_BALANCED` | planner, implementer, test-critic |
| `AF_MODEL_TIER_EFFICIENT` | test-writer, refactorer, documenter, researcher, compliance-checker, `ado-*` workers |

Format: `Model Name (vendor)`; comma-separated entries become a prioritized
array. Blank = deploy's curated built-in default.

## Dependencies & quality

| Key | Purpose |
|---|---|
| `DEP_FILE` / `DEP_DEV_FILE` | Runtime / dev dependency spec files |
| `LINTING_STRICTNESS` | ruff rule set for the lint gate in the implementer and refactorer stop hooks: `minimal` / `standard` / `strict` |
| `PYLANCE_TYPE_CHECKING` | Mirrors `python.analysis.typeCheckingMode` (`off`…`strict`) |
| `NOTEBOOKS_ENABLED` | Registers the `nbstripout` git filter when `true` |

## Large-file commit guard

| Key | Purpose |
|---|---|
| `LARGE_FILE_MAX_BYTES` | Staged-blob size threshold (default `1048576` = 1 MB) |
| `LARGE_FILE_ALLOWLIST` | Comma-separated fnmatch globs exempt from the guard |

Enforced by a **real git pre-commit hook** deployed to
`.github/hooks/git/pre-commit` — see [Hooks & Autonomy](11-hooks-and-autonomy.md).

## Worktrees

| Key | Purpose |
|---|---|
| `WORKTREE_ENABLED` | Run agent workflows in isolated git worktrees |
| `WORKTREE_DIR` | Where worktrees are created (auto-computed if blank) |
| `WORKTREE_VENV_MODE` | `shared` (reuse parent `.venv`) / `isolated` |
| `WORKTREE_BRANCH_PREFIX` | Branch naming prefix (default `agent`) |

> **Limitation.** Only **one** active worktree at a time is supported — hook
> routing uses a single-path sentinel (`.github/.active-worktree`). Creating a
> second worktree while the first is active breaks routing for the first task.
> Default is `WORKTREE_ENABLED=false`.

## Deploy retention

| Key | Purpose |
|---|---|
| `BACKUP_PRUNE_DAYS` | Retention for `.af-backup-*` conflict backups (default 14; `0` disables) |

## Azure DevOps capability workers (optional)

Active only when `ADO_CAPABILITY_MODE` ≠ `off`:

| Key | Purpose |
|---|---|
| `ADO_CAPABILITY_MODE` | `off` / `optional` / `required` |
| `ADO_PROJECT` | Default ADO project |
| `ADO_WIKI_IDENTIFIER` | Default **project-wiki** id (general/project-wide docs) |
| `ADO_CODE_WIKI_PATH` | In-repo path for **code-wiki** docs (default `docs/wiki`) |
| `ADO_REPOSITORY_ID` / `ADO_REPOSITORY_NAME` | Linking helpers |
| `ADO_DEFAULT_AREA_PATH` / `_ITERATION_PATH` / `_TEAM` | Work-item routing defaults |
| `ADO_DEFAULT_TARGET_BRANCH` | PR target (default `dev`) |
| `ADO_PR_AUTOCOMPLETE_BRANCHES` / `ADO_PR_HUMAN_ONLY_BRANCHES` | Branch-scoped PR completion policy |
| `ADO_PR_MERGE_STRATEGY` | Merge strategy for autocompleted PRs (default `noFastForward`, so `git branch -d agent/*` still recognizes the branch as merged) |
| `ADO_PR_DEFAULT_REVIEWERS` | Optional default PR reviewers |
| `ADO_GATE_BRANCHES` | Branches protected by the PR build-validation gate |

The wiki routing split (`ADO_WIKI_IDENTIFIER` for project-wide vs
`ADO_CODE_WIKI_PATH` for repo-specific) is described on the
[Deployment](12-deployment.md) page and enforced by the `ado-wiki` skill.

## See also

- [Hooks & Autonomy](11-hooks-and-autonomy.md) · [Deployment](12-deployment.md) · [Agent Team](10-agents.md)
