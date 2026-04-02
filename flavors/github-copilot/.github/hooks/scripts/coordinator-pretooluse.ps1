# copilot:generated | implementer | 2026-03-16
# copilot:modified  | implementer | 2026-03-17 | fixed false-positive deny on read-only tools
# copilot:modified  | implementer | 2026-04-02 | deny pytest via terminal, hint execute/runTests
# Agent-scoped PreToolUse hook for the coordinator agent.
#
# DELEGATION ENFORCEMENT (HARD -- blocks coordinator from editing/creating files)
# TEST TOOL ENFORCEMENT (HARD -- blocks pytest via terminal, must use runTests)
#
# The coordinator must delegate all file modifications to subagents.
# This hook blocks edit/create tool calls. Defence-in-depth with the
# coordinator PostToolUse detective check (git status after terminal commands).
#
# It also blocks pytest invocations via terminal -- the coordinator must
# use execute/runTests or predefined tasks (tests: domain, tests: all).
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

# Intercept terminal pytest — coordinator must use execute/runTests or tasks
if ($toolName -match 'terminal') {
    $command = $inputData.tool_input.command
    # Fallback: tool_input may arrive as a JSON string
    if (-not $command -and $inputData.tool_input -is [string]) {
        try { $ti = $inputData.tool_input | ConvertFrom-Json; $command = $ti.command } catch {}
    }
    if ($command -match '\bpytest\b|\bpy\.test\b') {
        @{
            hookSpecificOutput = @{
                hookEventName      = 'PreToolUse'
                permissionDecision = 'deny'
                permissionDecisionReason = "Do not run tests via terminal. Use the execute/runTests tool (structured output, VS Code test integration) or the predefined task 'tests: domain' / 'tests: all' via execute/runTask."
            }
        } | ConvertTo-Json -Depth 3 -Compress
        exit 0
    }
    # Non-pytest terminal commands are allowed (git, investigation, etc.)
    Write-Output '{}'
    exit 0
}

# Only inspect file-modifying tools — everything else passes
if ($toolName -notmatch 'editFile|createFile|createDir|editNotebook|writeFile') {
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
