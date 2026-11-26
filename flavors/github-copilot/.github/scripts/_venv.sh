# shellcheck shell=bash
# Shared venv resolution for the runners (#579). Source, then:
#
#   af_resolve_venv "$WORKSPACE_ROOT" || exit 1
#   af_enable_venv
#
# Sets AF_VENV_PYTHON, AF_VENV_BIN, AF_VENV_ROOT, AF_VENV_SOURCE,
# AF_VENV_TOPLEVEL, AF_VENV_MODE. Search order, first hit wins:
#   workspace  <workspaceRoot>/.venv
#   toplevel   <git toplevel>/.venv     -- the payload sits below the repo root
#   shared     <main checkout>/.venv    -- a worktree, only when
#                                          WORKTREE_VENV_MODE=shared (default)
# Nothing found is BLOCKED: creating a venv installs packages, which is a step
# a human approves (setup-worktree / bootstrap-python-env), never a runner.
# _venv.ps1 is the PowerShell twin of this file; keep both in step.

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

af_resolve_venv() {
    local ws conf val top common main dir src searched="" py
    ws="$(_af_venv_abs "$1")" || ws="$1"
    AF_VENV_PYTHON="" AF_VENV_BIN="" AF_VENV_ROOT="" AF_VENV_SOURCE=""
    AF_VENV_TOPLEVEL="$ws" AF_VENV_MODE="shared"

    conf="$ws/.github/af-env.conf"
    if [[ -f "$conf" ]]; then
        val="$(grep -E '^WORKTREE_VENV_MODE=' "$conf" | head -1 | cut -d= -f2- | tr -d "[:space:]\"'")"
        [[ -n "$val" ]] && AF_VENV_MODE="$val"
    fi

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
    echo "BLOCKED: no usable venv for this checkout. Creating one installs packages, so a human runs it:"
    echo "  worktree:       .github/scripts/setup-worktree.sh (isolated mode creates the worktree venv)"
    echo "  plain checkout: .github/scripts/bootstrap-python-env.sh"
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
    echo "  Set WORKTREE_VENV_MODE=isolated in .github/af-env.conf and have a human run .github/scripts/setup-worktree.sh."
    return 1
}
