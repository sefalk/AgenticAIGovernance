# copilot:generated | implementer | 2026-03-XX
# copilot:modified  | implementer | 2026-04-14 | add branch context proof gate
# copilot:modified  | implementer | 2026-04-16 | worktree-aware path resolution via active-worktree sentinel
# Agent-scoped PreToolUse hook for the refactorer agent.
#
# NO NEW FILES GATE (HARD -- blocks refactorer from creating files/directories)
# BRANCH CONTEXT PROOF (HARD -- blocks file edits if not on agent/* branch)
#
# Refactoring must only modify existing files. This preventative hook fires
# before createFile/createDirectory calls. Defence-in-depth with the
# refactorer:Stop detective check (git status for untracked files).
#
# Fires only when the refactorer agent is active.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

$ErrorActionPreference = 'SilentlyContinue'

# Worktree-aware path resolution (see ideas/feature-git-worktrees.md §12).
$mainRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot))
$codeRoot = $mainRoot
$sentinel = Join-Path $mainRoot '.github/.active-worktree'
if (Test-Path $sentinel) {
    $p = (Get-Content $sentinel -Raw -ErrorAction SilentlyContinue).Trim()
    if ($p -and (Test-Path $p)) { $codeRoot = $p }
}

# Read and parse stdin
$raw = [Console]::In.ReadToEnd()
try {
    $inputData = $raw | ConvertFrom-Json
} catch {
    Write-Output '{}'
    exit 0
}

# Branch context proof -- block file edits if not on agent/* branch
$toolName = $inputData.tool_name
if ($toolName -match 'editFile|createFile|createDir|editNotebook') {
    $currentBranch = git -C $codeRoot branch --show-current 2>$null
    if ($currentBranch -and $currentBranch -notmatch '^agent/') {
        @{
            hookSpecificOutput = @{
                hookEventName      = 'PreToolUse'
                permissionDecision = 'deny'
                permissionDecisionReason = "Branch context violation: refactorer is running on branch '$currentBranch', not on an agent/* branch. Ensure the coordinator created a worktree for this task (Step 0d). Expected branch: agent/{workflow-id}."
            }
        } | ConvertTo-Json -Depth 3 -Compress
        exit 0
    }
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
