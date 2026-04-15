#!/usr/bin/env bash
# copilot:generated | implementer | 2026-04-14
# Bootstrap Python environment for AF workflows.
#
# Usage:
#   .github/scripts/bootstrap-python-env.sh
#   .github/scripts/bootstrap-python-env.sh --skip-deps
#
# Exit codes:
#   0 = environment ready
#   1 = python executable not found
#   2 = venv creation failed
#   3 = dependency install failed

set -euo pipefail

SKIP_DEPS=false
if [[ "${1:-}" == "--skip-deps" ]]; then
    SKIP_DEPS=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VENV_PY="$WORKSPACE_ROOT/.venv/bin/python"
VENV_PIP="$WORKSPACE_ROOT/.venv/bin/pip"
CONF_PATH="$WORKSPACE_ROOT/.github/af-env.conf"

echo "=== Bootstrap Python Environment ==="
echo "Workspace: $WORKSPACE_ROOT"

resolve_python() {
    if command -v python3 >/dev/null 2>&1; then
        echo "python3"
        return
    fi
    if command -v python >/dev/null 2>&1; then
        echo "python"
        return
    fi
    echo ""
}

# 1) Create venv if missing
if [[ ! -x "$VENV_PY" ]]; then
    PY_CMD="$(resolve_python)"
    if [[ -z "$PY_CMD" ]]; then
        echo "ERROR: No Python executable found (python3/python)."
        exit 1
    fi

    echo "Creating .venv ..."
    cd "$WORKSPACE_ROOT"
    "$PY_CMD" -m venv .venv || { echo "ERROR: Failed to create .venv."; exit 2; }
    [[ -x "$VENV_PY" ]] || { echo "ERROR: .venv created but python missing."; exit 2; }
fi

[[ -x "$VENV_PIP" ]] || { echo "ERROR: pip not found at $VENV_PIP"; exit 2; }

# 2) Upgrade base tooling
echo "Upgrading pip/setuptools/wheel ..."
"$VENV_PY" -m pip install --upgrade pip setuptools wheel || {
    echo "ERROR: Failed to upgrade base packaging tools."
    exit 3
}

if [[ "$SKIP_DEPS" == true ]]; then
    echo "Dependency installation skipped (--skip-deps)."
    echo "Environment ready."
    exit 0
fi

# 3) Install deps from af-env.conf
DEP_FILE=""
DEP_DEV_FILE=""
if [[ -f "$CONF_PATH" ]]; then
    DEP_FILE="$(grep -E '^DEP_FILE=' "$CONF_PATH" | head -1 | cut -d= -f2- | xargs || true)"
    DEP_DEV_FILE="$(grep -E '^DEP_DEV_FILE=' "$CONF_PATH" | head -1 | cut -d= -f2- | xargs || true)"
fi

declare -a dep_targets=()
[[ -n "$DEP_FILE" ]] && dep_targets+=("$DEP_FILE")
if [[ -n "$DEP_DEV_FILE" && "$DEP_DEV_FILE" != "$DEP_FILE" ]]; then
    dep_targets+=("$DEP_DEV_FILE")
fi

cd "$WORKSPACE_ROOT"
for dep in "${dep_targets[@]:-}"; do
    dep_path="$WORKSPACE_ROOT/$dep"
    if [[ ! -f "$dep_path" ]]; then
        echo "WARN: Dependency file not found, skipping: $dep"
        continue
    fi

    if [[ "$dep" == *.txt ]]; then
        echo "Installing deps from $dep ..."
        "$VENV_PIP" install -r "$dep_path" || {
            echo "ERROR: Dependency installation failed for $dep"
            exit 3
        }
    else
        echo "Installing package editable from $dep ..."
        "$VENV_PIP" install -e . || {
            echo "ERROR: Editable install failed for $dep"
            exit 3
        }
    fi
done

# 4) Register nbstripout git filter if NOTEBOOKS_ENABLED=true
NOTEBOOKS_ENABLED=false
if [[ -f "$CONF_PATH" ]] && grep -qE '^NOTEBOOKS_ENABLED=true$' "$CONF_PATH"; then
    NOTEBOOKS_ENABLED=true
fi

if [[ "$NOTEBOOKS_ENABLED" == true ]]; then
    echo "Registering nbstripout git filter (NOTEBOOKS_ENABLED=true) ..."
    cd "$WORKSPACE_ROOT"
    if "$VENV_PY" -m nbstripout --install; then
        echo "nbstripout git filter registered."
    else
        echo "WARN: nbstripout --install failed. Ensure nbstripout is in requirements-dev.txt."
    fi

    GA_PATH="$WORKSPACE_ROOT/.gitattributes"
    if [[ ! -f "$GA_PATH" ]] || ! grep -q 'filter=nbstripout' "$GA_PATH"; then
        echo "WARN: .gitattributes is missing or has no nbstripout filter entry."
        echo "  Add to .gitattributes: *.ipynb filter=nbstripout"
        echo "  Reference: .github/templates/gitattributes-notebooks.txt"
    fi
fi

echo "Environment ready."
exit 0
