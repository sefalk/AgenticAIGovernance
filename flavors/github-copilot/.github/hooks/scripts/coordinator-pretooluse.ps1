# copilot:generated | implementer | 2026-03-16
# copilot:modified  | implementer | 2026-03-17 | fixed false-positive deny on read-only tools
# Agent-scoped PreToolUse hook for the coordinator agent.
#
# DELEGATION ENFORCEMENT (HARD -- blocks coordinator from editing/creating files)
#
# The coordinator must delegate all file modifications to subagents.
# This hook blocks edit/create tool calls. Defence-in-depth with the
# coordinator PostToolUse detective check (git status after terminal commands).
#
# Fires only when the coordinator agent is active.
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

# Allow read-only and search tools unconditionally
$toolName = $inputData.tool_name
if ($toolName -match 'read|search|find|list|get|problems') {
    Write-Output '{}'
    exit 0
}

# Only inspect file-modifying tools
if ($toolName -notmatch 'edit|create|write|file') {
    Write-Output '{}'
    exit 0
}

# Allow createTerminal (not a file operation)
if ($toolName -match 'terminal|Terminal') {
    Write-Output '{}'
    exit 0
}

# Block: coordinator must not edit or create files directly
$reason = "Coordinator delegation violation: The coordinator must not modify files directly. " +
    "Select the appropriate workflow and delegate to the correct subagent: " +
    "test-writer (Red phase, test files), implementer (Green phase, production code), " +
    "refactorer (Refactor phase, structural cleanup), documenter (logs and docs), " +
    "planner (plan files). Review your Cardinal Rules and Workflow Selection."

@{
    hookSpecificOutput = @{
        hookEventName      = 'PreToolUse'
        permissionDecision = 'deny'
        permissionDecisionReason = $reason
    }
} | ConvertTo-Json -Depth 3 -Compress
exit 0
