#!/usr/bin/env bash
# Canonical lint runner for agent workflows.
# All agents MUST use this script instead of calling ruff directly, so that the
# rule set always comes from LINTING_STRICTNESS in .github/af-env.conf and the
# executable is always resolved from the project venv.
#
# The hard gate in implementer-stop / refactorer-stop lints only *changed*
# files. This script is the repo-wide counterpart: it is what you run to find
# drift that accumulated before the gate existed, or after a bulk edit.
#
# Usage:
#   .github/scripts/run-lint.sh                      # Lint SRC_DIR/ and tests/
#   .github/scripts/run-lint.sh --scope src          # Lint SRC_DIR/ only
#   .github/scripts/run-lint.sh --scope tests        # Lint tests/ only
#   .github/scripts/run-lint.sh --fix                # Apply ruff's safe fixes
#   .github/scripts/run-lint.sh --strictness strict  # Override af-env.conf
#
# Exit codes (identical to check-python-linting.py):
#   0 = clean
#   1 = blocked (venv python or ruff missing, or bad configuration)
#   2 = lint violations found

set -uo pipefail

# Resolve workspace root (script is at .github/scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONF="${WORKSPACE_ROOT}/.github/af-env.conf"

SRC_DIR="src"
if [ -f "$CONF" ]; then
    _val=$(grep -E '^SRC_DIR=' "$CONF" | head -1 | cut -d= -f2-)
    [ -n "$_val" ] && SRC_DIR="$_val"
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
    all)   TARGETS=("$SRC_DIR" "tests") ;;
    src)   TARGETS=("$SRC_DIR") ;;
    tests) TARGETS=("tests") ;;
    *) echo "ERROR: invalid scope '$SCOPE'. Use: all|src|tests"; exit 1 ;;
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

FILES=()
for t in "${TARGETS[@]}"; do
    if [ -d "$t" ]; then
        while IFS= read -r f; do
            FILES+=("$f")
        done < <(find "$t" -type f -name '*.py')
    fi
done

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
    RUFF_EXIT=$?
    # ruff exits 1 when violations remain after fixing -- map to the documented
    # contract (2 = violations).
    if [ "$RUFF_EXIT" -eq 0 ]; then EXIT_CODE=0; else EXIT_CODE=2; fi
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
