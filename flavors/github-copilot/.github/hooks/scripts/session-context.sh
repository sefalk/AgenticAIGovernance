#!/usr/bin/env bash
# SessionStart hook: Injects git and environment context into the agent session.
# copilot:modified | implementer | 2026-03-19 | added test log summary
# Input:  JSON via stdin (common fields + source)
# Output: JSON with additionalContext

# Consume stdin (required even if unused)
cat > /dev/null

# Gather context
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
commit=$(git log -1 --format='%h %s' 2>/dev/null || echo "unknown")
py_ver=$(python3 --version 2>/dev/null || python --version 2>/dev/null || echo "unknown")
project=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "unknown")

# Test log summary — pure bash
test_log_summary=""
repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
test_log_path="$repo_root/.github/test-log.json"
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
context_escaped=$(echo "$context" | sed 's/"/\\"/g')
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$context_escaped"
