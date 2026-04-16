# Feature: Git Worktrees for Parallel Agent Task Execution

**Status:** ✅ COMPLETE — Phase 1+2+3+4 done 2026-04-14  
**Created:** 2026-04-14  
**Owner:** User Request  
**Type:** Enhancement (git-workflow)

---

## 1. Problem Statement

Current workflow forces sequential task execution on a single branch/checkout:
- Only one agent task can run locally at a time.
- Switching between branches stashes/restores working directory repeatedly.
- Human developer cannot make local changes without interference.
- Coordination overhead and cognitive load increase.

**Goal:** Enable true parallel execution of multiple agent tasks + independent human work on the main checkout.

---

## 2. Solution: Git Worktrees

### 2.1 How It Works

A **worktree** is an additional working directory tied to a single git repository.

- **Shared repository:** `.git` directory is shared (single history).
- **Isolated checkouts:** Each worktree has its own branch and file state.
- **Lifecycle:** Create from main/dev → work on agent/{task-id} → merge → destroy.

Example structure:
```
repo/                         (main checkout, on dev)
├── .git                      (shared)
├── mpfdact/
├── tests/
└── ..

wt/                           (worktrees subdirectory)
├── wt/agent-feature-x        (agent/feature-x branch)
├── wt/agent-fix-y            (agent/fix-y branch)
└── wt/...
```

Each worktree can be worked on independently; commits flow to the same repository history.

### 2.2 Lifecycle

1. **Create:** Planner/Coordinator creates worktree for new `agent/{task-id}` branch.
   - Base: `git worktree add ../wt/{task-id} -b agent/{task-id} dev`
   - Path: `../wt/{task-id}` (sibling to main checkout).
   - Bootstrap: ensure venv, deps, hooks setup.

2. **Work:** All task-specific agents (test-writer, implementer, refactorer) run in worktree.
   - Commits stay branch-scoped.
   - Coordination hooks verify context (branch + worktree mismatch).

3. **Merge (Human):** Human merges to dev in main checkout.
   - `git merge --no-ff agent/{task-id}` from main repo.
   - No rebase by agents (prevents drift).

4. **Cleanup:** Coordinator removes worktree after successful merge.
   - `git worktree remove ../wt/{task-id}`
   - Verify no uncommitted changes before removal.
   - Prune dangling references: `git worktree prune`.

---

## 3. Architecture Changes

### 3.1 Coordinate: Startup Phase

**New step BEFORE Red (test writing):**

```
Step 0d: Worktree Bootstrap
  - Coordinator: `git worktree add ../wt/{task-id} -b agent/{task-id} dev`
  - Verify: worktree created, branch exists, .github/ hooks present.
  - Setup: run venv bootstrap (if new), ensure .python-version or .venv symlink.
  - Document: record worktree-id in plan metadata.
  - Status: READY (proceed to test-writer).
```

### 3.2 Agent Context: Proof-of-Presence

All agents (in every pre-tool use hook and critical stop gates) verify:
1. **Branch check:** `git branch --show-current` contains `agent/`.
2. **Worktree check:** `git rev-parse --git-common-dir` matches expected repo structure.
3. **Mismatch:** Halt with escalation — agent is in wrong context.

### 3.3 Coordinator: Shutdown Phase

**New step AFTER human merge:**

```
Step 8: Worktree Cleanup (Coordinator)
  - Verify merge completed (human confirms).
  - Git status in worktree: must be clean.
  - Coordinator: `git worktree remove ../wt/{task-id}`
  - Verify removal success + prune dangling references.
  - Document: record cleanup + final commit hash.
  - Archive: symlink/note for post-workflow retrospective.
```

---

## 4. Gate Matrix: Soft & Hard Gates

All gates are **HARD** (mechanically enforced) unless marked SOFT.

### 4.1 Coordinator: Worktree Creation (Pre-Tool Use Hook)

| Gate | Type | Check | Enforcement |
|---|---|---|---|
| Branch name valid | HARD | `agent/{workflow-id}` matches slug | Regex: `^agent/[a-z0-9-]+$` |
| Worktree path collision | HARD | `../wt/{task-id}` does not exist | `git worktree list` grep |
| Repo health | HARD | Main repo `.git` is valid | `git status` in main checkout |
| Dev branch exists | HARD | `dev` branch exists and is clean | `git rev-parse refs/heads/dev` |

**On violation:** `deny` decision; error message includes remediation step.

### 4.2 All Agents: Context Proof (Per-Tool Use or Pre-Commit)

| Gate | Type | Check | Enforcement |
|---|---|---|---|
| Current branch is agent/* | HARD | `git branch --show-current \| grep -q '^agent/'` | Stop hook: block any commit/terminal command if false |
| Worktree is active | HARD | `git rev-parse --git-common-dir` points to shared `.git` | Pre-tool use: block file edits if worktree context invalid |
| No cross-worktree contamination | HARD | PWD matches worktree path in git metadata | Stop hook: verify ENV or file marker |

**On violation:** Escalate to human with context dump (current branch, PWD, expected worktree).

### 4.3 Coordinator: Worktree Cleanup (Post-Merge Gate)

| Gate | Type | Check | Enforcement |
|---|---|---|---|
| Merge completed | SOFT | Human confirms merge to dev | Manual checkpoint (user narrates) |
| Worktree is clean | HARD | `git status --porcelain` empty in worktree | Coordinator checks before removal |
| Stale worktrees list | SOFT | `git worktree list` shows no orphaned entries | Informational alert if found |
| Removal succeeded | HARD | `git worktree remove` exit code 0 | Retry logic: if locked, suggest `git worktree unlock` |

**On HARD violation:** WIP checkpoint; halt and escalate to human.

---

## 5. Implementation Roadmap

### Phase 1: Spec & Documentation (2-3 files)

- [x] Extend `git-workflow.instructions.md` with new sections
- [x] Update `coordinator.agent.md` (Step 0d, Step 8, context injection)
- [x] Create `skills/git-worktrees/SKILL.md`

### Phase 2: Hard Gates (4 hooks)

- [x] `coordinator-pretooluse.ps1/.sh`: Worktree creation preconditions (branch name, path collision, repo health)
- [x] `test-writer-pretooluse.ps1/.sh`: Branch context proof (agent/* required)
- [x] `refactorer-pretooluse.ps1/.sh`: Branch context proof (agent/* required)
- [x] `coordinator-postmerge.ps1/.sh` (new): Worktree audit at session end

### Phase 3: Tool Integration (2 new scripts)

- [x] `scripts/setup-worktree.ps1/.sh`: Bootstrap script (validate, create, venv, verify)
- [x] `scripts/cleanup-worktree.ps1/.sh`: Safe cleanup (clean check, remove, prune, verify)

### Phase 4: Testing & Hardening

- [x] Integration tests: setup-worktree / cleanup-worktree lifecycle (19 test cases).
- [x] Multi-worktree validation: simultaneous create + parallel cleanup.
- [x] Error recovery: path collision, invalid IDs, dirty worktrees, force-remove.
- [x] Round-trip verification: create → clean → verify removal.

---

## 6. Risk Assessment

| Risk | Severity | Mitigation |
|---|---|---|
| Stale worktrees pile up (disk/confusion) | Medium | Lifecycle gate + cleanup script + periodic audit |
| Merge conflicts from long-running branches | High | Policy: max 2-day branch lifetime; daily rebase gate (optional) |
| Agent commits in wrong worktree | High | Context proof gate in every agent stop hook |
| Worktree corruption (git internals) | Low | Git is mature; timeout on removal + manual fallback |
| Performance: many worktrees slow operations | Low | 5-10 worktrees have negligible impact on modern hardware |
| Backward compatibility | Low | Feature is opt-in; current flows still work; no breaking changes |

---

## 7. Success Criteria

- [ ] Coordinator can create/destroy worktrees without human intervention.
- [ ] Multiple agent tasks run in parallel without interference.
- [ ] Commits are properly scoped to branch + worktree.
- [ ] Hard gates prevent context contamination (wrong branch in wrong tree).
- [ ] Cleanup is automated and verifiable.
- [ ] Zero false-positive hard gate blocks (gates are tight, not paranoid).
- [ ] Documentation + troubleshooting guide covers 80% of edge cases.

---

## 8. Appendix: Example Workflow

### Timeline: 2 Parallel Tasks

**T+0: Human starts feature**
```
Human: "Implement auth module"
Coordinator → Step 0d: 
  git worktree add ../wt/feat-auth -b agent/feat-auth dev
  Bootstrap venv, setup hooks.
  → Test-writer spawned in wt/feat-auth
```

**T+1: Test-writer runs (in wt/feat-auth)**
```
Red phase: Create test_auth_service.py in wt/feat-auth
Commit: [agent:test-writer] failing tests: auth module -- login/logout/token refresh
Context gates: ✓ branch = agent/feat-auth, ✓ worktree active
```

**T+2: Human starts a second task (main checkout stays on dev)**
```
Human: "Fix database connection pool"
Coordinator → Step 0d (for second task):
  git worktree add ../wt/fix-db-pool -b agent/fix-db-pool dev
  Bootstrap venv.
  → Test-writer #2 spawned in wt/fix-db-pool
```

**T+3: Both test-writers running in parallel**
```
wt/feat-auth: implementer writing auth service code
wt/fix-db-pool: implementer writing db pool fix
Main checkout: Human debugging local issue on dev (no interference)
```

**T+4: Complete feat-auth**
```
Code-critic APPROVED
Human: `git merge --no-ff agent/feat-auth` (in main checkout)
Coordinator → Step 8: Cleanup
  Verify wt/feat-auth clean
  git worktree remove ../wt/feat-auth
  Prune dangling refs
  → wt/feat-auth gone, dev now has latest code
```

**T+5: Still working on fix-db-pool (in wt/fix-db-pool)**
```
No interference; still in own worktree
Main checkout available for dev work
```

---

## 9. Manifest & Config Changes

### `.github/.af-manifest` — add when scripts/hooks are created

The manifest controls which files `deploy.ps1` owns and syncs. New entries required when Phase 2/3 ships:

```
# Worktree scripts (Phase 3)
scripts/setup-worktree.ps1
scripts/setup-worktree.sh
scripts/cleanup-worktree.ps1
scripts/cleanup-worktree.sh

# Worktree cleanup hook (Phase 2)
hooks/scripts/coordinator-postmerge.ps1
hooks/scripts/coordinator-postmerge.sh
```

`skills/` and `hooks/scripts/` are already declared as directories in the manifest — new files inside them are automatically covered. The 4 new scripts under `scripts/` need explicit entries because the manifest lists scripts individually.

**Do NOT update the manifest before the files exist** — deploy.ps1 warns on missing listed files.

### `af-env.conf` — add WORKTREE_DIR on Phase 1

Already declared `[customizable]` in the manifest (protected from AF updates). Only the file *content* changes — no manifest entry needed:

```bash
# Git Worktree Configuration
WORKTREE_DIR=../wt
WORKTREE_BRANCH_PREFIX=agent
```

---

## 10. Dependencies / Blockers

- ✅ Git 2.7+ (worktree support) — standard on all modern systems.
- ✅ Bash 4+ / PowerShell 5.1+ (script execution).
- ⏳ Quality-gates.instructions.md may need expansion for context checks (soft dependency; can defer).

---

## 10. Open Questions / Follow-Up

1. **Rebase policy:** Should agents rebase feature branches daily? Or merge-only? (Recommended: merge-only to avoid history rewrite friction.)
2. **Stale worktree audit:** Auto-delete worktrees older than N days? Or only manual + warnings?
3. **Performance baseline:** What's the overhead of 3-5 parallel worktrees on CI agents? (Expected: negligible, <5% memory.)
4. ~~**venv sharing:** Should each worktree have its own venv or share the main venv?~~ → See Section 11 (planned).
5. **Hook duplication:** Should we extract context checks into a shared utility module (e.g., `scripts/verify-context.ps1`) to avoid hook code duplication?

---

## Notes

---

## 11. Planned Feature: Worktree venv Strategy (v1.18.25)

**Status:** 🟡 PLANNED
**Tracked:** 2026-04-15

### Problem

When a worktree is added to the VS Code workspace as a new root folder,
VS Code cannot find a `.venv` inside it (none exists yet). It repeatedly
prompts the user to select or create a Python interpreter — even though the
parent repo already has a fully configured venv. This degrades UX, especially
with multiple parallel worktrees open simultaneously.

### Design Decision: No User Prompt

The coordinator **must** configure the Python interpreter at worktree creation
time (Step 0d), before any agent or VS Code opens a file in the worktree.
The task scope is known at creation time — the workflow ID and plan determine
whether environment changes are expected — so prompting is entirely avoidable.

### Strategy: Coordinator Decides Mode

The coordinator selects the venv mode based on task scope:

| Mode | When | How |
|---|---|---|
| `shared` (default) | No dependency-file changes expected | Write `python.defaultInterpreterPath` in worktree settings pointing to parent `.venv` |
| `isolated` | Plan flags dep changes (new imports, package version updates) | Create a new `.venv` inside the worktree; clean up on Step 8 |

**Config flag:** `WORKTREE_VENV_MODE=shared|isolated` in `af-env.conf`
Default: `shared`. Coordinator may override to `isolated` per-workflow when
the plan signals dependency changes.

### Implementation: Path-Based Config (not Symlink)

**Decision: use path-based config, not a symlink.**

At Step 0d, after creating the worktree and adding it to `.code-workspace`,
write `python.defaultInterpreterPath` into the worktree entry — either via
the workspace file's `settings` key or a `.vscode/settings.json` written
inside the worktree directory:

```json
{ "python.defaultInterpreterPath": "../../MP Field Data Analysis CT/.venv/Scripts/python.exe" }
```

This path is relative to the worktree root and resolves to the parent repo's
venv. VS Code reads this on folder open and suppresses the interpreter prompt.

For `isolated` mode: run `python -m venv {worktree}/.venv` after creation
and point the setting there instead.

### Q&A: Path-Based vs Symlink

**Q: What would be the pro for symlink?**

| | Symlink | Path-Based Config |
|---|---|---|
| Shell activation | `source .venv/bin/activate` works natively in worktree | Must point scripts at parent path explicitly |
| VS Code auto-discovery | VS Code finds `.venv/` in root without any config | Requires explicit `pythonPath` setting (but same end result) |
| pip install side-effects | Writes to shared venv (can be a feature or a footgun) | Same (both point at same venv) |
| **Windows NTFS** | Requires Developer Mode or admin rights for symlinks | ✅ Works everywhere, no permissions needed |
| **Deletion safety** | Risk: deleting worktree could follow symlink into parent | ✅ No risk — config is just a string path |
| **Broken link risk** | Silently broken if parent venv is recreated or moved | ✅ Easy to validate and fail loudly |
| **CI compatibility** | CI agents often restrict symlink creation | ✅ Always works |

**Verdict: path-based config wins.** Symlinks offer shell convenience but the
Windows NTFS friction, deletion risk, and CI incompatibility outweigh the
benefit. Path config solves the VS Code prompt problem (the primary goal)
without the downsides.

### Step 0d Changes Needed (v1.18.25)

1. After worktree creation, determine venv mode (config default + plan override).
2. **Shared mode:** Compute relative path from worktree to parent `.venv`.
  Write `python.defaultInterpreterPath` into a `.vscode/settings.json` inside
  the worktree. Resolve platform-correctly:
  - Windows: `{parent}/.venv/Scripts/python.exe`
  - Linux/macOS: `{parent}/.venv/bin/python`
3. **Isolated mode:** Run `python -m venv {worktree}/.venv` and point settings there.
4. On Step 8 cleanup: if `isolated`, delete `{worktree}/.venv` before `git worktree remove`.

### AF Config Addition (v1.18.25)

```ini
# WORKTREE_VENV_MODE: Python interpreter strategy for agent worktrees.
# Values:
#   shared   -- Worktree uses the parent repo's .venv (default, no duplication).
#               The interpreter path is written to the worktree's VS Code settings
#               at creation time to suppress the interpreter selection prompt.
#   isolated -- A new .venv is created inside the worktree (use for tasks expected
#               to change dependencies). Cleaned up automatically on Step 8.
# The coordinator may override to isolated per-workflow when the plan
# signals dependency changes are expected.
WORKTREE_VENV_MODE=shared
```

- Document is **living** — update as implementation progresses.
- Each phase should result in a commit to AAIG main with ticket ref.
- Testing should cover at least 3 parallel task scenarios before merge.

---

## 12. Known Gap: Hook Scripts Are CWD-Anchored (Observed 2026-04-16)

**Status:** ✅ RESOLVED v1.18.26 — sentinel Option A implemented

### Confirmed Working

The existing target-binding measures are effective at the coordinator/subagent
prompt level:
- Coordinator records the absolute worktree path at Step 0d and injects it
  into every subagent context block (`Worktree: {absolute_path}`).
- Subagents are aware of which worktree to work in and do so correctly.
- Branch-proof hooks (`test-writer-pretooluse`, `refactorer-pretooluse`) block
  writes if not on an `agent/*` branch.
- `coordinator-postmerge` stop hook lists active worktrees as advisory context.

This confirms the **central-controller / external-target** model is working at
the agent instruction layer.

### The New Problem: CWD-Anchored Hook Scripts

All hook scripts use `Get-Location` (or equivalent) to resolve paths:

```powershell
# e.g. implementer-stop.ps1, refactorer-stop.ps1, coordinator-posttooluse.ps1
$confPath = Join-Path (Get-Location) '.github/af-env.conf'
$status   = git status --porcelain -- "$SRC_DIR/" tests/
```

`Get-Location` returns VS Code's active CWD — the **main checkout**, not the
active worktree. Consequences:

| Hook | What it does wrong |
|---|---|
| `implementer-stop` | Reads `SRC_DIR` from main checkout `af-env.conf`; runs pytest against main checkout; freshness check (`test-log.json`, git diff) targets main checkout |
| `refactorer-stop` | Same: pytest + new-file check run in main checkout |
| `coordinator-posttooluse` | Dirty-state detective reads `git status` from main checkout — never sees worktree changes |
| `test-writer-stop` | pytest run from main checkout |
| `test-writer-pretooluse` / `refactorer-pretooluse` | `git branch --show-current` reflects main checkout branch, not worktree's |

**Net effect:** Quality gates (tests pass, no new files, dirty-state) check the
wrong directory. They give false green on the main checkout while the worktree
may have failing tests or unintended changes — or vice versa.

### Candidate Solutions

#### Option A — Sentinel File (`.github/.active-worktree`)

**Idea:** Coordinator writes the absolute worktree path to
`.github/.active-worktree` in the main checkout at Step 0d. All hook scripts
read this file; if present, they `Push-Location` to the worktree path before
running git/pytest, then `Pop-Location`.

```powershell
$sentinelPath = Join-Path $PSScriptRoot '../.active-worktree'
$repoRoot     = if (Test-Path $sentinelPath) { Get-Content $sentinelPath -Raw | Trim() }
                else                         { Get-Location }
```

- **Pros:** Persistent across VS Code sessions; no env-var lifetime issue;
  single source of truth; easy to audit (`cat .github/.active-worktree`).
- **Cons:** Only one "active" worktree at a time per main checkout (fine for
  the current coordinator model); must be cleared at Step 8.

#### Option B — Environment Variable (`ACTIVE_WORKTREE_PATH`)

**Idea:** Coordinator sets `$env:ACTIVE_WORKTREE_PATH` at task start. Hooks
read it.

- **Pros:** No file I/O.
- **Cons:** Env vars don't survive VS Code restarts or new terminal
  sessions. Fragile.

#### Option C — `git rev-parse --git-common-dir` + walk-up

**Idea:** Hooks detect they are being run from a worktree by checking
`git rev-parse --git-common-dir` vs `git rev-parse --git-dir`. If they
differ, the current dir is a worktree and hooks can self-anchor. But hooks
always run in VS Code's CWD (main checkout), so this never fires.

- **Verdict:** Doesn't help — hooks don't run inside the worktree.

#### Option D — Hooks Accept an Optional Worktree Path Argument

**Idea:** Coordinator calls hooks explicitly (via `run_in_terminal`) with an
argument: `.github/hooks/scripts/implementer-stop.ps1 -WorktreePath {abs_path}`.
Hooks accept an optional `$WorktreePath` parameter; fall back to CWD if absent.

- **Pros:** Explicit and auditable per invocation.
- **Cons:** Requires coordinator to change how it invokes hooks; VS Code
  trigger hooks (not manually called) still run without the argument —
  so Stop hooks at agent completion would still be CWD-anchored.

#### Option E — VS Code Multi-Root Workspace: Open Worktree as Root

**Idea:** Already partially implemented (v1.18.24 auto-adds worktree to
`.code-workspace`). If the user has the worktree root selected as the
"active" folder in VS Code, `Get-Location` would return the worktree path.

- **Pros:** Zero hook changes needed — CWD changes naturally.
- **Cons:** Depends on the user manually selecting the worktree folder
  in VS Code Explorer. Not deterministic. Stop hooks still fire from
  whichever folder is the VS Code active root.

### Recommended Solution: Option A (Sentinel File)

**Rationale:**
- Persistent, file-based, tool-independent.
- Works for all hook types (pretooluse, posttooluse, stop).
- Coordinator already writes to `.github/` (test-log.json, etc.) — same pattern.
- Trivially auditable and clearable.
- Option D is complementary but cannot cover VS Code-triggered Stop hooks.

**Implementation sketch:**

1. **Step 0d (coordinator):** After worktree creation, write absolute path to
   `.github/.active-worktree`. Overwrite if file exists (only one active WT at a time).
2. **Step 8 (coordinator):** Delete `.github/.active-worktree` after cleanup.
3. **All hook scripts:** Replace `Get-Location` root resolution with:
   ```powershell
   function Get-RepoRoot {
       $sentinel = Join-Path $PSScriptRoot '../.active-worktree'
       if (Test-Path $sentinel) { return (Get-Content $sentinel -Raw).Trim() }
       return (Get-Location).Path
   }
   $repoRoot = Get-RepoRoot
   $confPath = Join-Path $repoRoot '.github/af-env.conf'
   # git commands: git -C $repoRoot status ...
   # pytest: Push-Location $repoRoot; pytest ...; Pop-Location
   ```
4. Add `.github/.active-worktree` to `.gitignore` (it is already ignored via
   the `.github` rule — verify).

**Scope:** ~6 hook scripts + coordinator Step 0d + Step 8 prose update.
**Risk:** Low — fallback to `Get-Location` preserves current behaviour when
no worktree is active.

### Open Questions

1. Should the sentinel file be a plain path, or a structured file (JSON with
   `path`, `workflow_id`, `branch`) to support future multi-worktree parallelism?
2. Should the `session-context` start hook also read the sentinel and inject the
   active worktree path as session context? (Would surface it prominently at
   every session start.)
3. Future: if multiple worktrees are ever active simultaneously (different
   VS Code windows), the single-sentinel model breaks. A registry file
   (`{ "workflow-id": "/abs/path" }`) would scale — but is over-engineering
   for now.

---

## 13. Architecture Decision: Where Should AAIG Live During Worktree Tasks? (2026-04-16)

**Status:** 🔴 OPEN — decision pending

### Context

Section 12 describes a sentinel file (Option A) to make CWD-anchored hook
scripts aware of the active worktree. A sentinel works for a single active
worktree but breaks for parallel execution (only one sentinel path at a time).
This section evaluates the deeper architectural question:

> **Should AAIG be auto-deployed into each worktree at creation, so hooks
> run natively in the correct context?**

### How Hooks Currently Fire

VS Code extension hooks (`run`, `stop`, `pretooluse`, `posttooluse`) are
invoked by the VS Code process. They always run with CWD set to the
**active workspace root that VS Code was opened against** — in a multi-root
`.code-workspace`, this is typically the folder that was most recently
active or the first root. Critically:

- Hooks are loaded from the **main checkout's** `.github/hooks/` (the
  deployed AAIG location).
- Worktrees do not have a `.github/` directory — `.github` is gitignored
  in the target project, so it is not part of the tracked working tree.
  Each worktree is a fresh checkout of tracked files only.
- **There is no mechanism by which a worktree's hooks fire instead of the
  main checkout's hooks.** VS Code does not run hooks per-workspace-root.

### Option A Revisited: Sentinel File (Parallelism Ceiling)

```
main checkout: .github/.active-worktree = /abs/path/to/wt/task-x
hooks: read sentinel → redirect all path lookups to worktree
```

- ✅ No deployment complexity
- ✅ Works for the current single-active-WT model
- ❌ **Hard ceiling: one active task at a time.** Sentinel is overwritten
  when a second WT is created; hooks now point to the wrong directory for
  the first task.
- A registry file (`{ task-x: path, task-y: path }`) could extend this,
  but hooks would need a way to know *which* task is currently executing —
  there is no reliable per-invocation identity available.

### Option B: Auto-Deploy AAIG into Each Worktree

**Idea:** When the coordinator creates a worktree (`git worktree add …`),
it immediately runs `deploy.ps1 -TargetDir {worktree_path}` to install a
full AAIG copy into `{worktree}/.github/`. Hooks then run natively in the
worktree context because VS Code (if opened to the worktree root) uses
that `.github/`.

#### How It Would Work

1. Coordinator Step 0d: after `git worktree add`, run
   `deploy.ps1 -TargetDir {worktree_path}`.
2. VS Code workspace: the worktree folder is already added as a root (v1.18.24).
   If the user opens a file in the worktree folder, VS Code's active root
   shifts to that folder, and hooks from `{worktree}/.github/hooks/` fire.
3. Step 8 cleanup: worktree directory is removed entirely (including its
   `.github/`) — no separate cleanup step needed.

#### Parallelism

Each worktree has its own `.github/` → its own `af-env.conf`, `test-log.json`,
hooks. **Hooks for task-x fire from worktree-x's hooks; hooks for task-y
fire from worktree-y's hooks.** No sentinel needed. True parallelism is
possible.

#### Risks

| Risk | Description | Severity |
|---|---|---|
| **Deployment drift (config)** | `deploy.ps1` reads `af-env.conf` from the main checkout and merges it with the AAIG template. In v1.18.x, `UpdateConfig` only adds missing keys — but if a key was intentionally customised in the main checkout, it copies correctly. If `deploy.ps1` has a bug or the template changed, the worktree config may differ silently. | Medium |
| **Deployment drift (intentional)** | If the user manually edits main checkout's `af-env.conf` between WT creation and task completion (e.g., changes `SRC_DIR`), the WT has the old value. This is actually **correct** (WT should be stable during its task) but feels surprising. | Low |
| **Version drift** | If AAIG is updated in the AAIG repo and re-deployed to the main checkout mid-task, the worktree runs on the old deployed version. The main checkout and worktrees diverge on hook behaviour. | Low–Medium |
| **Hook invocation uncertainty** | VS Code's per-root hook selection in multi-root workspaces is not officially documented for multi-root. If VS Code uses the *first* workspace root's hooks regardless of active file, auto-deploy gains nothing — hooks still run from the main checkout. This is the **critical unknown** and must be empirically verified. | High (if unknown) |
| **Deploy time** | `deploy.ps1` copies ~50 files. On a fast SSD this is <1s. On OneDrive-synced paths (as in the MP project) it may be slower and trigger sync contention. | Low |
| **Nested gitignore complexity** | The worktree's `.github/` is gitignored by the shared `.gitignore`. This is correct — we don't want AAIG committed. But the gitignore applies to the shared index, so attempts to `git status` inside the worktree still ignore `.github/`. No issue, just worth confirming. | Low |

#### The Critical Unknown: VS Code Hook Routing in Multi-Root

VS Code's hooks docs do not specify which workspace root's `copilot-instructions.md`
or hooks folder is used when multiple roots are open and the user is editing
a file under a specific root. Empirical testing needed:

1. Open `.code-workspace` with two roots: main checkout + worktree.
2. Open a file under the worktree root.
3. Trigger a stop hook — does it load from `{worktree}/.github/hooks/` or
   from `{main}/.github/hooks/`?

If VS Code uses the **active file's nearest root**: auto-deploy works perfectly.
If VS Code uses **the first root unconditionally**: auto-deploy gives no benefit
for hook routing (but still provides correct `af-env.conf`, `test-log.json`, etc.
for agent scripts that reference relative paths).

### Option C: Hybrid (Deploy Minimal Config Only)

**Idea:** Do not deploy full AAIG into worktrees. Only copy `af-env.conf`
(and optionally `test-log.json`) from the main checkout into
`{worktree}/.github/`. Hook scripts continue to run from the main checkout
but resolve config via the sentinel pointing to the worktree.

- ✅ No full deploy overhead or version drift
- ✅ Config is always correct in the worktree
- ❌ Doesn't solve hook routing (still CWD-anchored)
- ❌ Still has the single-sentinel parallelism ceiling

### Recommendation

| Scenario | Recommended option |
|---|---|
| Single active worktree at a time (current reality) | **Option A (Sentinel)** — minimal complexity |
| Multiple parallel worktrees in same VS Code window | **Option B (Auto-deploy)** — but verify hook routing first |
| Multiple parallel worktrees in separate VS Code windows | **Option B** — each window opens one worktree root; hooks naturally use that root's `.github/` |

**Proposed next step:** Empirically test Option B's hook routing (two roots,
one `.code-workspace`, trigger stop hook from worktree). If VS Code routes
correctly, Option B is the right long-term answer and Option A is a stopgap.

### Deployment Drift Mitigation (if Option B adopted)

1. Use `deploy.ps1 -SkipConfig` flag (to be implemented): copy all AAIG
   files except `af-env.conf`. Inherit the main checkout's `af-env.conf`
   by symlinking or copying once at creation time.
2. Record the AAIG `VERSION` in a `{worktree}/.github/.deploy-version` file
   at deploy time. Session-context hook can warn if main checkout's deployed
   version differs from the worktree's — surfacing version drift explicitly.
3. At Step 8 cleanup: `git worktree remove` deletes the entire worktree
   directory, including `.github/`. No extra cleanup needed.

### Open Questions

1. Does VS Code route hooks by active-file's nearest workspace root or by
   the first root in `.code-workspace`? (**Must verify empirically.**)
2. Should `deploy.ps1` gain a `-SkipConfig` flag for worktree deployments?
3. Is there value in the `{worktree}/.github/.deploy-version` drift warning
   even if hook routing does not work as hoped?
