#!/usr/bin/env bash
# Canonical lint runner for agent workflows.
# All agents MUST use this script instead of calling ruff directly, so that the
# rule set always comes from LINTING_STRICTNESS in .github/af-env.conf and the
# executable is always resolved from the project venv. A direct
# `ruff check --select=...` call also will not reproduce this gate's verdict:
# check-python-linting.py applies the project's own ruff `ignore` /
# `per-file-ignores` on top of the selected rules (see project_ignore= in its
# output), so a bare ruff invocation can show violations the gate does not
# have, or vice versa if the project ignore is broader than the selection
# implies (issue #124 finding 2).
#
# The hard gate in implementer-stop / refactorer-stop lints only *changed*
# files. This script is the repo-wide counterpart: it is what you run to find
# drift that accumulated before the gate existed, or after a bulk edit.
#
# -Scope changed reproduces the gate's own file set, so you can see what the
# gate will say before it says it.
#
# check-python-linting.py also runs `ruff format --check` over that same file
# set -- formatting is blocking at every strictness level, independent of
# rule selection and project_ignore (issue #124). --fix applies both.
#
# Usage:
#   .github/scripts/run-lint.sh                      # Lint SRC_DIR/ and tests/
#   .github/scripts/run-lint.sh --scope src          # Lint SRC_DIR/ only
#   .github/scripts/run-lint.sh --scope tests        # Lint tests/ only
#   .github/scripts/run-lint.sh --scope changed      # Lint the branch delta + working tree
#   .github/scripts/run-lint.sh --fix                # Apply ruff's safe fixes + ruff format
#   .github/scripts/run-lint.sh --strictness strict  # Override af-env.conf
#
# Exit codes (identical to check-python-linting.py):
#   0 = clean (lint and formatting)
#   1 = blocked (venv python or ruff missing, or bad configuration)
#   2 = lint violations found and/or formatting drift

set -uo pipefail

# Resolve workspace root (script is at .github/scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONF="${WORKSPACE_ROOT}/.github/af-env.conf"

SRC_DIR="src"
BASE_BRANCH=""
if [ -f "$CONF" ]; then
    _val=$(grep -E '^SRC_DIR=' "$CONF" | head -1 | cut -d= -f2-)
    [ -n "$_val" ] && SRC_DIR="$_val"
    _val=$(grep -E '^BASE_BRANCH=' "$CONF" | head -1 | cut -d= -f2- | tr -d '[:space:]')
    [ -n "$_val" ] && BASE_BRANCH="$_val"
fi

SCOPE="all"
STRICTNESS=""
FIX=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope)      SCOPE="$2"; shift 2 ;;
        --strictness) STRICTNESS="$2"; shift 2 ;;
        --fix)        FIX=true; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

case "$SCOPE" in
    all)     TARGETS=("$SRC_DIR" "tests") ;;
    src)     TARGETS=("$SRC_DIR") ;;
    tests)   TARGETS=("tests") ;;
    changed) TARGETS=() ;;
    *) echo "ERROR: invalid scope '$SCOPE'. Use: all|src|tests|changed"; exit 1 ;;
esac

# Resolve venv python (same contract as run-tests.sh)
PYTHON="$WORKSPACE_ROOT/.venv/bin/python"
if [[ ! -x "$PYTHON" ]]; then
    PYTHON="$WORKSPACE_ROOT/.venv/Scripts/python.exe"
fi
if [[ ! -x "$PYTHON" ]]; then
    echo "ERROR: venv python not found under $WORKSPACE_ROOT/.venv"
    exit 1
fi

cd "$WORKSPACE_ROOT"

# Linting scope is wider than the quality scope: ruff violations in tests/ are
# real violations, so both SRC_DIR and tests count.
is_lint_path() {
    case "$1" in
        "$SRC_DIR"/*|tests/*) return 0 ;;
        *) return 1 ;;
    esac
}

FILES=()
if [ "$SCOPE" = "changed" ]; then
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        # "cannot determine the changed set" is not the same as "nothing
        # changed"; reporting clean would silently weaken the gate this mirrors.
        echo "ERROR: --scope changed needs a git repository at $WORKSPACE_ROOT"
        echo "=== Exit Code: 1 ==="
        exit 1
    fi

    # Deliberately the same set implementer-stop and refactorer-stop gate on:
    # uncommitted work plus everything this branch already committed. Files from
    # an earlier phase are invisible to a working-tree diff but still ship.
    CHANGED=$(git diff --name-only --cached --diff-filter=AM -- '*.py' 2>/dev/null)
    [ -z "$CHANGED" ] && CHANGED=$(git diff --name-only HEAD --diff-filter=AM -- '*.py' 2>/dev/null)

    MERGE_BASE=""
    if [ -n "$BASE_BRANCH" ]; then
        MERGE_BASE=$(git merge-base HEAD "$BASE_BRANCH" 2>/dev/null | head -1)
        [ -z "$MERGE_BASE" ] && MERGE_BASE=$(git merge-base HEAD "origin/$BASE_BRANCH" 2>/dev/null | head -1)
    fi
    if [ -n "$MERGE_BASE" ]; then
        CHANGED="$CHANGED
$(git diff --name-only --diff-filter=AM "${MERGE_BASE}..HEAD" -- '*.py' 2>/dev/null)"
    fi

    while IFS= read -r f; do
        [ -n "$f" ] || continue
        is_lint_path "$f" || continue
        [ -f "$f" ] || continue
        FILES+=("$f")
    done < <(printf '%s\n' "$CHANGED" | sort -u)

    if [ -n "$BASE_BRANCH" ]; then
        TARGETS=("changed vs $BASE_BRANCH")
    else
        TARGETS=("changed (BASE_BRANCH unset -- working tree only)")
    fi
else
    for t in "${TARGETS[@]}"; do
        if [ -d "$t" ]; then
            while IFS= read -r f; do
                FILES+=("$f")
            done < <(find "$t" -type f -name '*.py')
        fi
    done
fi

echo "=== Lint Runner: scope=$SCOPE targets=${TARGETS[*]} files=${#FILES[@]} ==="

if [ "${#FILES[@]}" -eq 0 ]; then
    echo "(no Python files in scope)"
    echo "=== Exit Code: 0 ==="
    exit 0
fi

if [[ "$FIX" == true ]]; then
    # ruff has no fix mode behind check-python-linting.py, so the rule set is
    # mapped here. Source of truth for the GATE remains check-python-linting.py
    # -- this map only widens/narrows what gets auto-fixed, never what blocks.
    # Keep in sync when adding a level.
    LEVEL="$STRICTNESS"
    if [ -z "$LEVEL" ] && [ -f "$CONF" ]; then
        LEVEL=$(grep -E '^LINTING_STRICTNESS=' "$CONF" | head -1 | cut -d= -f2- | tr -d ' ')
    fi
    [ -z "$LEVEL" ] && LEVEL="standard"

    case "$LEVEL" in
        minimal)  RULES="F8" ;;
        standard) RULES="E,F,I" ;;
        strict)   RULES="E,F,I,B,UP,SIM,C90" ;;
        *)
            echo "ERROR: unknown LINTING_STRICTNESS '$LEVEL'. Valid: minimal, standard, strict"
            echo "=== Exit Code: 1 ==="
            exit 1
            ;;
    esac

    RUFF="$WORKSPACE_ROOT/.venv/bin/ruff"
    [[ ! -x "$RUFF" ]] && RUFF="$WORKSPACE_ROOT/.venv/Scripts/ruff.exe"
    if [[ ! -x "$RUFF" ]]; then
        RUFF="$(command -v ruff || true)"
    fi
    if [ -z "$RUFF" ]; then
        echo "ERROR: ruff not found in .venv or PATH. Install with: pip install ruff"
        echo "=== Exit Code: 1 ==="
        exit 1
    fi

    "$RUFF" check "--select=$RULES" --fix "${FILES[@]}"
    CHECK_EXIT=$?

    # Formatting is blocking regardless of strictness (issue #124), so --fix
    # must apply it too -- otherwise the remedy this gate names does not
    # actually clear the gate in one command.
    "$RUFF" format "${FILES[@]}"
    FORMAT_EXIT=$?

    # ruff exits 1 when violations remain after fixing -- map to the documented
    # contract (2 = violations). ruff format itself only fails (non-zero) on an
    # unparsable file, which is a violation too.
    if [ "$CHECK_EXIT" -eq 0 ] && [ "$FORMAT_EXIT" -eq 0 ]; then EXIT_CODE=0; else EXIT_CODE=2; fi
else
    LINT_SCRIPT=".github/scripts/check-python-linting.py"
    if [ ! -f "$LINT_SCRIPT" ]; then
        echo "ERROR: .github/scripts/check-python-linting.py not found"
        echo "=== Exit Code: 1 ==="
        exit 1
    fi
    if [ -n "$STRICTNESS" ]; then
        "$PYTHON" "$LINT_SCRIPT" --strictness "$STRICTNESS" --files "${FILES[@]}"
    else
        "$PYTHON" "$LINT_SCRIPT" --files "${FILES[@]}"
    fi
    EXIT_CODE=$?
fi

echo "=== Exit Code: $EXIT_CODE ==="
exit $EXIT_CODE
