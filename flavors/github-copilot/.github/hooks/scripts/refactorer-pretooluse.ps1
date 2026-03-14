# Agent-scoped PreToolUse hook for the refactorer agent.
#
# NO NEW FILES GATE (HARD -- blocks refactorer from creating files/directories)
#
# Refactoring must only modify existing files. This preventative hook fires
# before createFile/createDirectory calls. Defence-in-depth with the
# refactorer:Stop detective check (git status for untracked files).
#
# Fires only when the refactorer agent is active.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

$ErrorActionPreference = 'SilentlyContinue'

# Read and parse stdin
$raw = [Console]::In.ReadToEnd()
try {
    $inputData = $raw | ConvertFrom-Json
} catch {
    Write-Output '{}'
    exit 0
}

# Only inspect file/directory creation tools
$toolName = $inputData.tool_name
if ($toolName -notmatch 'create|Create') {
    Write-Output '{}'
    exit 0
}

# Block createFile and createDirectory (but allow createTerminal etc.)
if ($toolName -match 'file|File|directory|Directory') {
    @{
        hookSpecificOutput = @{
            hookEventName      = 'PreToolUse'
            permissionDecision = 'deny'
            permissionDecisionReason = "Refactor phase prohibits creating new files or directories. Refactoring must only modify existing files. Use the implementer phase for new file creation."
        }
    } | ConvertTo-Json -Depth 3 -Compress
    exit 0
}

# Not a file creation tool -- allow
Write-Output '{}'
