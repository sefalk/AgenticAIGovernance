---
name: git-worktrees
description: Bootstrap, manage, and clean up git worktrees for parallel agent task execution. Lifecycle commands, coordinator step 0d/8, troubleshooting locked/stale worktrees, and VS Code integration.
argument-hint: '[workflow-id] [base-branch]'
activation:
  signals:
    af_config:
      WORKTREE_ENABLED: true
  agents: [coordinator]
  priority: recommended
---
<!-- copilot:generated | implementer | 2026-04-14 -->

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

### Step 0d: Create

```bash
# Read from af-env.conf
WT_DIR=$(grep "^WORKTREE_DIR=" .github/af-env.conf | cut -d= -f2 | xargs)
WT_DIR="${WT_DIR:-../wt}"

git worktree add "$WT_DIR/$WORKFLOW_ID" -b "agent/$WORKFLOW_ID" dev
```

**PowerShell equivalent:**
```powershell
$afenv = Get-Content .github/af-env.conf | Where-Object { $_ -match '^WORKTREE_DIR=' }
$WT_DIR = if ($afenv) { ($afenv -split '=')[1].Trim() } else { '../wt' }
git worktree add "$WT_DIR/$env:WORKFLOW_ID" -b "agent/$env:WORKFLOW_ID" dev
```

### Step 8: Cleanup

```bash
# Only after human confirms merge
git status --porcelain "$WT_DIR/$WORKFLOW_ID"   # must be empty
git worktree remove "$WT_DIR/$WORKFLOW_ID"
git worktree prune
git worktree list                                # verify removal
```

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
| `WORKTREE_DIR` | `../wt` | Root directory for all agent worktrees |
| `WORKTREE_BRANCH_PREFIX` | `agent` | Branch prefix; all worktree branches = `{prefix}/{id}` |

Read in scripts:
```bash
WT_DIR=$(grep "^WORKTREE_DIR=" .github/af-env.conf | cut -d= -f2 | xargs)
: "${WT_DIR:=../wt}"
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
