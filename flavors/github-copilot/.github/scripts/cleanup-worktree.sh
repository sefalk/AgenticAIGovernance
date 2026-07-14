#!/usr/bin/env bash
# Safely remove a git worktree after task completion.
#
# Usage:
#   .github/scripts/cleanup-worktree.sh feat-auth
#   .github/scripts/cleanup-worktree.sh feat-auth --force
#
# What it does:
#   1. Reads WORKTREE_DIR from af-env.conf (default: ../wt)
#   2. Resolves the worktree path for the given workflow ID
#   3. Verifies the worktree exists in git worktree list
#   4. Checks the worktree is clean (git status --porcelain must be empty)
#   5. Removes the worktree
#   6. Prunes stale references
#   7. Verifies removal
#
# Exit codes:
#   0 = success, worktree removed
#   1 = validation failure (not registered or not found)
#   2 = worktree is dirty -- halts and reports uncommitted changes
#   3 = removal failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONF="$REPO_ROOT/.github/af-env.conf"

# --- Defaults ---
WORKFLOW_ID=""
FORCE=false
WT_DIR="../wt"
BRANCH_PREFIX="agent"

# --- Load config ---
if [ -f "$CONF" ]; then
    _wt=$(grep '^WORKTREE_DIR=' "$CONF" | cut -d= -f2 | xargs)
    _bp=$(grep '^WORKTREE_BRANCH_PREFIX=' "$CONF" | cut -d= -f2 | xargs)
    [ -n "$_wt" ] && WT_DIR="$_wt"
    [ -n "$_bp" ] && BRANCH_PREFIX="$_bp"
fi

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) FORCE=true; shift ;;
        -*) echo "Unknown option: $1" >&2; exit 1 ;;
        *) WORKFLOW_ID="$1"; shift ;;
    esac
done

if [ -z "$WORKFLOW_ID" ]; then
    echo "Usage: cleanup-worktree.sh <workflow-id> [--force]" >&2
    echo "  Example: cleanup-worktree.sh feat-auth" >&2
    exit 1
fi

BRANCH_NAME="${BRANCH_PREFIX}/${WORKFLOW_ID}"
WT_PATH="$(python3 -c "import os; print(os.path.normpath(os.path.join('$REPO_ROOT', '$WT_DIR', '$WORKFLOW_ID')))" 2>/dev/null || echo "$REPO_ROOT/$WT_DIR/$WORKFLOW_ID")"

echo ""
echo "=== Worktree Cleanup ==="
echo "  Workflow ID : $WORKFLOW_ID"
echo "  Branch      : $BRANCH_NAME"
echo "  Path        : $WT_PATH"
echo ""

cd "$REPO_ROOT"

# --- Verify worktree is registered ---
if ! git worktree list --porcelain 2>/dev/null | grep -qF "worktree $WT_PATH"; then
    echo "WARNING: Worktree path '$WT_PATH' is not registered in 'git worktree list'." >&2
    echo "  Active worktrees:"
    git worktree list
    echo ""
    echo "  If the directory was deleted manually, run: git worktree prune"
    exit 1
fi

# --- Check worktree is clean ---
dirty=$(git -C "$WT_PATH" status --porcelain 2>/dev/null || true)
if [ -n "$dirty" ]; then
    echo ""
    echo "ERROR: Worktree is dirty. Uncommitted changes found:" >&2
    echo "$dirty"
    echo ""
    echo "  Options:"
    echo "    Commit   : cd \"$WT_PATH\" && git add <files> && git commit -m \"...\""
    echo "    Discard  : cd \"$WT_PATH\" && git checkout -- ."
    echo "    Stash    : cd \"$WT_PATH\" && git stash"
    echo ""
    echo "  After cleaning: re-run cleanup-worktree.sh $WORKFLOW_ID"
    exit 2
fi

echo "  Status: clean"

# --- Remove worktree ---
echo "  Removing worktree..."
if [ "$FORCE" = true ]; then
    git worktree remove --force "$WT_PATH"
else
    git worktree remove "$WT_PATH"
fi

if [ $? -ne 0 ]; then
    echo ""
    echo "ERROR: 'git worktree remove' failed." >&2
    echo "  If the worktree is locked, run:"
    echo "    git worktree unlock \"$WT_PATH\""
    echo "  Then retry: cleanup-worktree.sh $WORKFLOW_ID"
    echo "  Or use --force if you are certain there is nothing to keep."
    exit 3
fi

# --- Prune stale references ---
echo "  Pruning stale references..."
git worktree prune

# --- Verify removal ---
if git worktree list 2>/dev/null | grep -qF "$WT_PATH"; then
    echo "  WARNING: Path still appears in 'git worktree list'. Manual check recommended."
else
    echo "  Verified: worktree removed"
fi

echo ""
echo "=== Cleanup Complete ==="
echo "  Worktree : $WT_PATH  [REMOVED]"
echo "  Branch   : $BRANCH_NAME  [local branch still exists -- delete when ready]"
echo ""
echo "  To delete the local branch (after confirming merge):"
echo "    git branch -d $BRANCH_NAME"
echo ""

exit 0
