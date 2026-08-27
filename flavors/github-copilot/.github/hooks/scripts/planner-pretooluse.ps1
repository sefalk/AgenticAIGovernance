# Agent-scoped PreToolUse hook for the planner agent.
#
# PLAN DIRECTORY CONFINEMENT (HARD -- blocks every write outside a plans/ dir)
#
# The planner produces the plan and, since issue #130, persists it, so the
# document reaches disk in one emission instead of three: the planner used to
# return the text, the coordinator repeated it verbatim into the documenter's
# prompt, and the documenter emitted it a third time as the `createFile`
# argument. Measured over 66 plans, the relayed document is a median 1,747
# tokens, so two of those three emissions were pure relay.
#
# That trade widens the write surface of an agent that was incapable of
# touching the repository, and the tool list alone is not what holds it: this
# gate is. It is an ALLOWLIST, not a denylist -- the test-writer's gate names
# the one place it may not write, which is the right shape when the agent may
# write nearly everywhere. Here the agent may write in exactly one kind of
# place, and anything a denylist forgot to name would be permitted.
#
# `plans` as a path segment is the same definition check-plan-budget.py uses,
# so a project that keeps plans somewhere other than docs/plans is not locked
# out of planning by a gate that hardcoded a path the budget guard does not.
#
# Fires only when the planner agent is active.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

$ErrorActionPreference = 'SilentlyContinue'

. "$PSScriptRoot/_common.ps1"

$raw = [Console]::In.ReadToEnd()
try {
    $inputData = $raw | ConvertFrom-Json
} catch {
    Write-Output '{}'
    exit 0
}

$toolName = $inputData.tool_name
if (-not (Test-AfWriteTool $toolName)) {
    Write-Output '{}'
    exit 0
}

$filePaths = @(Get-AfWritePaths $inputData.tool_input)

# A write tool whose payload names no path is not a write this gate can clear.
# Failing open here would let an unrecognised payload shape carry the very
# edit the gate exists to prevent -- the #64 defect, where a one-level-down
# path made a URL gate inert.
if ($filePaths.Count -eq 0) {
    @{
        hookSpecificOutput = @{
            hookEventName      = 'PreToolUse'
            permissionDecision = 'deny'
            permissionDecisionReason = "Plan directory confinement: planner called the write tool '$toolName' with no readable file path, so the target cannot be checked against the plan directory. The planner may only create the plan document."
        }
    } | ConvertTo-Json -Depth 3 -Compress
    exit 0
}

function Test-AfPlanPath {
    param([string]$Path, [string]$Root)

    # `Join-Path` concatenates unconditionally, so an absolute path -- the only
    # kind the planner's write tool accepts -- became `C:\repo\C:\repo\...`, and
    # the gate denied it as malformed instead of judging where it points (#232).
    # The bash twin already branched here; this puts the two back in step.
    try {
        $full = if ([System.IO.Path]::IsPathRooted($Path)) {
            [System.IO.Path]::GetFullPath($Path)
        } else {
            [System.IO.Path]::GetFullPath((Join-Path $Root $Path))
        }
    } catch {
        return $false
    }

    # `..` climbing out of the repository resolves to a real path with a real
    # `plans` segment somewhere above it, so containment is checked first.
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    if (-not $full.StartsWith($rootFull + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    $relative = $full.Substring($rootFull.Length + 1) -replace '\\', '/'
    $parts = $relative.Split('/')
    if ($parts.Count -lt 2) { return $false }

    $leaf = $parts[-1]
    if (-not $leaf.ToLowerInvariant().EndsWith('.md')) { return $false }

    $dirs = $parts[0..($parts.Count - 2)]
    return ($dirs -contains 'plans')
}

foreach ($filePath in $filePaths) {
    if (Test-AfPlanPath -Path $filePath -Root $script:AfCodeRoot) { continue }

    @{
        hookSpecificOutput = @{
            hookEventName      = 'PreToolUse'
            permissionDecision = 'deny'
            permissionDecisionReason = "Plan directory confinement: planner cannot write to '$filePath'. The planner may create only the plan document -- a .md file inside a 'plans' directory within the repository (default docs/plans/). Everything else in this workflow is written by the test-writer, implementer, refactorer or documenter."
        }
    } | ConvertTo-Json -Depth 3 -Compress
    exit 0
}

Write-Output '{}'
