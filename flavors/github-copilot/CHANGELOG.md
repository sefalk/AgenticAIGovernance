# Changelog

All notable changes to the Agent Framework are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!-- copilot:modified | implementer | 2026-06-11 | documented optional ADO capability workers and fallback governance -->
<!-- copilot:modified | implementer | 2026-06-30 | added optional ado-pipeline-manager capability worker -->
<!-- copilot:modified | implementer | 2026-07-01 | three-tier terminal autonomy classifier + web-fetch allowlist -->
<!-- copilot:modified | implementer | 2026-07-02 | released 1.19.0 (rolled Unreleased); added auto-version pre-commit hook -->

## [Unreleased]

### Added

- **Wiki placement routing** in `ado-wiki-manager` + `ado-wiki` skill: content
  is routed by scope — general / project-wide notes go to the **project wiki**
  (`ADO_WIKI_IDENTIFIER`), repo-specific docs are versioned in the code as a
  **code wiki** at the new configurable `ADO_CODE_WIKI_PATH` (default
  `docs/wiki`). Added `ADO_CODE_WIKI_PATH` to the `af-env.conf` template.
- **Branch-to-Work-Item Association (R-SD-08)** operationalized in
  `git-workflow.instructions.md`: when tracker capability is active
  (`ADO_CAPABILITY_MODE != off`) the branch slug carries the work item id
  (`agent/{work-item-id}-{workflow-id}`) and the work item must link the branch
  + plan path; missing association is a HARD compliance post-flight gate.
  Enforced by the `compliance-checker` and the quality-gates spec. Backflowed
  from a downstream project where it was already in use.
- **Protected-wiki (`TF402455`) handling** in `ado-wiki-manager` + `ado-wiki`
  skill: a PR-required `wikiMaster` policy no longer causes blind retries — the
  agent takes the PR route (branch + wiki page + PR, human-completed) and falls
  back to a DEGRADED handoff with ready page markdown. Documents the known
  `wiki_create_or_update_page` `branch`-param limitation. Added
  `repo_create_branch` / `repo_create_pull_request` to the worker's tools.

## [1.19.0] -- 2026-07-02

### Added

- **Three-tier terminal autonomy classifier** (`block-dangerous` hook rewrite):
  every terminal command is classified `allow` (auto-approved), `ask` (prompt),
  or `deny` (hard-blocked) instead of the previous prompt-only pattern list.
  Auto-approval is segment-based (safe only when every `;`/`&&`/`||`/`|`/newline
  segment is individually safe), branch-aware (feature-branch git auto;
  protected-branch push/reset/rebase/branch-deletion hard-denied), and fail-safe
  (grouping/subshell/`$(...)`/backticks/file-write redirects never auto-approve;
  DENY is scanned across the whole command string). Configurable via
  `AUTONOMY_LEVEL` (`conservative` | `balanced` | `autonomous`) and per-category
  `AUTONOMY_CAT_*` overrides (`GIT_READ`, `GIT_FEATURE`, `GIT_MERGE`, `TESTS`,
  `FS_READ`, `PKG_INSTALL`, `DATABRICKS`, `CLOUD_READ`) in `af-env.conf`. Cloud reads that
  touch secrets/credentials/tokens are excluded and always prompt.
  Reversible topology changes (`git pull`/`merge`/`cherry-pick`/`revert`,
  reflog-recoverable) and merged non-protected branch deletion (`git branch -d`,
  which git allows only for fully-merged branches) auto-approve at `balanced`;
  force deletion (`-D`/`--force`), `reset --hard`, and `rebase` stay denied.
  Path-invoked tools (`.venv\Scripts\pytest.exe`, `.venv/bin/ruff`, …), static
  analysis tools (`radon`/`bandit`/`flake8`/`pylint`/`vulture`/`pip-audit`),
  `Push-Location`/`Pop-Location`, and branch-aware bare `git push` (auto only
  when the current branch is a non-protected feature branch) are recognised.
- **Researcher web-fetch allowlist**: `researcher-pretooluse` auto-approves
  fetches to `WEB_FETCH_ALLOWLIST` domains (official docs) and prompts for other
  domains with an offer to add them; credential-bearing URLs no longer
  short-circuit the allowlist decision.
- New `af-env.conf` keys: `AUTONOMY_LEVEL`, `AUTONOMY_CAT_*`,
  `PROTECTED_BRANCHES`, `WEB_FETCH_ALLOWLIST`.
- **Work item board routing** — new optional `af-env.conf` keys
  `ADO_DEFAULT_AREA_PATH`, `ADO_DEFAULT_ITERATION_PATH`, `ADO_DEFAULT_TEAM`.
  The `ado-work-item-manager` now sets `System.AreaPath` / `System.IterationPath`
  from these on create so new items land on the owning team's board (previously
  new items fell to the project default area — this key existed in a downstream
  project but was never generalized). Documented in the `ado-workitem` skill,
  the core `ado_work_item_management` skill, and a new SOFT routing gate.
- **Auto-version pre-commit hook** (`.githooks/pre-commit`) — bumps the patch
  component of `VERSION` whenever `flavors/github-copilot/**` or `core/**`
  source changes and `VERSION` was not itself staged (a deliberate minor/major
  cut stages `VERSION`, so the hook skips). Prevents the version drift that
  stranded `1.18.26`. Enable once with `git config core.hooksPath .githooks`.
- **Optional `ado-pipeline-manager`** capability worker: registers/runs/monitors
  an Azure DevOps PR quality-gate pipeline via MCP and emits Build Validation
  branch-policy settings for a human to apply (no MCP tool exists for policy
  creation). Terminal-free (MCP only), gated by `ADO_CAPABILITY_MODE`, with gate
  branches read from `ADO_GATE_BRANCHES`. Integrated into the coordinator
  (roster + optional pipeline workflow) and the per-agent quality-gate exit
  gates. New optional config key `ADO_GATE_BRANCHES` in `af-env.conf`.
- **Optional `ado-pr-manager`** capability worker + **`ado-pr`** skill:
  request-based integration via Azure DevOps pull requests with a
  branch-scoped completion policy (integration branch autonomous via
  autocomplete; protected branch human-only). Terminal-free (MCP only) — the
  coordinator pushes the feature branch, the worker manages the PR.
- Two-path integration model in `git-workflow.instructions.md`: pure git
  (default; push/merge human-controlled) vs optional request-based
  integration, gated by `ADO_CAPABILITY_MODE`.
- Optional PR config keys in `af-env.conf`: `ADO_DEFAULT_TARGET_BRANCH`,
  `ADO_PR_AUTOCOMPLETE_BRANCHES`, `ADO_PR_HUMAN_ONLY_BRANCHES`,
  `ADO_PR_DEFAULT_REVIEWERS`.
- **Closure acceptance-criteria gate** (two-stage, post-merge) and
  **multi-phase spec modeling** in `ado-work-item-manager`: finalize only
  Resolves (never Closes), an AC coverage map is posted before any closure,
  closure happens post-merge against merged evidence, no bulk-close, and
  multi-phase work is modeled as a Feature with phase child stories
  (deterministic detection; mis-typed single stories are flagged, not closed).
  The `ado-pr-manager` never sets `transitionWorkItems` (no PR-driven
  auto-close).

### Changed

- **PR review hardening:** the traceability thread must be posted with a
  resolved status (so a `comment resolution = Required` policy cannot block
  the PR's own autocomplete); autocomplete is only set after the work-item
  link is confirmed (so a `linked work items = Required` policy cannot stall
  an autocompleting PR).
- **compliance-checker** now enforces the integration path post-flight
  (request-based vs pure git) as a HARD gate.
- **session-mcp-readiness** probe validates PR completion config keys
  (`ADO_DEFAULT_TARGET_BRANCH`, `ADO_PR_AUTOCOMPLETE_BRANCHES`,
  `ADO_PR_HUMAN_ONLY_BRANCHES`) when ADO capability is active.
- **ado-shared** is documented as the canonical (DRY) source for shared
  `ado-*` worker boilerplate (execution defaults, repo resolution, gate
  summary). Provider neutrality is labeled a design goal, not yet delivered.
- `block-dangerous` hook is now a three-tier autonomy classifier (see Added):
  feature-branch pushes auto-approve; force pushes and pushes naming a
  protected branch are hard-denied (previously prompt-only).
- `MANIFEST.md` git conventions and coordinator workflow are now
  integration-path aware (pure git vs request-based).

- `databricks-execution-patterns` skill: deterministic Databricks workflow
  orchestration — UC/hive_metastore detection, run-type selection, output
  retrieval, evidence gating, cluster management, and escalation rules.
- `templates/af-env.conf.databricks`: project configuration template for
  job registry, fallback cluster, and authentication profile.
- `docs/DATABRICKS_SETUP.md`: step-by-step integration guide for new projects.
- Optional Azure DevOps capability workers for work item and wiki lifecycle
  handling: `ado-work-item-manager` and `ado-wiki-manager`.
- Shared ADO integration skills for provider defaults, optional probe
  handling, and non-destructive update guidance.
- Generic governance updates for platform optionality, graceful degradation,
  and fallback traceability when ADO is unavailable or out of scope.

### Changed

- Coordinator, manifest, and quality-gate docs now treat ADO integrations as
  optional capabilities rather than hard requirements.
- Project and flavor guidance now use the provider-scoped `ado-` naming
  convention consistently.

## Versioning Rules

- **Major** — breaking changes: removed files, renamed agents, changed contract
  formats, restructured directories
- **Minor** — new capabilities: new skills, new instructions, new prompts, new
  templates, new agents
- **Patch** — fixes: typos, threshold corrections, frontmatter fixes, doc
  clarifications

---

## [1.18.26] -- 2026-04-16

### Fixed

- **Worktree-aware hook scripts** via `.github/.active-worktree` sentinel file.
  All CWD-anchored hook scripts (`implementer-stop`, `refactorer-stop`,
  `test-writer-stop`, `test-writer-pretooluse`, `refactorer-pretooluse`,
  `coordinator-posttooluse`, `coordinator-postmerge`) now resolve two paths:
  - `$mainRoot`: main checkout (derived from `$PSScriptRoot`), used for
    `.github/` files (config, scripts, test-log).
  - `$codeRoot`: active worktree path read from `.github/.active-worktree`
    when present, otherwise `$mainRoot`. Used for `git` operations, pytest,
    and source file lookups.
  Previously, all hooks used `Get-Location` (VS Code CWD = main checkout),
  so quality gates silently ran against the wrong directory when a worktree
  was active. See `ideas/feature-git-worktrees.md` §12.

- **Coordinator Step 0d** now writes `.github/.active-worktree` (absolute path)
  immediately after `git worktree add`.

- **Coordinator Step 8** now deletes `.github/.active-worktree` before removing
  the worktree, returning hooks to main-checkout mode.

- **`WORKTREE_ENABLED` default restored to `true`** (was temporarily set to
  `false` in v1.18.25-patch while the hook issue was unresolved).

### Known Limitation

- Only **one active worktree at a time** is supported by the sentinel approach.
  Parallel worktrees require Option B (auto-deploy into each WT) — see
  `ideas/feature-git-worktrees.md` §13 for the decision analysis.

## [1.18.25] -- 2026-04-15

### Added

- **Worktree Python interpreter mode config** in `.github/af-env.conf`:
  - New key: `WORKTREE_VENV_MODE=shared|isolated`.
  - Default: `shared` (reuse parent repo `.venv`).
  - `isolated` creates a dedicated `.venv` in each worktree.

### Changed

- **Coordinator Step 0d** now includes explicit Python interpreter setup policy:
  - Reads `WORKTREE_VENV_MODE`.
  - Configures `python.defaultInterpreterPath` in worktree settings.
  - Falls back from `shared` to `isolated` when parent `.venv` is missing.
  - Avoids prompting the human for interpreter selection unless both strategies fail.

- **Coordinator Step 8** now documents isolated venv cleanup before worktree removal.

- **Worktree bootstrap scripts** (`setup-worktree.ps1/.sh`) now:
  - Read `WORKTREE_VENV_MODE` from `af-env.conf`.
  - Use path-based interpreter configuration (`python.defaultInterpreterPath`).
  - Support `shared` and `isolated` execution modes without symlink/junction dependency.

### Documentation

- Updated `README.md` to document `WORKTREE_VENV_MODE` and interpreter prompt avoidance.

## [1.18.24] -- 2026-04-15

### Added

- **Optional worktree support** via `WORKTREE_ENABLED` configuration flag.
  - New config: `WORKTREE_ENABLED=true|false` in `.github/af-env.conf` (default: `true`).
  - When `false`, agent workflows run in main checkout (useful for CI/CD or single-threaded environments).
  - When `true` (default), coordinator bootstraps worktrees at Step 0d (existing behavior preserved).

- **Auto-computed worktree paths** based on project name.
  - `WORKTREE_DIR` now defaults to empty in `af-env.conf`.
  - If `WORKTREE_DIR` is empty, coordinator auto-computes:
    ```
    ../{git_repo_folder_name}_worktrees
    ```
    Example: `MP Field Data Analysis CT` → `../MP Field Data Analysis CT_worktrees`
  - Projects can still override by setting `WORKTREE_DIR` explicitly.

- **Auto-add worktree folder to VS Code workspace**.
  - When coordinator creates a worktree (Step 0d), it automatically creates or updates
    `.code-workspace` file to include the worktree folder.
  - Worktree folder appears in VS Code Explorer as a separate workspace root.
  - On cleanup (Step 8), worktree folder is removed from workspace.

### Changed

- **Coordinator Step 0d (Worktree Bootstrap):** Restructured with explicit WORKTREE_ENABLED check.
  - If disabled: proceed to Step 1 in main checkout.
  - If enabled: perform full worktree setup + VS Code workspace registration.
  - Auto-computes `WORKTREE_DIR` from repo name if not configured.
  - Added workspace folder management logic.

- **Coordinator Step 8 (Worktree Cleanup):** Updated to respect `WORKTREE_ENABLED` flag.
  - Skip cleanup if `WORKTREE_ENABLED=false`.
  - Added workspace file cleanup on removal.

- **Subagent Context Injection:** Updated `work_location` field to handle optional worktrees.
  - Context now uses `Work location: Worktree: {path}` or `Work location: Main checkout (worktrees disabled)`.

### Documentation

- Updated `.github/af-env.conf` template with comprehensive `WORKTREE_ENABLED` and `WORKTREE_DIR` docs.
- Clarified that `WORKTREE_DIR` auto-derives from project folder name if left empty.

## [1.18.7] -- 2026-04-14
---

## [1.18.23] -- 2026-04-15

### Added

- **Coordinator AF version awareness at Step 0.**
  - Coordinator reads `.github/.af-version` at the start of every workflow
    and logs the active framework version (`AF vX.Y.Z`) in its opening narration.
  - Includes a "context hygiene" notice: if a deploy happened since the
    conversation started, agents advise the human to start a new conversation
    so all agents pick up the latest instructions from disk.
  - `PLAN.md` template gains an `AF Version:` metadata field, making the
    deployed version traceable per workflow artifact.
  - Documenter YAML log schema gains an `af_version:` field.

---

## [1.18.22] -- 2026-04-15

### Added

- **Deploy hardening set (backup lifecycle + safer preflight + dry-run contract).**
  - Backup retention config key in `.github/af-env.conf`:
    `BACKUP_PRUNE_DAYS=14`.
  - Retention precedence in deploy scripts:
    `CLI override > af-env.conf > default (14)`.
  - `-UpdateHashes` / `--update-hashes` now also cleans leftover
    `.af-backup-*` conflict backups.
  - New preflight check for notebook projects:
    if `NOTEBOOKS_ENABLED=true`, `.gitattributes` must include
    `filter=nbstripout`.
  - Deploy prints warning when target repository is on `agent/*` branch.
  - Dry-run output now includes machine-readable line:
    `DRYRUN_JSON {...}` for CI/log parsing.
  - New regression smoke script:
    `.github/scripts/test-deploy-flags.ps1`.

### Changed

- `README.md` documents backup retention config and expanded quick preflight
  scope for notebook filter alignment.

---

## [1.18.21] -- 2026-04-15

### Added

- **Automatic stale backup pruning in deploy scripts.**
  - `deploy.ps1` adds `-BackupPruneDays <N>` (default: `14`, `0` disables).
  - `deploy.sh` adds `--backup-prune-days <N>` / `-b <N>` with same behavior.
  - During deploy, stale `.af-backup-*` directories in the target root older
    than the configured threshold are pruned automatically.
  - Current run backup behavior remains unchanged: conflict backups are still
    preserved for manual recovery.

---

## [1.18.20] -- 2026-04-15

### Added

- **Jupyter notebook output stripping anchored in AF (`NOTEBOOKS_ENABLED`).**
  - New `NOTEBOOKS_ENABLED=false` key in `af-env.conf` template. Set to `true`
    for Python projects using Jupyter notebooks.
  - `bootstrap-python-env.ps1` / `.sh` now run `nbstripout --install` when
    `NOTEBOOKS_ENABLED=true`, registering the git clean filter automatically on
    every clone/environment setup. This prevents notebook outputs from dirtying
    git status after cells are run.
  - Warns if `.gitattributes` is missing the `filter=nbstripout` entry.
  - New reference template: `.github/templates/gitattributes-notebooks.txt`.

---

## [1.18.19] -- 2026-04-15

### Added

- **Recommended deployment policy documented in README.**
  Added an explicit split between:
  - developer iteration mode (`-Preflight` / `--preflight`, quick)
  - release handoff mode (`-RequirePreflight` / `--require-preflight`, full)

  This formalizes when preflight is advisory vs when it is a hard gate.

---

## [1.18.18] -- 2026-04-15

### Added

- **Deploy preflight checks in both deploy scripts.**
  - PowerShell: `deploy.ps1` now supports:
    - `-Preflight` (run checks, non-blocking)
    - `-RequirePreflight` (run checks, block on failure)
    - `-PreflightMode quick|full` (default: `quick`)
  - Bash: `deploy.sh` now supports:
    - `--preflight` (run checks, non-blocking)
    - `--require-preflight` (run checks, block on failure)
    - `--preflight-mode quick|full` (default: `quick`)

### Preflight Profiles

- `quick`:
  - hook integration tests (`.github/scripts/test-hooks.ps1`)
  - skills validation (`.github/scripts/validate-skills.py`)
  - tool audit (`.github/scripts/audit-tools.ps1`)
- `full`:
  - quick profile + worktree integration tests (`.github/scripts/test-worktree-scripts.ps1`)

### Notes

- `-RequirePreflight` / `--require-preflight` provides a true deployment gate.
- Optional preflight mode still reports failures but allows deployment to continue.

---

## [1.18.17] -- 2026-04-14

### Added

- **Python environment bootstrap scripts**
  - `.github/scripts/bootstrap-python-env.ps1`
  - `.github/scripts/bootstrap-python-env.sh`
  Creates `.venv` when missing, upgrades pip/setuptools/wheel, and installs
  runtime + dev dependencies from `af-env.conf`.

- **Coordinator pretooluse bootstrap interception** (configurable)
  - New config keys in `.github/af-env.conf`:
    - `PROJECT_LANGUAGE=python`
    - `PY_ENV_BOOTSTRAP=ask|always|off` (default: `ask`)
  - In Python projects, when `.venv` is missing and coordinator runs
    Python-related terminal commands, the hook now:
    - `ask`: requests human approval to run bootstrap
    - `always`: auto-runs bootstrap script before continuing
    - `off`: disables interception

### Changed

- `README.md` prerequisites now document bootstrap behavior.
- `.github/.af-manifest` now includes bootstrap scripts.

---

## [1.18.16] -- 2026-04-14

### Fixed

- **HARD gate consistency for linting:** `refactorer-stop.ps1/.sh` now blocks
  handoff when linting cannot run (`ruff` missing), instead of reporting PASS
  with a `BLOCKED` lint status. This aligns behavior with the Quality Gate
  model for BLOCKED hard gates.

- **Dependency guidance sanitization:**
  - `README.md` now marks `ruff` as required (not optional) because the
    refactorer linting gate is hard-enforced.
  - `.github/af-env.conf` comments now state that missing `ruff` blocks
    refactorer handoff.

### Verification

- Hook integration suite: **53/53 PASS**
- Skills validation: **51/51 PASS**
- Tool audit: all registered tools valid; no duplicate tool definitions detected.

---

## [1.18.15] -- 2026-04-14

### Fixed

- **Hook test regressions (3 cases):** `test-hooks.ps1` still asserted `Allow` for
  test-writer/refactorer file operations on `main`. Since v1.18.10 the branch-context
  gate correctly denies those — tests updated to `Assert-Deny` with accurate descriptions.
  Suite now passes 53/53 (was 50/53).

- **`git-worktrees` SKILL.md missing YAML frontmatter:** Skills validator reported
  `invalid or missing YAML frontmatter`. Added `name`, `description`, and
  `argument-hint` frontmatter block. Skills validation now passes 51/51.

- **Refactorer pass message inaccuracy:** Stop hooks claimed `linting clean` even when
  ruff was not installed (BLOCKED) or the gate was skipped. Both `refactorer-stop.ps1`
  and `refactorer-stop.sh` now track a `$lintStatus` / `lint_status` variable
  (`clean` | `BLOCKED (ruff not installed)` | `skipped (script/python not available)`
  | `no src changes`) and emit it in the `systemMessage`.

- **CHANGELOG wrong date:** Entry `[1.18.7]` had date `2026-06-27` (future). Corrected
  to `2026-04-14`.

---

## [1.18.14] -- 2026-04-14

### Changed

- **Default linting strictness is now strict.**
  `LINTING_STRICTNESS` in `af-env.conf` now defaults to `strict` instead of
  `standard`, so refactorer lint hard-gates use the full rule set by default.

---

## [1.18.13] -- 2026-04-14

### Added

- **Linting Hard Gate — `scripts/check-python-linting.py`.**
  Dependency-light ruff wrapper that enforces linting quality on changed
  source files during the Refactor phase.
  Reads `LINTING_STRICTNESS` from `af-env.conf`:
  - `minimal` → F8 (unused imports + undefined names)
  - `standard` → E,F,I (+ pycodestyle errors + isort)
  - `strict` → E,F,I,B,UP,SIM,C90 (+ bugbear, pyupgrade, simplify, complexity)
  Exit 0 = pass, 1 = ruff not installed (BLOCKED — advisory skip, not deny), 2 = fail.

- **`refactorer-stop.ps1/.sh` — Gate 5 (Linting).**
  Calls `check-python-linting.py` on all changed `SRC_DIR/**/*.py` files.
  HARD gate: if exit 2, blocks with `ruff check --fix` remediation hint.
  BLOCKED state (ruff missing) is advisory — does not deny the commit.

- **`af-env.conf` template — two new configurable keys:**
  - `LINTING_STRICTNESS=standard` — controls ruff rule set
  - `PYLANCE_TYPE_CHECKING=strict` — documents Pylance strictness for agents

- **`.vscode/settings.json` — `python.analysis.typeCheckingMode: "strict"` default.**
  Anchors Pylance strict type checking in the workspace settings.
  Projects can override per `[customizable]` convention.

- **`quality-gates.instructions.md` — Refactorer linting HARD gate.**
  Explicitly documents the new gate: `check-python-linting.py` on changed
  source files; BLOCKED (not FAIL) if ruff is absent.

---

## [1.18.12] -- 2026-04-14

### Added

- **Git Worktrees — Phase 4: Integration Tests.**

  **`scripts/test-worktree-scripts.ps1`**
  19 integration tests covering the full lifecycle of `setup-worktree.ps1` and `cleanup-worktree.ps1`.
  Creates isolated temp git repos and exercises:
  - Setup: valid IDs, parallel worktrees, validation gates (bad slugs, collisions, bad base branch)
  - Cleanup: clean removal, unregistered IDs, dirty worktree blocking, force-remove override
  - Round-trip: create → [work implied] → cleanup → verify purged

  All tests run in isolation with no side effects (temp repos auto-deleted).
  Exit: 0 = all passed, 1 = failures.

  **`scripts/cleanup-worktree.ps1` — `-Force` fix:**
  The `-Force` flag now **skips the dirty check**, allowing safe recovery removal
  of abandoned/corrupted worktrees. Prints confirmation and proceeds directly to
  `git worktree remove --force`.

  **Feature Status: COMPLETE**
  - Phase 1 ✅ Spec + documentation
  - Phase 2 ✅ Hard gates (pre-tool + post-merge hooks)
  - Phase 3 ✅ Bootstrap & cleanup scripts (setup-worktree, cleanup-worktree)
  - Phase 4 ✅ Integration tests (19 cases, 100% pass)
  All four phases deployed. Worktree workflow ready for production use.

---

## [1.18.11] -- 2026-04-14

### Added

- **Git Worktrees — Phase 3: Bootstrap & Cleanup Scripts.**

  **`scripts/setup-worktree.ps1/.sh`**
  Human-runnable script to bootstrap a new agent worktree.
  Reads `WORKTREE_DIR` / `WORKTREE_BRANCH_PREFIX` from `af-env.conf`.
  Steps: validates workflow ID slug, stale worktree audit + prune,
  path collision guard, base branch health check, `git worktree add`,
  venv bootstrap (symlink/junction to main `.venv`, or fresh install
  via `run-deps` if no shared venv), hooks accessibility check.
  Prints exact path + `code "<path>"` open command on success.

  **`scripts/cleanup-worktree.ps1/.sh`**
  Safe coordinator/human-runnable script to remove a worktree after merge.
  Steps: verifies worktree is registered in `git worktree list`,
  checks `git status --porcelain` (empty = clean), removal via
  `git worktree remove` (with optional `--force`), prune, verification.
  On dirty worktree: halts with actionable options (commit/discard/stash).
  On locked worktree: prints `git worktree unlock` command.

  **`.af-manifest`** — all 4 scripts registered.

  **Not yet implemented (Phase 4):** Integration tests.

---

## [1.18.10] -- 2026-04-14

### Added

- **Git Worktrees — Phase 2: Hard-Gate Hooks.**

  **`coordinator-pretooluse.ps1/.sh` — Worktree Creation Gate (HARD)**
  When the coordinator runs `git worktree add`, the hook validates:
  - Branch name matches `^agent/[a-z0-9-]+$` — rejects invalid slugs.
  - Worktree path does not already exist — prevents collision with running tasks.
  - Main repository is healthy (`git status` exit 0) — halts on corrupt repo state.
  On any violation: `deny` decision with a specific remediation message.

  **`test-writer-pretooluse.ps1/.sh` — Branch Context Proof (HARD)**
  Before any file edit/create, verifies `git branch --show-current` returns
  `agent/*`. Blocks if running on `main`, `dev`, or any non-agent branch.
  Error includes worktree setup reminder (Step 0d).

  **`refactorer-pretooluse.ps1/.sh` — Branch Context Proof (HARD)**
  Same check as test-writer. Applied before both the no-new-files gate
  and any file edit, so context is verified regardless of tool type.

  **`coordinator-postmerge.ps1/.sh` (new) — Worktree Audit at Session End**
  Fires on coordinator Stop event. Lists all active `agent/*` worktrees
  with their paths and branch names. Warns about prunable stale entries.
  Added to coordinator.agent.md Stop hooks.

  **`.af-manifest`** — `coordinator-postmerge.ps1/.sh` registered.

  **Not yet implemented (Phases 3–4):** `setup-worktree` and
  `cleanup-worktree` scripts; integration tests.

---

## [1.18.9] -- 2026-04-14

### Added

- **Git Worktrees — Phase 1: Spec & Skill.** Enables parallel agent task
  execution. Each `agent/{id}` task runs in an isolated `../wt/{id}` worktree
  backed by the shared `.git`. Human’s main checkout stays on `dev` and is
  never disturbed.

  **`git-workflow.instructions.md`**
  - Expanded Autonomy Boundary table: `git worktree add/remove/prune/list`
    are now coordinator-permitted local operations.
  - New section **Worktree Lifecycle:** path convention (`../wt/{id}`),
    Create / Work / Merge / Cleanup lifecycle, context proof requirements,
    stale worktree audit, and full recovery table (locked, dirty, diverged,
    stale, path collision).
  - New section **Worktree and VS Code:** how to open worktrees as workspace
    folders, `.gitignore` recommendations.

  **`coordinator.agent.md`**
  - New **Step 0d: Worktree Bootstrap** — creates the worktree before Red
    phase; reads `WORKTREE_DIR` from `af-env.conf`; checks for stale trees;
    records worktree path in plan metadata.
  - New **Step 8: Worktree Cleanup** — after human confirms merge; verifies
    clean status; removes + prunes; narrates result.
  - Subagent context injection now includes `Worktree: {path}` and
    `Branch: agent/{id}` so all agents know their execution context.
  - Phase Checkpoint #1 updated to show `git worktree add` as the canonical
    branch creation path.

  **`af-env.conf`** (template defaults)
  - `WORKTREE_DIR=../wt` — sibling path to avoid repo pollution.
  - `WORKTREE_BRANCH_PREFIX=agent` — consistent with existing branch convention.

  **`skills/git-worktrees/SKILL.md`** (new)
  - 7-section practical guide: concepts, key commands, lifecycle,
    troubleshooting (7 common problems + resolutions), verification
    patterns, configuration reference, `.gitignore` recommendations,
    limitations and edge cases (OneDrive, submodules, file watchers).

  **`skills/INDEX.md`** — entry #17; agent matrix entry for coordinator.
  **`copilot-instructions.md`** — skills table entry added.
  **`.af-manifest`** — `skills/git-worktrees/SKILL.md` registered.

  **Not yet implemented (Phases 2–4):** Hard-gate hooks for worktree
  creation preconditions and context proof; `setup-worktree` and
  `cleanup-worktree` scripts; integration tests. See
  `ideas/feature-git-worktrees.md` for the full roadmap.

---

## [1.18.8] -- 2026-04-14

### Fixed

- **Root cause: generic commit messages from test-writer and implementer.**
  The Phase-to-Commit Mapping table and Phase Checkpoints in
  `coordinator.agent.md` showed commit messages as **literal complete strings**
  (`"[agent:test-writer] failing tests"`) rather than templates requiring a
  colon-separated description. The coordinator followed the spec correctly —
  the spec was wrong.

### Changed

- **`git-workflow.instructions.md` — Phase-to-Commit Mapping:** All 5 phase
  messages now show mandatory `{description}` suffixes after a colon separator:
  `[agent:test-writer] failing tests: {module/suite — what scenarios are covered}`.
- **`git-workflow.instructions.md` — Commit Rule 4:** Tightened to require
  `[agent:name] {phase}: {description}` format. States that generic phase-only
  labels are rejected by the hook.
- **`coordinator.agent.md` — Phase Checkpoints:** All 7 phase commit message
  examples updated to show required `{description}` suffix.

### Added

- **Hard gate — `coordinator-pretooluse.ps1` and `.sh`:** `run_in_terminal`
  calls containing `git commit -m "..."` are now intercepted. The hook rejects
  commit messages that match `[agent:name] phase` with no `: {description}` of
  ≥ 10 chars. Exempt patterns: `WIP checkpoint`, `task cancelled`,
  `justify ignore` (already validated by their own gates). On rejection the
  coordinator receives a `deny` decision with the required format and a
  concrete example.
- **`coordinator-pretooluse.sh`:** The bash hook previously had no terminal
  interception at all (pytest block existed only in the PS1 version). This
  release adds full terminal handling parity: pytest block + commit message
  validation.


### Added

- **`check-python-quality.py` — `# noqa` hygiene:** Checker now enforces that
  every `# noqa` suppression includes an explicit rule code (`# noqa: E501`) and
  a justification comment of at least 8 characters. Mirrors existing
  `# type: ignore` and `# pyright: ignore` hygiene.
- **Atomic ignore commit enforcement (4 stop hooks):** `implementer-stop.ps1/sh`
  and `refactorer-stop.ps1/sh` now inspect the staged diff and block when:
  - More than one new ignore statement appears in the same commit.
  - A new ignore statement is bundled with other code changes.
  Agents receive a clear `block` decision with the required commit message
  format: `[agent:name] justify ignore: file:line RULE -- reason`.
- **Git Workflow Rule 6:** Added Commit Rule 6 to `git-workflow.instructions.md`
  formalising the standalone-commit requirement for every `# type: ignore`,
  `# pyright: ignore`, or `# noqa` added to production code.

---

## [1.18.6] -- 2026-04-07

### Removed

- **Hardcoded model definitions** — removed `model:` fields from all 10 worker
  agents (implementer, test-writer, refactorer, planner, code-critic, researcher,
  test-critic, arbiter, documenter, compliance-checker). Previously these listed
  tiered prioritized models (Tier 1-3) that required manual updates on company
  model releases.

### Changed

- **Model selection:** All agents now use the user's selected model in Copilot Chat.
  This eliminates maintenance burden and ensures zero downtime on model availability
  changes.
- **README:** Updated "Model Prioritization" section to explain new behavior and
  legacy reference.

### Rationale

- Company model updates happen frequently; hardcoding in 11 files created
  drift risk and maintenance overhead.
- User-driven model selection is simpler, more flexible (e.g., A/B testing,
  cost optimization), and future-proof.
- VS Code's fallback behavior handles unavailable models automatically.

## [1.18.5] -- 2026-04-07

### Changed

- **Hook configuration transition** — wire formerly orphaned hooks (block-dangerous,
  scan-secrets, session-context, stop-tests) into agent frontmatter instead of
  relying on `.json` files. Coordinator now enforces 4 lifecycle events (SessionStart,
  PreToolUse, PostToolUse, Stop). File-writing agents (implementer, test-writer,
  refactorer, documenter) now scan for secrets post-tool.
- **hooks/README.md** — document per-agent hooks as primary method, clarify JSON
  hooks are legacy fallbacks for future VS Code feature stabilization.

### Notes

- `agent-hooks.json` remains in place and is auto-generated if needed; it will
  not break if VS Code enables JSON loading in the future.
- All 4 orphaned hook scripts are now active via agent frontmatter.

## [1.18.4] -- 2026-04-01

### Removed

- **hook-utils.ps1** -- deleted. Custom trace logging replaced by VS Code's
  native `GitHub Copilot Chat Hooks.log` (zero runtime overhead).
- **Write-HookTrace calls in all 13 hooks** -- removed dot-source and all
  trace invocations. Scripts are now self-contained again.
- **Section 8 (trace telemetry) in test-hooks.ps1** -- 6 trace test cases
  removed. Total: 53 tests (down from 59).

### Added

- **test-hooks-integration.ps1** -- parses VS Code's native hook log to
  verify hooks actually fire. Supports `-All` (all sessions) and `-Verbose`
  (per-invocation detail). Detects orphaned scripts and confirms global
  hook non-firing.
- **Pytest terminal guard in coordinator-pretooluse.ps1** -- denies
  `run_in_terminal` when command matches `\bpytest\b|\bpy\.test\b`.
  Returns hint to use `execute/runTests` tool or predefined tasks.

### Fixed

- **refactorer-stop.ps1** -- fixed corrupted line containing literal `\n`
  embedded in source.

## [1.18.3] -- 2026-04-01

### Added

- **hook-utils.ps1** -- shared trace logging utility for all hooks. Writes
  JSONL entries to `.github/logs/hook-trace.jsonl` with timestamp, hook name,
  event type, tool name, and detail. Proves hooks fire during real agent runs.
- **Trace calls in all 13 hooks** -- dot-source `hook-utils.ps1` and log at
  decision points (deny/ask/block/warn) plus `invoked` events for stop hooks
  and session-context.
- **Trace verification in test-hooks.ps1** -- 6 new test cases confirm trace
  entries are written and valid JSON. Total: 54 tests.

### Fixed

- **test-writer-pretooluse.ps1** -- tool-name pattern `edit|create|write|file`
  falsely matched `readFile`, blocking the test-writer from reading production
  code. Tightened to `editFile|createFile|createDir|editNotebook`.
- **coordinator-pretooluse.ps1, scan-secrets.ps1** -- same pattern tightened
  for consistency (not exploitable due to earlier guards, but fragile).

## [1.18.2] -- 2026-04-01

### Added

- **test-hooks.ps1** -- integration test suite for all 13 Copilot agent hooks.
  Exercises PreToolUse (block-dangerous, coordinator, test-writer, refactorer,
  researcher), PostToolUse (scan-secrets), and edge cases (empty/malformed JSON).
  48 test cases. Task: `test: hooks`.

## [1.18.1] -- 2026-03-31

### Added

- **Tool audit system** — `audit-tools.ps1` script validates agent tool
  assignments against `tools-reference.txt` baseline and `TOOLS.md` matrix.
  Reports unknown, undocumented, and orphaned tools. Tasks: `audit: tools`,
  `audit: tools verbose`.
- **Extension tools assigned to agents** — `ms-toolsai.jupyter/configureNotebook`
  (implementer, refactorer, code-critic, test-writer),
  `ms-python.python/configurePythonEnvironment` (same 4),
  `vscode/askQuestions` (coordinator, planner),
  `vscode.mermaid-chat-features/renderMermaidDiagram` (planner, documenter),
  `ms-toolsai.jupyter/listNotebookPackages` (code-critic).
- **tools-reference.txt** expanded from 30 built-in to 43 registered tools
  (built-in + extension).

### Changed

- **TOOLS.md** — added extension tools and VS Code UI sections to matrix;
  updated exclusion tables with correct frontmatter keys.
- **audit-tools.ps1** — renamed "built-in" to "registered" to reflect
  built-in + extension coverage; fixed Unicode characters for PS 5.1.

### Fixed

- **deploy.ps1** — added version-stale detection: warns when deploying
  updated files without a VERSION bump (prevents silent version drift).

## [1.18.0] -- 2026-03-27

### Added

- **12 new skills from ai-dev-kit** — databricks-agent-bricks, databricks-apps,
  databricks-bundles, databricks-connect, databricks-dbsql, databricks-jobs,
  databricks-mlflow-eval, databricks-model-serving, databricks-sdp,
  databricks-synthetic-data, databricks-unity-catalog, python-dev.
  Available skills library expanded from 22 to 34.
- **validate-skills.py** — Automated skill validation script. Checks YAML
  frontmatter (name, description, argument-hint), directory-name consistency,
  and INDEX.md cross-references. Supports `--deep-available`, `--root`, `--ci`.
  Integrated into validate-framework.prompt.md step 7.

### Changed

- **data-pipeline-design skill enhanced** — Added medallion architecture,
  Delta Lake patterns, and Spark Streaming guidance.
- **secrets-management skill enhanced** — Added Databricks secret scopes
  and dbutils.secrets patterns.

### Fixed

- **deploy.ps1 skill INDEX.md protection** — Marked `skills/INDEX.md` as
  `[customizable]` in `.af-manifest`. Previously, deploy would overwrite
  project-specific skill activations with the AAIG template index.
- **deploy.ps1 stale activation warning** — Post-deploy check now warns
  when activated skills have a newer version in `_available/`.
- **validate-framework.prompt.md** — Step 7 now references the automated
  validation script as the preferred check method.

## [1.17.0] -- 2026-03-24

### Changed

- **README restructured for team distribution** — Two-tier layout: quick-start
  for newcomers (Why Use This → Prerequisites → Quick Setup → Your First Week)
  and collapsible deep-dive sections (File Map, Model Prioritization, Tool
  Configuration). Value proposition section added. Prerequisites moved before
  Quick Setup. "Adopting Incrementally" promoted to "Your First Week" with
  table format. Links bar with version badge, Changelog, and Troubleshooting.
- **Scope-aware test execution** — Agents now follow per-agent test budgets
  (implementer: 0× all-scope, test-writer: Red-phase only, refactorer: 1× all).
  Persistent `.github/test-log.json` tracks cumulative test results across
  sessions. Stop hooks invoke the canonical test runner script instead of raw
  pytest. Git-based change detection replaced hardcoded time limits for
  freshness checks.
- **Pure bash hook scripts** — Removed python3 dependency from all `.sh` hook
  scripts (`run-tests.sh`, `session-context.sh`, `implementer-stop.sh`,
  `refactorer-stop.sh`). Reimplemented JSON merging and date formatting with
  sed, tr, date, and printf.

### Fixed

- **Stop hooks now use canonical test runner** — `implementer-stop` and
  `refactorer-stop` hooks invoke `run-tests.ps1/.sh` instead of raw pytest,
  ensuring test-log.json is always populated (P0).
- **Implementer test budget contradiction** — Resolved conflict between
  "1× all" budget and "Do NOT run all" instruction; standardised on 0× all
  (P1).
- **git diff missing HEAD** — Added `HEAD` to all `git diff` commands in hook
  scripts to correctly detect staged and committed changes (P2).
- **Stale pytest commands in testing instructions** — Replaced raw pytest
  invocations with canonical runner references (P3).
- **Error summary chrome stripping** — Stop hooks now strip pytest `===` banner
  lines from error summaries injected into agent context (R1).
- **Known-schema comment** — Expanded documentation of sed JSON parsing safety
  assumptions in `run-tests.sh` (R3).

---

## [1.16.0] -- 2026-03-16

### Added

- **Idea 46 -- Task-Based Test Execution System** -- Back-ported from live
  project work. Agents now use pre-defined VS Code Tasks (`execute/runTask`)
  instead of calling pytest directly.

  - **Canonical test runner** -- `run-tests.ps1/.sh` wraps pytest with scope
    selection, coverage, fail-fast, output file, and PySpark stderr suppression.
  - **VS Code tasks** -- 12 test tasks, 5 git tasks, 3 lint tasks defined in
    `.vscode/tasks.json`. Agents invoke via `execute/runTask`.
  - **VS Code settings** -- `.vscode/settings.json` enables hook system
    (`chat.useCustomAgentHooks: true`) and pytest integration.
  - **Tool sets** -- `.vscode/tool-sets.jsonc` defines reusable tool groups
    (`reader`, `dev`, `python-analysis`, `python-environment`, `notebooks`).
  - **Agent tool grants** -- `execute/runTask` added to coordinator,
    implementer, refactorer, code-critic, test-critic, test-writer, documenter,
    planner. Implementer also gets `execute/createAndRunTask`.
  - **Testing instruction** -- New "Agent Test Execution" section with task
    table, phase-specific strategy, and 7 rules.

  **Files created (5):** `.vscode/settings.json`, `tasks.json`,
  `tool-sets.jsonc`, `scripts/run-tests.ps1`, `.sh`
  **Files modified (10):** 8 agent `.agent.md` files, `testing.instructions.md`,
  `.af-manifest`

- **Idea 41 -- Coordinator Delegation Enforcement Hooks** -- Three-layer
  safeguard preventing the coordinator from directly modifying files.

  **Background:** During live project work, the coordinator bypassed all
  workflows and directly edited 4 files. Investigation revealed the "never
  modify files" Cardinal Rule was enforced only by prose instruction -- no
  programmatic guard existed.

  - **Layer 1: PreToolUse hook (HARD deny)** -- `coordinator-pretooluse.ps1/.sh`
    blocks `editFiles`, `createFile`, `createDirectory` tool calls. Allows
    `runInTerminal` and all read/search tools. Deny message redirects to the
    correct subagent and workflow.
  - **Layer 2: PostToolUse hook (detective advisory)** --
    `coordinator-posttooluse.ps1/.sh` fires after terminal commands. Runs
    `git status --porcelain -- mpusage/ tests/` to detect indirect file writes
    via terminal escape hatch (`Set-Content`, `echo >`, `sed -i`). Injects
    warning via `additionalContext`.
  - **Layer 3: Prose (existing)** -- Cardinal Rule #1 reinforced by Layer 1
    deny messages.

  Scripts follow the established agent-scoped hook pattern from Idea 39
  (test-writer PreToolUse, refactorer PreToolUse). Coordinator is the 5th
  agent with scoped hooks.

  **Files created (4):** `coordinator-pretooluse.ps1`, `.sh`,
  `coordinator-posttooluse.ps1`, `.sh`
  **Files modified (1):** `coordinator.agent.md` (hooks frontmatter)

- **Idea 43 -- Remaining Hook Iteration 3 (37a + 39-H3)** -- Completed the
  two remaining low-priority hook tasks.

  - **37a: Provenance marker check in scan-secrets** -- Extended
    `scan-secrets.ps1/.sh` with a SOFT advisory that checks `.py` files for
    `copilot:generated|modified` markers in the first 5 lines. Emits JSON
    warning; does not block.
  - **39-H3: Researcher PreToolUse credential-URL scan** -- Created
    `researcher-pretooluse.ps1/.sh`. Scans `web/fetch` URLs for basic auth,
    token query params, credential fragments. WARN advisory only — allows
    fetch, shows sanitized URL. Researcher is now the 6th agent with scoped
    hooks.

  **Files created (2):** `researcher-pretooluse.ps1`, `.sh`
  **Files modified (4):** `scan-secrets.ps1`, `.sh`, `researcher.agent.md`,
  `.af-manifest`

### Changed

- **Open task re-evaluation** -- Reviewed all remaining open items from
  Ideas 14, 37, 39.
  - Dropped **37b** (branch advisory in SessionStart) -- superseded by 3
    existing layers of branch awareness.
  - Corrected **39-H8** (planner Stop hook) -- the Stop hook itself
    remains infeasible (conversational output, not hookable), but the
    original drop reasoning was wrong. Investigation revealed a latent
    plan persistence gap, resolved by Idea 42.
  - Retained **39-P4** (PreCompact checkpoint) at MEDIUM priority.
  - Retained **37a** (provenance in scan-secrets) and **39-H3** (researcher
    URL scan) at LOW priority.

### Fixed

- **Idea 42 -- Plan File Persistence Gap** -- Coordinator Step 1 instructed
  "persist as {type}-{date}-{slug}.md" but neither the coordinator (no
  `edit/*` tools, PreToolUse hook denies) nor the planner (read-only) could
  actually write the file. Latent contradiction since Idea 35, masked until
  Idea 41 added programmatic enforcement.
  - Coordinator Step 1 now delegates plan file creation to the **documenter**.
  - Quick Fix investigation doc creation also delegated to documenter.
  - Documenter gained Responsibility #1 "Persist plan files when delegated";
    existing responsibilities renumbered #2--#6.
  - **Files modified (2):** `coordinator.agent.md`, `documenter.agent.md`

- **Idea 44 -- Coordinator PreToolUse False-Positive Fix** -- The `file`
  pattern in the coordinator hook matched read-only tools (`read_file`,
  `readFile`, `fileSearch`) causing false-positive denials. Added a
  read-only tool allowlist (`read|search|find|list|get|problems`) that
  exits early before the `file` catch-all. 14/14 tool scenarios pass.
  - **Files modified (2):** `coordinator-pretooluse.ps1`, `.sh`

- **Idea 45 -- Hook-Agent Alignment Audit** -- Cross-referenced all 11 agent
  tool definitions against hook enforcement, workflow semantics, and quality
  gates.
  - Removed `edit/createFile` + `edit/createDirectory` from refactorer tools
    (hook already blocks them — model was wasting turns).
  - Standardized researcher hook YAML format to match all other agents.
  - Added provenance marker check to `implementer-stop` as a HARD gate
    (quality-gates.instructions.md said HARD but only SOFT WARN existed).
  - HARD gate hook coverage improved from 56% (9/16) to 69% (11/16).
  - **Files modified (4):** `refactorer.agent.md`, `researcher.agent.md`,
    `implementer-stop.ps1`, `.sh`

---

## [1.15.0] -- 2026-03-11

### Changed

- **Idea 40 -- Deploy Mechanism Improvements** — Comprehensive overhaul of both
  deploy scripts (`deploy.ps1` and `deploy.sh`) based on peer review (planner +
  code-critic). All improvements applied to both scripts for full parity.

  - **D2: Fix -Diff exit code bug** — `-Diff` mode now wrapped in try/catch
    (PowerShell) to prevent `$ErrorActionPreference = 'Stop'` from converting
    non-terminating errors into exit code 1. Explicit `exit 0` added at end of
    both Diff and Deploy modes.

  - **D3+D9: Manifest annotation system** — `.af-manifest` now supports
    annotations at end of line: `path  [annotation1, annotation2]`. Three
    annotations defined:
    - `[customizable]` — file contains project-specific content; protected on update
    - `[optional]` — directory or file may not exist in AF source; no warning
    - `[vscode]` — file deployed to `.vscode/` instead of `.github/`
    Eliminates hardcoded `$CustomizableFiles` array and hardcoded `.vscode/toolsets.jsonc`
    special case. Both are now driven entirely by manifest annotations.

  - **D4: Content diff on CONFLICT** — When a CONFLICT is detected (both AF and
    project changed), `Show-ContentDiff` / `show_content_diff` displays up to 15
    lines of diff output. Uses `git diff --no-index` when available, falls back to
    `Compare-Object` (PowerShell) or `diff -u` (bash).

  - **D5: Manifest validation** — After parsing, deploy scripts warn about manifest
    entries pointing to missing directories or files. `[optional]` entries are
    silently skipped. Catches manifest drift early.

  - **D6: Ephemeral backup** — Before overwriting files (UPDATE or Force), copies
    the existing file to `.af-backup-{timestamp}/`. If deploy completes with 0
    conflicts, the backup directory is automatically deleted. If conflicts remain,
    the backup persists with its path printed in the summary.

  - **D8: Bash parity** — `deploy.sh` completely rewritten to match `deploy.ps1`
    capabilities: full 3-way merge via `.af-hashes`, `--update-hashes` mode,
    PRESERVE/CONFLICT states, manifest annotation parsing, content diff on
    conflict, manifest validation, and ephemeral backup. Previously, `deploy.sh`
    had no 3-way merge and silently overwrote project customizations (data loss
    risk for UC2 on Linux/macOS).

  - **Customizable file handling improved** — Customizable files now participate
    in 3-way merge to provide better status messages:
    - AF changed, project unchanged → `PROTECT (AF has changes -- review manually)`
    - AF unchanged, project changed → `PRESERVE (project customization)`
    - Both changed → `CONFLICT` with content diff
    Previously all cases showed generic `PROTECT` message.

## [1.14.0] -- 2026-03-11

- **Idea 39 Iteration 2 -- Agent-Scoped Phase Gate Expansion** -- Adds
  machine-verified phase gates to test-writer, refactorer, and documenter.
  - **`test-writer:SubagentStop`** (P1a + H5) — Red phase gate: blocks if all
    tests pass (tests must FAIL to prove a requirement gap). Also checks
    provenance markers on newly created test files.
  - **`test-writer:PreToolUse`** (H2) — TDD phase isolation: blocks the
    test-writer from editing production code under `mpusage/`. Prevents the
    most fundamental TDD invariant violation.
  - **`refactorer:SubagentStop`** (H1) — Refactor phase gate: blocks if tests
    fail OR if new `.py` files were created under `mpusage/`/`tests/`. Scoped
    `git status` to avoid false positives on pre-existing untracked files.
  - **`refactorer:PreToolUse`** (H4) — Preventative layer: blocks
    `createFile`/`createDirectory` calls. Defence-in-depth with Stop hook.
  - **`documenter:SubagentStop`** (P1c) — Artifact gate: blocks documenter if
    workflow log YAML or retro snippet is missing for the current workflow-id.
  - Peer-reviewed: planner (6 new proposals) + code-critic (4 approved,
    1 approved with conditions, 1 rejected). H6 rejected (SubagentStart
    routing unverified, redundant with coordinator prompting).
  - Global Stop hook Gate 2 (workflow artifacts advisory) now complemented
    by documenter:SubagentStop hard gate — Gate 2 retained as session-end
    safety net.
  - **VS Code `Stop` event bug:** `Stop` hooks in `.agent.md` frontmatter
    crash subagent invocation. 7 of 8 events work; only `Stop` is broken.
    **Workaround:** use `SubagentStop` instead of `Stop` — functionally
    equivalent for subagent-only agents. All agents verified working.

## [1.13.0] -- 2026-03-11

### Added

- **Idea 39 -- Agent-Scoped Hooks (Iteration 1: Green Gate)** -- VS Code now
  supports hooks in `.agent.md` frontmatter that fire only when that agent is
  active. An agent's `Stop` hook should fire as `SubagentStop` when invoked as
  a subagent, but a VS Code bug crashes `Stop`; use `SubagentStop` instead.
  - **New `implementer:SubagentStop` hook scripts** (`implementer-stop.ps1/.sh`)
    — runs the test suite when the implementer subagent completes. Blocks the
    implementer from returning if tests fail (Green phase gate).
  - **Global Stop hook Gate 1 retired** — pytest enforcement removed from
    `stop-tests.ps1/.sh` (handled by per-agent SubagentStop hook at phase exit).
    Global Stop hook retains Gate 2 (workflow artifact advisory).
  - **`implementer.agent.md`** updated with `hooks.SubagentStop` in YAML
    frontmatter.
  - Requires `chat.useCustomAgentHooks: true` in `.vscode/settings.json`.
  - Peer-reviewed: planner (8 proposals) + code-critic (3 rejected, 3 approved
    with conditions, 1 deferred). P1b unanimously approved as highest ROI.

### Future iterations (from peer discussion)

- **P1a** `test-writer:Stop` — Red gate (tests must FAIL).
- **P1c** `documenter:Stop` — artifact existence gate.
- **P4** `coordinator:PreCompact` — workflow checkpoint before context compaction.

---

## [1.12.0] -- 2026-03-10

### Added

- **Idea 37 -- Bookend Compliance Pattern** -- New `compliance-checker` agent
  (11th agent) acts as a mandatory workflow watchdog. Invoked at two bookend
  checkpoints: pre-flight (before Step 1) and post-flight (after Step 7).
  - **Pre-flight checks:** branch not on main/master, plan directory resolved,
    WIP state consistent.
  - **Post-flight checks:** plan file marked COMPLETED, workflow log YAML
    exists, retro snippet exists, provenance markers present. Reports missing
    artifacts to the coordinator — the coordinator handles remediation by
    invoking the documenter (only it has the full workflow context).
  - **Read-only design:** compliance-checker detects gaps but never creates
    files. The documenter needs rich context (step summaries, critic findings,
    metrics) that only exists in the coordinator's conversation history.
  - **Stop hook enhanced** (Layer 3 safety net): `stop-tests.ps1` and
    `stop-tests.sh` now also check for workflow artifacts (log YAML, retro
    snippet, plan status) at session end. Emits advisory WARNING if missing
    — does not block.
  - **3-layer enforcement model:** (1) Coordinator instructions → (2)
    Compliance-checker bookends → (3) Stop hook detection. Each layer
    catches failures the previous layer missed.
  - Updated coordinator workflow diagrams, state machine, phase checkpoints,
    and narration examples.
  - Added compliance-checker exit gates to quality-gates.instructions.md.
  - Updated MANIFEST.md, README.md, skills/INDEX.md.

---

## [1.11.0] -- 2026-03-10

### Changed

- **Idea 38 -- Autonomous Local Git Execution** -- Coordinator now executes
  local git operations (branch creation, staging, committing) at reviewed
  checkpoints. Remote and destructive operations remain human-controlled.
  Unanimously approved by planner + code-critic peer discussion.
  - **Cardinal Rule replaced** with local/remote principle in
    `git-workflow.instructions.md`. Local git is coordinator-executed;
    remote git is human-controlled.
  - **Coordinator agent** gains permitted-command list, branch guard
    (never commit on main/master), explicit staging rules, and
    post-command verification protocol.
  - **Block-dangerous hook** expanded: `git push` (any form), `git merge`,
    `git branch -d/-D`, `git rebase` now trigger confirmation prompt.
    Previously only `--force` push and `--hard` reset were blocked.
  - **Documenter** no longer suggests git commits (responsibility fully
    moved to coordinator).
  - **MANIFEST.md** §7 Git Conventions updated to reflect two-tier model.

---

## [1.10.0] -- 2026-03-10

### Added

- **Idea 36 -- Researcher Agent** -- New 10th agent (`researcher.agent.md`)
  for external research and domain expertise. Unanimously approved by planner
  + code-critic peer discussion.
  - **Role:** Fetch and synthesize external documentation — third-party APIs,
    versioned library docs, external standards not in the codebase or skills.
  - **Tool profile:** Read-only + `fetch`. No write access. Most constrained
    agent in the framework.
  - **User-invocable:** Yes — standalone domain questions and coordinator
    pre-flight research.
  - **Coordinator integration:** Conditional pre-flight step before planner.
    Invoked only when task involves external APIs/libraries/standards not
    covered by existing skills. Anti-invocation rules prevent over-use.
  - **Security:** Structured artifact output only (no raw content forwarding),
    no autonomous URL following, source scope constraints. Human review gate
    for Standard+ tiers.
  - **Quality gates:** 3 HARD (citations, no secrets, structured output),
    1 SOFT (source authority), 1 ADVISORY (retrieval timestamps).
  - **Skills assigned:** data-pipeline-design, data-modeling, data-quality.

### Changed

- **coordinator.agent.md** -- Added researcher to agents list, Worker Agents
  table, workflow diagram. Added "Research Pre-Flight" section with invocation
  criteria and anti-invocation rules.
- **MANIFEST.md** -- Added researcher to Worker Agent Roles and Handoff Data
  Requirements tables.
- **skills/INDEX.md** -- Added researcher to Agent Skill Matrix.
- **quality-gates.instructions.md** -- Added Researcher per-agent exit gates.
- **README.md** -- Agent count 9→10, added researcher to file map.

## [1.9.0] -- 2026-03-10

### Changed

- **Idea 35 -- Plan and WIP Artefact Redesign** -- Plans and WIP files now
  follow clear naming, location, and lifecycle conventions.
  - **Plan naming:** unique per-workflow filenames using
    `{type}-{YYYY-MM-DD}-{slug}.md` (e.g., `feat-2026-03-10-bucketing-v2.md`).
    Type prefix: `feat`, `fix`, `refactor`, `adr`, `review`.
    Slug derived from branch name.
  - **Plan location:** `docs/plans/` (default). Coordinator discovers existing
    conventions at Step 0 (e.g., `docs/designs/`, `docs/rfcs/`).
  - **WIP naming:** keeps literal `WIP.md` (ephemeral, easy to find).
  - **WIP location:** `docs/plans/WIP.md` (co-located with plans, not project root).
  - **Coordinator determines filename** (knows date + branch name).
  - **Archival eliminated:** plans live in their final location from creation.
    Removed unimplemented "archives to `.github/logs/`" step.
  - **WIP template:** added `Plan File` reference field so `/resume` can
    locate the associated plan.
  - **Convention discovery:** coordinator Step 0 checks for existing `docs/`
    structure before defaulting.

### Files Modified (12)

- `agents/coordinator.agent.md` -- Step 0 convention discovery, Step 1 plan
  naming logic, Session Interruption WIP path
- `agents/planner.agent.md` -- return format mentions unique filenames
- `agents/documenter.agent.md` -- references plan file path instead of PLAN.md
- `instructions/git-workflow.instructions.md` -- naming convention, location,
  WIP section, archival removed
- `instructions/quality-gates.instructions.md` -- plan file references
- `MANIFEST.md` -- Planning Documents section, artifact lifecycle table,
  handoff data table
- `prompts/resume.prompt.md` -- WIP discovery in docs/plans/
- `prompts/draft-pr-description.prompt.md` -- plan file in docs/plans/
- `prompts/simulate.prompt.md` -- plan file reference
- `TROUBLESHOOTING.md` -- WIP.md location guidance
- `templates/PLAN.md` -- naming convention comments
- `templates/WIP.md` -- Plan File field, location comments

## [1.8.0] -- 2026-03-10

### Added

- **Idea 34 — AF Deployment Scripts** — Created `deploy.ps1` (Windows) and
  `deploy.sh` (macOS/Linux) for safe, repeatable AF deployment into projects.
  - Install mode: copies AF-owned files to project `.github/` + `.vscode/`
  - Dry-run mode (`-DryRun`/`--dry-run`): preview changes without writing
  - Diff mode (`-Diff`/`--diff`): bidirectional comparison for both UC1
    (update check) and UC2 (feedback collection)
  - Force mode (`-Force`/`--force`): overwrite customized files
  - Customizable file protection: `copilot-instructions.md` and
    `architecture.instructions.md` are never overwritten on update
  - Version tracking via `.github/.af-version`

### Changed

- **README.md** — Quick Setup now references deploy scripts instead of manual
  copy. Manual instructions preserved as collapsible fallback. Added
  "Updating the AF" subsection. Deploy scripts added to file map.
- **`.af-manifest`** — Added `.af-manifest` and `.af-version` as deployment
  metadata entries.

---

## [1.7.3] — 2026-03-10

### Changed

- **U-08 — Workflow-lifecycle merged into coordinator** — Deleted standalone
  `instructions/workflow-lifecycle.instructions.md` (~120 lines, `applyTo: **`).
  All unique content merged into `coordinator.agent.md`:
  - Workflow States table + state transition diagram added to Execution Protocol
  - Session Interruption enhanced with detailed 6-step checkpoint protocol
    (commit in-progress changes, use template, include step history)
  - Task Cancellation enhanced with PR preservation and branch cleanup steps
  - Escalation handling and resume logic were already present — no duplication
  Savings: ~120 lines no longer loaded for every non-coordinator agent.

### Removed

- `instructions/workflow-lifecycle.instructions.md` — content lives in
  coordinator.agent.md (the only consumer).

---

## [1.7.2] — 2026-03-10

### Changed

- **U-01 — Arbiter tool contradiction resolved** — Removed `test-runner` from
  arbiter’s tool list; updated description to say "does NOT modify files or
  run tests." Coordinator Worker Agents table updated to "Read-only advisory."
  Body already said "No execution — do NOT run tests"; now frontmatter agrees.
- **U-02 — Planner read-only wording clarified** — Body constraint changed
  from "read-only tools only" to "read-only for files" with explicit note that
  terminal commands and test-failure inspection are allowed for analysis.
- **U-03 — Skill table completed** — copilot-instructions.md skill table
  expanded from 9 skills to all 16 active skills with correct consumer
  mappings. Added cross-reference to `skills/INDEX.md` as canonical source.
- **U-04 — Gate Summary aligned** — MANIFEST § 13 Gate Summary template now
  includes the `Skills Read:` line, matching quality-gates.instructions.md.
- **U-05 — Pre-Delivery Checklist deduplication** — MANIFEST § 11 body
  replaced with a single-source-of-truth pointer to copilot-instructions.md
  § Pre-Delivery Checklist, eliminating the duplicate that had already drifted.

---

## [1.7.1] — 2026-03-10

### Changed

- **G-07 — Secret scan hardened** — PostToolUse secret-scan hook now exits
  with code 1 (blocking) when secrets are detected. Previously advisory-only
  (exit 0), which contradicted MANIFEST § 5 Gate 4 (HARD security gate).
  Both `.ps1` and `.sh` scripts updated.
- **G-06 — CVE scanning operationalized** — Code-critic Step 6 now instructs
  running `pip-audit` in terminal when new dependencies are added. R-SD-12
  mapping in MANIFEST § 12 updated to reference `pip-audit`.
- **G-10 — Layer override exemption** — Pure documentation changes (docstrings,
  comments) in domain core files no longer trigger the Standard tier override.
  Only logic changes count.

### Added

- **G-02 — Early-exit logging** — Coordinator writes a minimal YAML log
  when a workflow fails before Step 7, ensuring steps 1–6 are not lost.
- **G-03 — R-SD-23 cross-reference** — `provenance.instructions.md` now
  references governance L1 Principle 3 and domain rule R-SD-23.
- **G-04 — Mutation testing labeled** — MANIFEST § 2 Tier 3 (mutation tests)
  explicitly labeled as aspirational with a note about future tooling.
- **G-09 — Governance action items** — Documenter retro snippets gain a
  `## Governance Action` section for proposing workflow/governance
  improvements with affected L2 rule or AF element.
- **G-11 — R-SD-03 mapped** — Added R-SD-03 (code review scope) to
  MANIFEST § 12 cross-reference table, mapped to code-critic Steps 1–7.
- **G-12 — Lockfile check** — Code-critic Step 6 now checks for lockfile
  presence when new dependencies are added (R-SD-10).

### Fixed

- **G-01 — toolsets.jsonc** — Confirmed to exist at `.vscode/toolsets.jsonc`
  (was missed in audit due to gitignored path). No action needed.
- **G-05 — Context budget RED** — Already mandates halt ("HARD gate — Do NOT
  continue"); confirmed correct after Idea 31 recalibration.
- **G-08 — Credential scoping** — Already acknowledged as open gap in
  MANIFEST § 7. No action until CI/CD integration.

---

## [1.7.0] — 2026-03-09

### Added

- **Idea 29 — Skill Pruning** — 22 unassigned skills moved to
  `skills/_available/`. INDEX.md split into "Active Skills (16)" and
  "Available for Activation (22)". `/validate-framework` deep-scans only
  active skills (light scan for `_available/`). `/onboard-project` evaluates
  available skills against project tech stack and recommends activation.
- **Idea 30 — Non-Destructive Install** — `.af-manifest` created listing
  AF-owned paths. README Quick Setup documents file ownership boundary (AF
  does NOT overwrite workflows, CODEOWNERS, dependabot.yml). `/onboard-project`
  gains conflict detection (Steps 7-8): enumerates existing `.github/` files,
  offers to merge `copilot-instructions.md`, respects ownership boundary.
- **Idea 31 — Token Budget Feasibility** — Context budget heuristics
  recalibrated: ≥7 calls → YELLOW, ≥10 → RED (was ≥5/≥7, which triggered
  RED on every normal Full TDD workflow). `/simulate` gains Context
  Feasibility section (SINGLE-SESSION / MULTI-SESSION / AT-RISK). Advisory
  (SOFT) — does not block execution.
- **Idea 33 — Gate Audit Trail** — Coordinator cross-references gate claims
  against actual tool invocations. Unverifiable HARD gate claims downgraded
  to BLOCKED. Standard tier: SOFT enforcement. Deep tier: HARD enforcement.
  Narrated via progress protocol.

---

## [1.6.0] — 2026-03-09

### Added

- **Idea 24 — Supervised Execution Mode** — New `--supervised` flag for
  coordinator. Pauses after each step, presents output summary + verdict +
  gate summary, and waits for human "continue" or feedback. Trust ramp:
  simulate → supervised → autonomous.
- **Idea 27 — Partial Failure State Machine** — Workflow states enum
  (PLANNING through COMPLETED, FAILED_{step}, SKIPPED_{step}) documented
  in `workflow-lifecycle.instructions.md`. WIP.md template gains Step
  History table with per-step state, retry count, and outcome. Final
  Report gains Workflow Health section (skipped steps, retries, degraded
  gates).
- **Idea 28 — Skill Compliance Gate** — `Skills Read:` line added as SOFT
  gate for producer agents (test-writer, implementer, refactorer) in
  `quality-gates.instructions.md`. Critic flags missing/empty declarations.
  Gate Summary format updated with `Skills Read` field.

---

## [1.5.0] — 2026-03-09

### Added

- **Idea 22 — Smoke Test Playbook** — New `/smoke-test` slash command runs a
  canned `clamp(value, lo, hi)` task through the full TDD pipeline. Per-step
  health report (PASS/FAIL/SKIPPED) with raw output on failures. Disposable
  `agent/smoke-test` branch. References TROUBLESHOOTING.md on failure.
- **Idea 32 — Human Troubleshooting Guide** — New `TROUBLESHOOTING.md` with
  symptom → cause → fix tables covering: setup issues, workflow selection,
  subagent failures, gate failures, escalation, resume, and hook issues.
  Written for the human project owner, no agent jargon.

---

## [1.4.0] — 2026-03-09

### Added

- **Idea 25 — Verdict Parsing Hardening** — Coordinator now parses verdicts
  defensively: case-insensitive search, accepts any formatting, unparseable
  verdicts treated as BLOCKED (never silently APPROVED). MANIFEST § 13
  updated to document defensive parsing.
- **Idea 26 — Rejection Feedback Contract** — MANIFEST § 13 gains a
  Rejection Feedback Contract (findings, blocking_count, retry_guidance).
  Coordinator validates rejection fields before re-invoking makers. Both
  critic agents (code-critic, test-critic) updated with severity-tagged
  findings and rejection detail section in return format.
- **Idea 23 — Progress Narration Protocol** — Coordinator emits structured
  one-line status updates after each subagent returns. Emoji-coded step
  progress with verdict, retry count, and context budget indicators.

---

## [1.3.1] — 2026-03-09

### Added

- **Ideas 22–33** — 12 new improvement ideas from team brainstorm (planner,
  code-critic, test-critic). Organised into 4 implementation phases:
  Phase 1 (pre-flight): verdict hardening, rejection feedback, narration.
  Phase 2 (first run): smoke test, troubleshooting guide.
  Phase 3 (trust): supervised mode, state machine, skill compliance.
  Phase 4 (maturity): skill pruning, install safety, token feasibility, audit trail.

---

## [1.3.0] — 2026-03-09

### Summary

Autonomy review (Idea 20). Peer-reviewed by planner + code-critic. Addressed
the key gap: subagents ran under-informed because the coordinator didn't inject
skills, thresholds, or retro context into prompts.

### Added

- **Subagent Context Injection** — coordinator prepends a structured context
  block to every subagent prompt: complexity tier, target layers, quality
  thresholds, retro lessons, and skill-read reminders (A1 + A2)
- **Prompt taxonomy** — README now classifies 12 prompts into 3 tiers:
  workflow entry points (coordinator-routed), post-workflow reporting, and
  standalone utilities (A3)

### Changed

- **`coordinator.agent.md`** — all 7 subagent prompt templates now include
  `{context_block}` with tier, thresholds, layers, retro lessons, and
  explicit skill-read instructions; retro consultation now unconditional
  across all workflows (was Full TDD only); updated description to reflect
  primary entry point role
- **`prompts/resume.prompt.md`** — added `agent: coordinator` to route
  through coordinator Step 0 instead of standalone discovery (A5)
- **`prompts/validate-framework.prompt.md`** — Step 2 now flags uncustomized
  `applyTo` defaults like `src/**/*.py` as WARN (A6)
- **`README.md`** — slash commands section reorganised into 3-tier taxonomy

### Design Decisions

- **GOVERNANCE.md NOT auto-injected** — 300+ lines would waste context budget.
  Relevant rules are embedded in agent prompts and critic checklists. Drift
  risk mitigated by `/validate-framework`.
- **Standalone utility prompts kept standalone** — `/audit-config`,
  `/validate-framework`, `/find-skill`, `/simulate`, `/onboard-project`,
  `/retro-summary` are legitimately user-triggered maintenance operations
  that don't need coordinator orchestration.
- **Git stays human-controlled** — L1 §7 (Least Privilege). No change.

---

## [1.2.0] — 2026-03-09

### Summary

Governance audit of all 9 L1 Core Principles. Three-agent parallel review
(planner, code-critic, test-critic) produced 12 recommendations — all
implemented. Hook coverage expanded from 2 → 4 lifecycle events.

### Added

- **PostToolUse hook** — `scan-secrets.ps1/.sh` scans edited files for
  hardcoded secrets using gitleaks or regex fallback (advisory, never blocks)
- **Stop hook** — `stop-tests.ps1/.sh` runs `pytest tests/ -q --tb=line`
  before session ends with graceful fallback
- **Worker Uncertainty Protocol** — BLOCKED status format with structured
  triggers added to test-writer, implementer, refactorer
- **Over-engineering check** — added to code-critic Step 4 checklist

### Changed

- **`agent-hooks.json`** — 4 active hooks (was 2): SessionStart, PreToolUse,
  PostToolUse, Stop
- **`coordinator.agent.md`** — Step 0 reads `retros/auto/` for Full TDD
  workflows; Step 7 trivial tier skips documenter subagent
- **`documenter.agent.md`** — YAML log schema gains `review_details` field
  for persisting critic findings (severity, description, resolution)
- **`implementer.agent.md`** — removed `web/fetch` tool; added
  `human-escalation` skill
- **`test-writer.agent.md`** — added `human-escalation` skill
- **`refactorer.agent.md`** — added `human-escalation` skill
- **`quality-gates.instructions.md`** — retro snippet generation promoted
  to HARD gate for documenter
- **`skills/INDEX.md`** — `human-escalation` references updated (arbiter →
  test-writer, implementer, refactorer, arbiter)
- **`GOVERNANCE.md`** — R-SD-26 corrected: "present structured escalation
  summary" replaces "generate ESCALATION.md"
- **`MANIFEST.md`** — hooks table reflects 4 active hooks; credential
  scoping (R-SD-21/22) documented as deferred open gap
- **`README.md`** — hooks file tree and summary table updated

### Governance Audit Results

All 9 L1 Core Principles scored **PARTIALLY ENFORCED** — strong design but
enforcement relied on prompt guidance, not deterministic checks. The 12
recommendations address the gaps:

| # | Principle | Recommendation |
|---|---|---|
| R1 | Verifiability | Activate Stop hook (test gate) |
| R2 | Safety | Activate PostToolUse hook (secret scan) |
| R3 | Transparency | Persist critic findings in YAML log |
| R4 | Fail-Safe | Worker Uncertainty Protocol |
| R5 | Fail-Safe | Human-escalation skill for all producers |
| R6 | Continuous Improvement | Retro snippet as HARD gate |
| R7 | Continuous Improvement | Coordinator retro consultation |
| R8 | Separation of Concern | Fix R-SD-26 ESCALATION.md reference |
| R9 | Efficiency | Trivial tier minimal doc path |
| R10 | Least Privilege | Remove web/fetch from implementer |
| R11 | Least Privilege | Document credential scoping gap |
| R12 | Review | Over-engineering check for code-critic |

---

## [1.1.0] — 2025-07-16

### Summary

Batch 2 and 3 improvements — new prompts, workflow memory, context awareness,
skill discoverability, and versioning infrastructure.

### Added

- **`/draft-pr-description`** prompt — generate PR text from PLAN.md + YAML log
  + gate summary (Idea 13)
- **`/find-skill`** prompt — semantic search across the skill library (Idea 17)
- **`skills/INDEX.md`** — auto-generated index of all 38 skills with agent
  matrix and unassigned skills list (Idea 17)
- **`/retro-summary`** prompt — pull-model aggregator for workflow lessons (Idea 11)
- **`/resume`** prompt — discover paused workflows from WIP.md files (Idea 16)
- **`/audit-config`** prompt — detect drift between AF config and project state (Idea 12)
- **`/simulate`** prompt — dry-run workflow prediction without execution (Idea 19)
- **`VERSION`** file and **`CHANGELOG.md`** — semver tracking (Idea 18)
- **Context Budget Awareness** — GREEN/YELLOW/RED self-assessment protocol in
  coordinator with HARD gate on RED (Idea 15)
- **Retro snippet generation** — documenter auto-generates `retros/auto/{id}.md`
  after each workflow (Idea 11)

### Changed

- **`coordinator.agent.md`** — added Context Budget Awareness section
- **`documenter.agent.md`** — added responsibility #5 (retro snippet),
  expanded write permissions to `retros/auto/`, added return format entry

### Deferred

- **Idea 14** (Custom Workflow Definitions) — deferred until existing workflows
  have been exercised ≥3 times end-to-end

### Ideas Completed

| Idea | Summary |
|---|---|
| 11 | Workflow Memory & Auto-Retro (pull model) |
| 12 | Config Drift Detection (`/audit-config`) |
| 13 | CI/PR Integration (`/draft-pr-description`) |
| 14 | Custom Workflows — DEFERRED |
| 15 | Context Budget Awareness |
| 16 | Workflow Resume (`/resume`) |
| 17 | Skill Discovery Index (`/find-skill`) |
| 18 | Framework Versioning & Changelog |
| 19 | Dry-Run / Simulation (`/simulate`) |

---

## [1.0.0] — 2026-03-09

### Summary

Initial release after completing Ideas 1–10. The framework is self-contained,
internally consistent, and ready for adoption.

### Added

- **9 agents** — coordinator + 8 generic workers (planner, test-writer,
  test-critic, implementer, refactorer, code-critic, arbiter, documenter)
- **38 skills** — domain knowledge modules referenced by agents on demand
- **7 instructions** — auto-applied rules (architecture, copilot-authoring,
  git-workflow, provenance, quality-gates, testing, workflow-lifecycle)
- **6 prompts** — slash commands (onboard-project, validate-framework,
  tdd-feature, quick-fix, review-code, workflow-summary)
- **2 templates** — PLAN.md, WIP.md
- **Hooks** — SessionStart (git context), PreToolUse (formatter/linter)
- **GOVERNANCE.md** — L1 Core Principles, Meta-Rules, L2 Domain Rules (R-SD-01
  through R-SD-27), L3 Workflow definitions
- **MANIFEST.md** — 13 sections covering TDD, architecture, maker-checker,
  quality gates, escalation, git conventions, hooks, model prioritisation,
  tool sets, pre-delivery checklist, governing rules cross-reference,
  inter-agent contracts
- **Quality gate system** — HARD/SOFT/ADVISORY taxonomy, Trivial/Standard/Deep
  complexity tiers, per-agent exit gate tables, Gate Summary reporting format

### Foundation (Ideas 1–10)

| Idea | Summary |
|---|---|
| 1 | AF self-contained — zero AAIG references |
| 2a | Git workflow with atomic commits |
| 2b | Persisted planning documents (PLAN.md) |
| 3 | Structural peer review — all file types validated |
| 4 | Automated project onboarding (`/onboard-project`) |
| 5 | Pydantic skill for Python domain models |
| 6 | Dynamic agent creation → WONTFIX |
| 7 | Agents generic — shells + skill references |
| 8 | Documentation/logging streamlining + inter-agent contracts |
| 9 | Quality gate system — taxonomy, tiers, per-agent exit gates |
| 10 | AF self-validation (`/validate-framework`) |

> copilot:generated | implementer | 2026-03-09
