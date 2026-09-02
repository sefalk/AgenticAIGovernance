#!/usr/bin/env bash
# SessionStart hook: Injects git and environment context into the agent session.
# Input:  JSON via stdin (common fields + source)
# Output: JSON with additionalContext

# Root and interpreter come from this script's location, never from the cwd
# the agent happens to run in (issue #54).
. "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# Consume stdin (required even if unused)
cat > /dev/null

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

context="Project: ${project} | Branch: ${branch} | Last commit: ${commit} | ${py_ver}${test_log_summary}"

# Return JSON — escape double quotes in context for safety
context_escaped=$(echo "$context" | af_json_escape)
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$context_escaped"
