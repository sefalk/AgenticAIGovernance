---
name: git-worktrees
description: Bootstrap, manage, and clean up git worktrees for parallel agent task execution. Lifecycle commands, coordinator step 0d/8, troubleshooting locked/stale worktrees, and VS Code integration.
argument-hint: '[workflow-id] [base-branch]'
metadata:
  activation:
    signals:
      af_config:
        WORKTREE_ENABLED: true
    agents: [coordinator]
    priority: recommended
---

**Domain:** Git workflow / Parallel task execution  
**Primary consumers:** coordinator, researcher  
**When to use:** Any task that creates a new `agent/{id}` branch AND the human
wants parallel execution without branch-switching overhead.

---

## 1. Concepts

### What is a Worktree?

A git worktree is an additional working directory linked to the same repository.

```
repo/            ← main checkout (on dev), shared .git
../wt/
  feat-auth/     ← worktree for agent/feat-auth branch
  fix-db/        ← worktree for agent/fix-db branch
```

- **Shared history:** All worktrees commit to the same repository.
- **Isolated checkout:** Each worktree has its own branch, index, `HEAD`.
- **One branch, one worktree:** A branch cannot be checked out in two worktrees simultaneously.
- **Hooks are shared:** `.github/` hooks work identically in all worktrees because they resolve through the common `.git`.

### Key Commands

| Command | Purpose |
|---------|---------|
| `git worktree add <path> -b <branch> <base>` | Create worktree + new branch |
| `git worktree add <path> <existing-branch>` | Create worktree for existing branch |
| `git worktree list` | List all active worktrees |
| `git worktree list --porcelain` | Machine-readable format (includes HEAD, branch, locked/prunable state) |
| `git worktree remove <path>` | Remove worktree (must be clean) |
| `git worktree remove --force <path>` | Force remove (use only if locked and human-confirmed) |
| `git worktree lock <path>` | Prevent accidental removal (e.g., on removable media) |
| `git worktree unlock <path>` | Remove lock |
| `git worktree prune` | Remove stale entries from `.git/worktrees/` |
| `git rev-parse --git-common-dir` | Returns the shared `.git` directory (same regardless of worktree) |
| `git rev-parse --git-dir` | Returns the per-worktree `.git` file (differs per worktree) |

---

## 2. Lifecycle in the AF Workflow

This is the coordinator's runbook for **Step 0d** (bootstrap) and **Step 8**
(cleanup). `coordinator.agent.md` names the two steps and their preconditions;
the executable detail lives here.

### Applicability

| Condition | Behaviour |
|---|---|
| `WORKTREE_ENABLED=false` (default) | Skip both steps entirely. All subagent work runs in the main checkout. Intended for CI/CD or single-threaded environments; not recommended for parallel workflows. |
| `WORKTREE_ENABLED=true`, Trivial Fix | Skip — single file, no parallel work expected. |
| `WORKTREE_ENABLED=true`, all other workflows | Run Step 0d after branch creation, Step 8 after the human confirms the merge. |

### Step 0d: Create

**1. Resolve `WORKTREE_DIR`.** Read it from `.github/af-env.conf`. If empty or
unset, compute `../{git_repo_folder_name}_worktrees` — e.g. a repo named
`MP Field Data Analysis CT` yields `../MP Field Data Analysis CT_worktrees`.
Record the resolved path.

```bash
WT_DIR=$(grep "^WORKTREE_DIR=" .github/af-env.conf | cut -d= -f2 | xargs)
: "${WT_DIR:=../$(basename "$(git rev-parse --show-toplevel)")_worktrees}"
```

```powershell
$afenv = Get-Content .github/af-env.conf | Where-Object { $_ -match '^WORKTREE_DIR=' }
$WT_DIR = ($afenv -split '=', 2)[1].Trim()
if (-not $WT_DIR) { $WT_DIR = "../$(Split-Path -Leaf (git rev-parse --show-toplevel))_worktrees" }
```

**2. Check for stale worktrees.** Run `git worktree list --porcelain`. If
prunable entries exist, run `git worktree prune` and report to the human.

**3. Create:**

```bash
git worktree add "$WT_DIR/$WORKFLOW_ID" -b "agent/$WORKFLOW_ID" dev
```

**4. Write the active-worktree sentinel.** Immediately after creation, write the
absolute worktree path to `.github/.active-worktree` in the **main checkout**:

```powershell
Set-Content -Path .github/.active-worktree -Value {absolute_worktree_path} -NoNewline
```

This lets the hook scripts (pretooluse, stop) resolve `$codeRoot` to the active
worktree instead of the main-checkout CWD, so quality gates (pytest,
`git status`, `SRC_DIR` lookups) target the worktree.

> ⚠️ **Single-worktree constraint:** only one active sentinel is supported.
> Creating a second worktree while the first is active overwrites it — parallel
> worktrees are not supported until Option B (auto-deploy) is verified.
> See `ideas/feature-git-worktrees.md` §12–13.

**5. Verify** the worktree directory exists and is accessible.

**6. Resolve the Python interpreter — without prompting the user.** Read
`WORKTREE_VENV_MODE` from `.github/af-env.conf` (default `shared`).

- `shared`: point at the parent repo interpreter —
  `{repo_root}/.venv/Scripts/python.exe` (Windows) or
  `{repo_root}/.venv/bin/python` (Linux/macOS) — and write
  `python.defaultInterpreterPath` into `{worktree}/.vscode/settings.json`.
  If the parent `.venv` is missing, fall back to `isolated` for this workflow.
- `isolated` (or the fallback above): create `{worktree}/.venv` and point
  `python.defaultInterpreterPath` at it.

Only ask the human to choose if **both** strategies fail.

**7. Add to the VS Code workspace.** If a `.code-workspace` file exists at the
repo root, add the worktree folder; otherwise create one with this structure:

```json
{
  "folders": [
    { "path": "." },
    { "path": "{WORKTREE_DIR}/{workflow-id}", "name": "agent/{workflow-id}" }
  ]
}
```

Narrate: `"VS Code workspace updated to include worktree folder."`

**8. Record** `worktree: {absolute_path}` in the plan metadata (or in the WIP
checkpoint for Trivial/Quick Fix).

**9. Narrate:** `"Worktree created at {path} on branch agent/{workflow-id}. Proceeding inside worktree."`

All subsequent subagent calls include the worktree path in their context block
(see `coordinator.agent.md` § Subagent Context Injection).

### Step 8: Cleanup

Runs only after the human confirms the branch was merged to `dev`.

1. **Confirm merge:** `"Please confirm branch agent/{id} has been merged to dev."`
2. **Check clean:** `git status --porcelain` in the worktree. If dirty, **halt
   and escalate** — never force-remove.
3. **Delete the sentinel** from the main checkout, returning hooks to
   main-checkout mode *before* removal:
   ```powershell
   Remove-Item -Force .github/.active-worktree -ErrorAction SilentlyContinue
   ```
4. **Isolated venv cleanup:** if this workflow used `WORKTREE_VENV_MODE=isolated`,
   remove `{worktree}/.venv` before removing the worktree.
5. **Remove:** `git worktree remove {WORKTREE_DIR}/{workflow-id}`
6. **Prune:** `git worktree prune`
7. **Verify:** `git worktree list` must no longer show the path.
8. **Clean up the workspace file** (if `.code-workspace` exists): remove the
   worktree folder entry.
9. **Narrate:** `"Worktree {path} removed. Branch agent/{id} cleanup complete."`
10. **Log:** record the cleanup timestamp and final commit hash in the workflow log.

---

## 3. Troubleshooting

### Problem: `fatal: '{path}' is already checked out`

A branch is checked out in another worktree.  
**Resolution:** Run `git worktree list` to find where. Finish or remove that worktree first.

### Problem: `fatal: '{path}' is locked`

The worktree was locked (e.g., on removable media, or manually).  
**Resolution:**
```bash
git worktree unlock ../wt/{id}
git worktree remove ../wt/{id}
```
If it fails again with `--force`, confirm with the human before forcing.

### Problem: `git worktree remove` says "working tree is dirty"

Uncommitted changes exist in the worktree.  
**Resolution** (human decides):
1. `git -C ../wt/{id} status` — see what's uncommitted.
2. Commit if valuable, or `git -C ../wt/{id} checkout -- .` to discard.
3. Then retry `git worktree remove`.

### Problem: Stale entry in `git worktree list` (directory missing)

The worktree directory was deleted externally without `git worktree remove`.  
**Resolution:**
```bash
git worktree prune   # safe; only removes entries where dir is gone
git worktree list    # verify clean
```

### Problem: Agent committed to wrong branch / wrong worktree

A context check gate should have caught this. If it didn't:
1. Check `git log --oneline -5` in both worktrees.
2. Use `git cherry-pick` to move the commit to the correct branch.
3. Use `git reset --soft HEAD~1` on the wrong branch (human executes).

### Problem: Divergence from dev (long-lived branch)

After several days, `dev` has new commits the worktree branch doesn't have.  
**Resolution (human executes in the worktree):**
```bash
cd ../wt/{id}
git fetch origin
git merge origin/dev          # or: git rebase origin/dev (if single-developer)
```
Agents do NOT rebase. If merge conflicts arise, human resolves.

### Problem: venv missing in new worktree

Worktrees don't automatically inherit the venv from the main checkout.  
**Resolution:** Run the bootstrap script (see `scripts/setup-worktree.ps1/.sh`):
```bash
cd ../wt/{id}
python -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"       # or: pip install -r requirements-dev.txt
```
Alternatively, symlink the existing venv:
```bash
ln -s ../../{repo}/.venv ../wt/{id}/.venv   # only if paths are stable
```

### Problem: VS Code opens the wrong folder

Each worktree is an independent VS Code workspace. Open explicitly:
```bash
code ../wt/{id}
```
Or: `File > Add Folder to Workspace` to see multiple worktrees side-by-side.

---

## 4. Verification Patterns

### Confirm you're in a worktree (not the main checkout):
```bash
git rev-parse --git-dir           # worktree: ../.git/worktrees/{id}
git rev-parse --git-common-dir    # always: /path/to/repo/.git
```
If `--git-dir` == `--git-common-dir`, you're in the main checkout.

### List all worktrees with branch info:
```bash
git worktree list
# Output:
# /path/to/repo           abc1234 [dev]
# /path/to/wt/feat-auth   def5678 [agent/feat-auth]
# /path/to/wt/fix-db      ghi9012 [agent/fix-db]
```

### Check for prunable (stale) entries:
```bash
git worktree list --porcelain | grep -A3 "prunable"
```

---

## 5. Configuration Reference

All worktree configuration lives in `.github/af-env.conf`:

| Key | Default | Description |
|-----|---------|-------------|
| `WORKTREE_ENABLED` | `false` | Master switch. When false, Steps 0d and 8 are skipped entirely. |
| `WORKTREE_DIR` | *(empty)* | Root directory for agent worktrees. Empty means: compute `../{git_repo_folder_name}_worktrees`. |
| `WORKTREE_VENV_MODE` | `shared` | `shared` reuses the parent repo `.venv`; `isolated` creates one per worktree. |
| `WORKTREE_BRANCH_PREFIX` | `agent` | Branch prefix; all worktree branches = `{prefix}/{id}` |

Read in scripts:
```bash
WT_DIR=$(grep "^WORKTREE_DIR=" .github/af-env.conf | cut -d= -f2 | xargs)
: "${WT_DIR:=../$(basename "$(git rev-parse --show-toplevel)")_worktrees}"
```

---

## 6. `.gitignore` Recommendations

Add to the project root `.gitignore`:
```gitignore
# Git worktree directories (created by coordinator during agent task execution)
../wt/
/worktrees/
/.worktrees/
```

> Note: `../wt/` is a relative path entry. Git resolves this from the repo root.
> Some tools may not honor relative paths in `.gitignore` — test with `git check-ignore -v ../wt/test`.
> If needed, use an absolute path or a sibling `.gitignore` in the parent directory.

---

## 7. Limitations & Edge Cases

- **One branch per worktree:** Cannot check out `agent/feat-x` in two worktrees simultaneously.
- **Submodules:** Submodule paths may collide across worktrees. Use absolute submodule paths.
- **File watchers (vscode):** VS Code file watchers may not distinguish worktrees from main checkout. Open each worktree in its own window for best experience.
- **Network drives / OneDrive:** Worktrees on network-synced paths (OneDrive, Dropbox) can exhibit lock issues. Prefer local drives.
- **`.git` is a file, not a dir:** In each worktree, `.git` is a plain text file (not a directory) pointing to `.git/worktrees/{id}`. This is expected and correct.
