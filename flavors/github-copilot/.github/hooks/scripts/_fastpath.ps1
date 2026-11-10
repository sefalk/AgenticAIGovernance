# Fast path for the guard hooks (issue #515).
#
# DOT-SOURCE before _common.ps1, which probes for Python on load. Six parallel
# MCP reads took the guards to 13-57 s and a quarter of them timed out, which
# fails open. A call no guard acts on now exits before that cost.
#
# The pattern is a SUPERSET of every class the guards act on: terminal, task,
# code-execution surfaces, work-item/body writes, file writes. Matching more
# than needed only costs latency; an unmatched guarded tool would skip a gate,
# so test-hooks.* assert the superset and the identity with _fastpath.sh.

$afGuardedTools = 'terminal|task|update|create|write|edit|insert|apply|replace|runcodesnippet|notebook_?cell|playwright|browser_|vs_?code_?command'
# Calls the body guard records (#376): its READ_SUFFIXES plus comment declarations.
$afGuardReads = '(issue_read|pull_request_read|list_issues|search_issues|list_pull_requests|search_pull_requests|add_issue_comment)$'

function Read-AfStdinRaw {
    $ms = New-Object System.IO.MemoryStream
    [Console]::OpenStandardInput().CopyTo($ms)
    return (New-Object System.Text.UTF8Encoding $false).GetString($ms.ToArray()).TrimStart([char]0xFEFF)
}

# The payload's tool_name when it appears exactly once, else ''. A second
# occurrence (nested JSON) is ambiguous and takes the full path.
function Get-AfFastToolName {
    param([string]$Raw)
    $m = [regex]::Matches($Raw, '"tool_name"\s*:\s*"([A-Za-z0-9_.-]+)"')
    if ($m.Count -ne 1) { return '' }
    return $m[0].Groups[1].Value
}

# -match is case-insensitive, as the superset must be.
function Test-AfUnguardedTool {
    param([string]$Name)
    return [bool]($Name -and $Name -notmatch $afGuardedTools)
}

# scan-secrets has nothing to do for a small result of an unguarded call, unless
# a write guard records it (#197, #376) or it is a returning subagent (#515).
# Under 4096 chars no result reaches the long-line spill threshold (#341).
function Test-AfScanSkippable {
    param([string]$Raw)
    $tool = Get-AfFastToolName $Raw
    if (-not (Test-AfUnguardedTool $tool) -or $Raw.Length -ge 4096) { return $false }
    if ($tool -match $afGuardReads -or $tool -eq 'runSubagent') { return $false }
    return -not ($tool -match 'wit_work_item$' -and $Raw -match '"action"\s*:\s*"(get|get_batch)"')
}
