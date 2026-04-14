#!/usr/bin/env bash
# copilot:generated | implementer | 2026-04-14
# Bootstrap a new git worktree for an agent task.
#
# Usage:
#   .github/scripts/setup-worktree.sh feat-auth
#   .github/scripts/setup-worktree.sh fix-db-pool --base main
#   .github/scripts/setup-worktree.sh feat-auth --skip-venv
#
# What it does:
#   1. Reads WORKTREE_DIR from af-env.conf (default: ../wt)
#   2. Validates the workflow ID slug
#   3. Checks for stale worktrees and prunes them
#   4. Creates the worktree at {WORKTREE_DIR}/{WorkflowId} on branch agent/{WorkflowId}
#   5. Bootstraps the Python venv (symlink strategy or fresh install)
#   6. Verifies .github/ hooks are accessible
#   7. Prints the worktree path for the coordinator to record
#
# Exit codes:
#   0 = success, worktree ready
#   1 = validation failure
#   2 = worktree creation failed
#   3 = venv bootstrap failed (non-fatal with --skip-venv)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONF="$REPO_ROOT/.github/af-env.conf"

# --- Defaults ---
WORKFLOW_ID=""
BASE_BRANCH="dev"
SKIP_VENV=false
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
        --base) BASE_BRANCH="$2"; shift 2 ;;
        --skip-venv) SKIP_VENV=true; shift ;;
        -*) echo "Unknown option: $1" >&2; exit 1 ;;
        *) WORKFLOW_ID="$1"; shift ;;
    esac
done

if [ -z "$WORKFLOW_ID" ]; then
    echo "Usage: setup-worktree.sh <workflow-id> [--base <branch>] [--skip-venv]" >&2
    echo "  Example: setup-worktree.sh feat-auth" >&2
    exit 1
fi

# --- Validation ---
if ! echo "$WORKFLOW_ID" | grep -qE '^[a-z0-9][a-z0-9-]*$'; then
    echo "ERROR: Invalid workflow ID '$WORKFLOW_ID'." >&2
    echo "       Must match '^[a-z0-9][a-z0-9-]+' (e.g. feat-auth, fix-db-pool)." >&2
    exit 1
fi

BRANCH_NAME="${BRANCH_PREFIX}/${WORKFLOW_ID}"
WT_PATH="$(cd "$REPO_ROOT" && python3 -c "import os; print(os.path.normpath(os.path.join('$REPO_ROOT', '$WT_DIR', '$WORKFLOW_ID')))" 2>/dev/null || echo "$REPO_ROOT/$WT_DIR/$WORKFLOW_ID")"

echo ""
echo "=== Worktree Bootstrap ==="
echo "  Workflow ID : $WORKFLOW_ID"
echo "  Branch      : $BRANCH_NAME"
echo "  Path        : $WT_PATH"
echo "  Base        : $BASE_BRANCH"
echo ""

# --- Repo health check ---
cd "$REPO_ROOT"
if ! git status --porcelain >/dev/null 2>&1; then
    echo "ERROR: Repository is not healthy ('git status' failed). Fix repo state first." >&2
    exit 1
fi

# --- Base branch check ---
if ! git rev-parse "refs/heads/$BASE_BRANCH" >/dev/null 2>&1; then
    echo "ERROR: Base branch '$BASE_BRANCH' does not exist locally." >&2
    echo "       Run 'git fetch' or create the branch first." >&2
    exit 1
fi

# --- Stale worktree audit ---
echo "  Checking for stale worktrees..."
if git worktree list --porcelain 2>/dev/null | grep -q "prunable"; then
    echo "  WARNING: Prunable stale entries found. Running 'git worktree prune'..."
    git worktree prune
fi

# --- Path collision check ---
if [ -e "$WT_PATH" ]; then
    echo "ERROR: Worktree path '$WT_PATH' already exists." >&2
    echo "       Is another task still running? Run 'git worktree list' to check." >&2
    exit 1
fi

# --- Create worktree ---
echo "  Creating worktree..."
if ! git worktree add "$WT_PATH" -b "$BRANCH_NAME" "$BASE_BRANCH"; then
    echo "ERROR: Failed to create worktree." >&2
    exit 2
fi

# --- Verify hooks accessible ---
if [ -d "$WT_PATH/.github/hooks" ]; then
    echo "  .github/hooks accessible: OK"
else
    echo "  WARNING: .github/hooks not found in worktree. Hooks may not fire correctly."
fi

# --- Python venv bootstrap ---
if [ "$SKIP_VENV" = false ]; then
    echo "  Setting up Python venv..."
    MAIN_VENV="$REPO_ROOT/.venv"
    WT_VENV="$WT_PATH/.venv"

    if [ -d "$MAIN_VENV" ]; then
        # Symlink to main venv — avoids full reinstall
        if ln -s "$MAIN_VENV" "$WT_VENV" 2>/dev/null; then
            echo "  Venv: symlink to main .venv created"
        else
            echo "  WARNING: Could not symlink venv. Trying fresh install..."
            SKIP_VENV=true
        fi
    else
        SKIP_VENV=true
    fi

    if [ "$SKIP_VENV" = true ]; then
        echo "  Venv: no shared venv found -- creating fresh..."
        cd "$WT_PATH"
        PYTHON=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "")
        if [ -z "$PYTHON" ]; then
            echo "  WARNING: python not found. Skipping venv setup." >&2
        elif ! "$PYTHON" -m venv .venv; then
            echo "  WARNING: venv creation failed. Skipping." >&2
        else
            # Install deps
            RUN_DEPS="$WT_PATH/.github/scripts/run-deps.sh"
            if [ -x "$RUN_DEPS" ]; then
                bash "$RUN_DEPS" --scope dev
            else
                DEP_DEV_FILE="requirements-dev.txt"
                _d=$(grep '^DEP_DEV_FILE=' "$CONF" 2>/dev/null | cut -d= -f2 | xargs)
                [ -n "$_d" ] && DEP_DEV_FILE="$_d"
                PIP="$WT_PATH/.venv/bin/pip"
                [ -f "$PIP" ] && "$PIP" install -r "$DEP_DEV_FILE"
            fi
        fi
        cd "$REPO_ROOT"
    fi
else
    echo "  Venv: skipped (--skip-venv)"
fi

# --- Summary ---
echo ""
echo "=== Worktree Ready ==="
echo "  Path   : $WT_PATH"
echo "  Branch : $BRANCH_NAME"
echo "  Open   : code \"$WT_PATH\""
echo ""
echo "  Next: Open the worktree in VS Code and start the agent workflow."
echo "  Record in plan: worktree: $WT_PATH"
echo ""

exit 0
