# shellcheck shell=bash
# Shared venv resolution for the runners (#579). Source, then:
#
#   af_resolve_venv "$WORKSPACE_ROOT" bootstrap || exit 1
#   af_enable_venv
#
# Sets AF_VENV_PYTHON, AF_VENV_BIN, AF_VENV_ROOT, AF_VENV_SOURCE,
# AF_VENV_TOPLEVEL, AF_VENV_MODE. Search order, first hit wins:
#   workspace  <workspaceRoot>/.venv
#   toplevel   <git toplevel>/.venv     -- the payload sits below the repo root
#   shared     <main checkout>/.venv    -- a worktree, only when
#                                          WORKTREE_VENV_MODE=shared (default)
# Nothing found: with "bootstrap" and PY_ENV_BOOTSTRAP=always (default) the
# caller runs bootstrap-python-env, which creates <workspaceRoot>/.venv, and
# resolves again -- an agent must not wait on a human for a venv (#579).
# ask/off, or a failed bootstrap, is BLOCKED and names the script to run.
# Hooks resolve without "bootstrap": a pip install cannot finish in a hook's
# timeout. _venv.ps1 is the PowerShell twin of this file; keep both in step.

_af_venv_python_in() {
    local rel
    for rel in .venv/bin/python .venv/Scripts/python.exe; do
        if [[ -x "$1/$rel" ]]; then
            printf '%s\n' "$1/$rel"
            return 0
        fi
    done
    return 1
}

# Physical path in this shell's own notation: git on Windows prints C:/...,
# pwd in Git Bash prints /c/..., and only the shell can make them comparable.
_af_venv_abs() {
    (cd "$1" 2>/dev/null && pwd -P)
}

_af_venv_conf() {
    local val=""
    [[ -f "$1" ]] && val="$(grep -E "^$2=" "$1" | head -1 | cut -d= -f2- | tr -d "[:space:]\"'")"
    printf '%s\n' "${val:-$3}"
}

af_resolve_venv() {
    local ws conf top common main dir src searched="" py policy script why code
    ws="$(_af_venv_abs "$1")" || ws="$1"
    AF_VENV_PYTHON="" AF_VENV_BIN="" AF_VENV_ROOT="" AF_VENV_SOURCE=""
    AF_VENV_TOPLEVEL="$ws"

    conf="$ws/.github/af-env.conf"
    AF_VENV_MODE="$(_af_venv_conf "$conf" WORKTREE_VENV_MODE shared)"

    local -a dirs=("$ws") sources=("workspace")
    if command -v git >/dev/null 2>&1 && top="$(git -C "$ws" rev-parse --show-toplevel 2>/dev/null)" && [[ -n "$top" ]]; then
        top="$(_af_venv_abs "$top")" || top=""
        if [[ -n "$top" ]]; then
            AF_VENV_TOPLEVEL="$top"
            if [[ "$top" != "$ws" ]]; then
                dirs+=("$top"); sources+=("toplevel")
            fi
        fi
        if [[ "$AF_VENV_MODE" == "shared" ]]; then
            common="$(git -C "$ws" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
                || common="$(cd "$ws" && git rev-parse --git-common-dir 2>/dev/null)"
            [[ -n "$common" && "$common" != /* && "$common" != ?:* ]] && common="$ws/$common"
            # Only a non-bare repository's .git has a checkout as its parent;
            # a submodule's common dir (.git/modules/x) does not.
            if [[ -n "$common" && "$(basename "$common")" == ".git" ]]; then
                main="$(_af_venv_abs "$common/..")"
                if [[ -n "$main" && "$main" != "$ws" && "$main" != "$AF_VENV_TOPLEVEL" ]]; then
                    dirs+=("$main"); sources+=("shared")
                fi
            fi
        fi
    fi

    local i
    for i in "${!dirs[@]}"; do
        dir="${dirs[$i]}"
        src="${sources[$i]}"
        if py="$(_af_venv_python_in "$dir")"; then
            AF_VENV_PYTHON="$py"
            AF_VENV_BIN="$(dirname "$py")"
            AF_VENV_ROOT="$dir"
            AF_VENV_SOURCE="$src"
            return 0
        fi
        searched="${searched:+$searched, }$dir/.venv"
    done

    echo "ERROR: venv python not found under $ws/.venv (searched: $searched; WORKTREE_VENV_MODE=$AF_VENV_MODE)"
    policy="$(_af_venv_conf "$conf" PY_ENV_BOOTSTRAP always | tr '[:upper:]' '[:lower:]')"
    script="$ws/.github/scripts/bootstrap-python-env.sh"
    if [[ "${2:-}" == "bootstrap" && "$policy" == "always" && -f "$script" ]]; then
        echo "NOTE: PY_ENV_BOOTSTRAP=always -- creating the venv with .github/scripts/bootstrap-python-env.sh"
        if bash "$script" 2>&1; then code=0; else code=$?; fi
        if [[ $code -eq 0 ]] && af_resolve_venv "$ws" >/dev/null; then
            return 0
        fi
        echo "BLOCKED: venv bootstrap failed (bootstrap-python-env.sh exit $code); its output is above."
        echo "  Fix the cause and run .github/scripts/bootstrap-python-env.sh (task 'env: bootstrap python')."
        return 1
    fi
    if [[ "${2:-}" != "bootstrap" ]]; then
        why="this caller does not create venvs"
    elif [[ "$policy" != "always" ]]; then
        why="PY_ENV_BOOTSTRAP=$policy does not let a runner create one"
    else
        why="bootstrap-python-env.sh is not deployed"
    fi
    echo "BLOCKED: no usable venv for this checkout, and $why. Create it with:"
    echo "  .github/scripts/bootstrap-python-env.sh (task 'env: bootstrap python')"
    echo "  worktree in isolated mode: .github/scripts/setup-worktree.sh"
    echo "  or set PY_ENV_BOOTSTRAP=always in .github/af-env.conf so the runners create it."
    return 1
}

# Puts the venv's bin first on PATH, so tools the runner spawns (ruff via
# check-python-linting.py, pytest plugins) come from the same venv as the
# interpreter, and says where the venv came from when it is not the workspace's.
af_enable_venv() {
    export PATH="$AF_VENV_BIN:$PATH"
    if [[ "$AF_VENV_SOURCE" != "workspace" ]]; then
        echo "NOTE: venv: $AF_VENV_SOURCE -> $AF_VENV_ROOT"
    fi
}

# A shared venv is the main checkout's. If the main checkout is installed
# into it editable, pytest in this worktree imports the main checkout's code
# and reports on code nobody changed. Returns 1 (after printing why) if so.
af_check_venv_isolation() {
    local script_dir="$1" found
    [[ "$AF_VENV_SOURCE" == "shared" ]] || return 0
    if found="$("$AF_VENV_PYTHON" "$script_dir/check-venv-editable.py" \
            --foreign-root "$AF_VENV_ROOT" --workspace "$AF_VENV_TOPLEVEL" 2>&1)"; then
        return 0
    fi
    printf '%s\n' "$found"
    echo "BLOCKED: the shared venv at $AF_VENV_ROOT imports code from the main checkout, not this worktree."
    echo "  Set WORKTREE_VENV_MODE=isolated in .github/af-env.conf and run .github/scripts/setup-worktree.sh to create the worktree venv."
    return 1
}

# ruff formats differently between releases, so a local ruff that is not the
# one CI pins passes `ruff format --check` here and fails it there. Reads the
# ruff==X pin from DEP_DEV_FILE (workspace, then git toplevel) and prints a
# warning when the venv's ruff differs. Never blocks: a project without a pin,
# or a venv without ruff, has nothing to compare. Call after af_resolve_venv.
af_ruff_pin_warning() {
    local ws dep dir pin="" have
    ws="$(_af_venv_abs "$1")" || ws="$1"
    dep="$(_af_venv_conf "$ws/.github/af-env.conf" DEP_DEV_FILE requirements-dev.txt)"
    for dir in "$ws" "$AF_VENV_TOPLEVEL"; do
        [[ -f "$dir/$dep" ]] || continue
        pin="$(grep -iE "^[[:space:]]*[\"']?ruff[[:space:]]*==" "$dir/$dep" | head -1 \
            | sed -E "s/^[^=]*==[[:space:]]*([0-9][0-9A-Za-z.+!-]*).*/\1/" | tr -d '\r')"
        [[ -n "$pin" ]] && break
    done
    [[ -n "$pin" ]] || return 0
    have="$("$AF_VENV_PYTHON" -m ruff --version 2>/dev/null | tr -d '\r' | awk '{print $NF}')" || return 0
    [[ -n "$have" && "$have" != "$pin" ]] || return 0
    echo "WARN: venv ruff $have differs from the ruff==$pin pin in $dep; formatting may pass here and fail in CI. Re-run .github/scripts/bootstrap-python-env.sh to install the pinned version."
}