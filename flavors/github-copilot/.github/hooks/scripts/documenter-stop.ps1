# Agent-scoped Stop hook for the documenter agent.
#
# DOCUMENTATION ARTIFACT GATE (HARD -- blocks documenter if required artifacts missing)
#
# Verifies the documenter has produced the required workflow artifacts:
#   1. YAML workflow log in .github/logs/{workflow-id}.yaml
#   2. Retro snippet in retros/auto/{workflow-id}.md or .github/retros/auto/
#
# Fires as SubagentStop when the documenter is invoked by the coordinator.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot/hook-utils.ps1"

# Read stdin (hook input JSON -- required by protocol)
$null = [Console]::In.ReadToEnd()
Write-HookTrace -Hook 'documenter-stop' -Event 'invoked'

# Derive workflow-id from current branch
$branch = & git branch --show-current 2>$null
if (-not $branch -or $branch -notmatch '^agent/(.+)$') {
    # Not on an agent branch -- skip artifact checks
    $output = @{
        systemMessage = "documenter:Stop -- not on agent/ branch, artifact gate skipped"
    } | ConvertTo-Json -Compress
    Write-Output $output
    exit 0
}

$workflowId = $Matches[1]
$missing = @()

# ---------- Gate 1: Workflow log YAML ----------

$logPath1 = ".github/logs/$workflowId.yaml"
$logPath2 = ".github/logs/$workflowId.yml"
if (-not (Test-Path $logPath1) -and -not (Test-Path $logPath2)) {
    $missing += "workflow log (.github/logs/$workflowId.yaml)"
}

# ---------- Gate 2: Retro snippet ----------

$retroPath1 = "retros/auto/$workflowId.md"
$retroPath2 = ".github/retros/auto/$workflowId.md"
if (-not (Test-Path $retroPath1) -and -not (Test-Path $retroPath2)) {
    $missing += "retro snippet (retros/auto/$workflowId.md)"
}

# ---------- Verdict ----------

if ($missing.Count -gt 0) {
    Write-HookTrace -Hook 'documenter-stop' -Event 'block' -Detail ($missing -join '; ')
    $list = $missing -join '; '
    $output = @{
        hookSpecificOutput = @{
            hookEventName = "Stop"
            decision = "block"
            reason = "Documentation phase violation: required artifacts missing for workflow '$workflowId': $list. Create these files before completing."
        }
    } | ConvertTo-Json -Compress -Depth 3
    Write-Output $output
    exit 0
}

$output = @{
    systemMessage = "documenter:Stop -- artifact gate PASS: workflow log and retro snippet exist for '$workflowId'"
} | ConvertTo-Json -Compress
Write-Output $output
exit 0
