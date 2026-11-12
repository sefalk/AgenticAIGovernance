#!/usr/bin/env bash
# Fast path for the guard hooks (issue #515).
#
# SOURCE before _common.sh, which probes for Python on load. Six parallel MCP
# reads took the guards to 13-57 s and a quarter of them timed out, which fails
# open. A call no guard acts on now exits before that cost.
#
# The pattern is a SUPERSET of every class the guards act on: terminal, task,
# code-execution surfaces, work-item/body writes, file writes. Matching more
# than needed only costs latency; an unmatched guarded tool would skip a gate,
# so test-hooks.* assert the superset and the identity with _fastpath.ps1.

AF_GUARDED_TOOLS='terminal|bash|powershell|task|update|create|write|edit|insert|apply|replace|runcodesnippet|notebook_?cell|playwright|browser_|vs_?code_?command'
# Calls the body guard records (#376): its READ_SUFFIXES plus comment declarations.
AF_GUARD_READS='(issue_read|pull_request_read|list_issues|search_issues|list_pull_requests|search_pull_requests|add_issue_comment)$'

# af_fast_tool_name RAW -- the payload's tool_name when it appears exactly
# once, else nothing. A second occurrence (nested JSON) takes the full path.
af_fast_tool_name() {
    local _ft_raw="$1" _ft_re='"tool_name"[[:space:]]*:[[:space:]]*"([A-Za-z0-9_.-]+)"' _ft_name
    [[ $_ft_raw =~ $_ft_re ]] || return 1
    _ft_name=${BASH_REMATCH[1]}
    _ft_raw=${_ft_raw/"${BASH_REMATCH[0]}"/}
    [[ $_ft_raw =~ $_ft_re ]] && return 1
    printf '%s' "$_ft_name"
}

# Lowercased with tr, not ${1,,}: bash 3.2 on macOS has no case conversion.
af_unguarded_tool() {
    local _ug_name
    [ -n "${1:-}" ] || return 1
    _ug_name=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    ! [[ $_ug_name =~ $AF_GUARDED_TOOLS ]]
}

# af_scan_skippable RAW -- scan-secrets has nothing to do for a small result of
# an unguarded call, unless a write guard records it (#197, #376) or it is a
# returning subagent (#515). Under 4096 chars no result reaches the spill (#341).
af_scan_skippable() {
    local _ss_raw="$1" _ss_tool
    _ss_tool=$(af_fast_tool_name "$_ss_raw") || return 1
    af_unguarded_tool "$_ss_tool" && [ "${#_ss_raw}" -lt 4096 ] || return 1
    [[ $_ss_tool =~ $AF_GUARD_READS ]] && return 1
    [ "$_ss_tool" = runSubagent ] && return 1
    if [[ $_ss_tool == *wit_work_item ]] && [[ $_ss_raw =~ \"action\"[[:space:]]*:[[:space:]]*\"(get|get_batch)\" ]]; then
        return 1
    fi
    return 0
}
