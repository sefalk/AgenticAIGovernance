#!/usr/bin/env bash
# SessionStart hook: Injects git and environment context into the agent session.
# Input:  JSON via stdin (common fields + source)
# Output: JSON with additionalContext

# Root and interpreter come from this script's location, never from the cwd
# the agent happens to run in (issue #54).
. "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# The session id keys the foreign-work baseline (#120).
stdin_raw=$(cat)
session_id=""
if [ -n "$AF_PYTHON" ]; then
    session_id=$(printf '%s' "$stdin_raw" | "$AF_PYTHON" -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)
fi

# Gather context
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
commit=$(git log -1 --format='%h %s' 2>/dev/null || echo "unknown")
if [ -n "$AF_PYTHON" ]; then
    py_ver=$("$AF_PYTHON" --version 2>/dev/null || echo "unknown")
else
    py_ver="unknown"
fi
project=$(basename "$AF_CODE_ROOT" 2>/dev/null || echo "unknown")

# Test log summary -- pure bash
test_log_summary=""
test_log_path="$AF_MAIN_ROOT/.github/test-log.json"
if [[ -f "$test_log_path" ]]; then
    _now_epoch=$(date +%s)
    _flat=$(tr -d '\n\r' < "$test_log_path" | tr -s ' ')
    _parts=""
    for _scope in domain adapters properties contracts all; do
        _block=$(echo "$_flat" | sed -n "s/.*\"${_scope}\" *: *\({[^}]*}\).*/\1/p")
        if [[ -n "$_block" ]]; then
            _passed=$(echo "$_block" | sed -n 's/.*"passed" *: *\([0-9][0-9]*\).*/\1/p')
            _total=$(echo "$_block" | sed -n 's/.*"total" *: *\([0-9][0-9]*\).*/\1/p')
            _ec=$(echo "$_block" | sed -n 's/.*"exit_code" *: *\([0-9][0-9]*\).*/\1/p')
            _lr=$(echo "$_block" | sed -n 's/.*"last_run" *: *"\([^"]*\)".*/\1/p')
            _age="?"
            if [[ -n "$_lr" ]]; then
                _lr_epoch=$(date -d "$_lr" +%s 2>/dev/null || echo "")
                if [[ -n "$_lr_epoch" ]]; then
                    _mins=$(( (_now_epoch - _lr_epoch) / 60 ))
                    if [[ $_mins -lt 60 ]]; then
                        _age="${_mins}m ago"
                    else
                        _age="$(( _mins / 60 ))h ago"
                    fi
                fi
            fi
            _status="FAIL"
            [[ "${_ec:-1}" == "0" ]] && _status="PASS"
            _entry="${_scope}=${_passed:-0}/${_total:-0}(${_status},${_age})"
            _parts="${_parts:+${_parts}, }${_entry}"
        fi
    done
    if [[ -n "$_parts" ]]; then
        test_log_summary=" | Tests: ${_parts}"
    fi
fi

# Without an interpreter most gates degrade quietly, per call; say which, once (#342).
# Derived from the hooks themselves, so a new Python-backed hook is named without a list to maintain.
python_notice=""
if [ -z "$AF_PYTHON" ]; then
    _hook_dir=$(dirname -- "${BASH_SOURCE[0]}")
    _helpers=$(awk '
        /^[a-z_]+\(\) *\{/ { name = $1; sub(/\(\).*/, "", name); body = ""; infn = 1; next }
        infn && /^\}/ {
            if (body ~ /AF_PYTHON/ && name != "af_require_python" && name != "af_deny_no_python") print name
            infn = 0; next
        }
        infn { body = body "\n" $0 }
    ' "$_hook_dir/_common.sh")
    _refused=""
    _degraded=""
    for _f in "$_hook_dir"/*.sh; do
        _n=$(basename "$_f" .sh)
        case "$_n" in _*|session-context) continue ;; esac
        if grep -qw 'af_require_python' "$_f"; then
            _refused="${_refused:+$_refused, }$_n"
            continue
        fi
        _dep=""
        grep -q 'AF_PYTHON' "$_f" && _dep=1
        for _h in $_helpers; do grep -qw "$_h" "$_f" && _dep=1; done
        [ -n "$_dep" ] && _degraded="${_degraded:+$_degraded, }$_n"
    done
    python_notice=" | AF WARNING: no working Python interpreter (tried AF_PYTHON_OVERRIDE, python3, python, py). Running without their Python-backed check: ${_degraded:-none}. Refusing every call they guard: ${_refused:-none}. Install Python 3 or set AF_PYTHON_OVERRIDE (#342)."
fi

# Paths dirty now were authored by no agent of this session; block-dangerous asks before discarding them (#120).
foreign_notice=""
fg_core="$(dirname -- "${BASH_SOURCE[0]}")/_foreign_guard.py"
if [ -n "$AF_PYTHON" ] && [ -n "$AF_CODE_ROOT" ] && [ -f "$fg_core" ]; then
    _fg=$(AF_FG_SESSION="$session_id" "$AF_PYTHON" "$fg_core" record "$AF_CODE_ROOT" 2>/dev/null)
    [ -n "$_fg" ] && foreign_notice=" | ${_fg}"
fi

context="Project: ${project} | Branch: ${branch} | Last commit: ${commit} | ${py_ver}${test_log_summary}${python_notice}${foreign_notice}"

# Return JSON — escape double quotes in context for safety
context_escaped=$(echo "$context" | af_json_escape)
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$context_escaped"
