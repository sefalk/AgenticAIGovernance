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

. "$PSScriptRoot/_common.ps1"

# Read and parse stdin
$raw = [Console]::In.ReadToEnd()
try {
    $inputData = $raw | ConvertFrom-Json
} catch {
    Write-Output '{}'
    exit 0
}

# Branch context proof -- block file edits unless each repository written to is
# on an agent/* branch. In a multi-root workspace the edited file need not live
# in the repository this hook is deployed in, so the file names the repository
# to ask (issue #456); a call naming no path is judged by the deploying one.
$toolName = $inputData.tool_name
if (Test-AfWriteTool $toolName) {
    $targets = @(Get-AfWriteTargets $inputData.tool_input)
    $roots = if ($targets.Count -gt 0) { @($targets | ForEach-Object { $_.Root } | Select-Object -Unique) } else { @($script:AfCodeRoot) }
    foreach ($root in $roots) {
        # Outside a repo there is nothing to prove, so the label stays empty there.
        $currentBranch = Get-AfBranchLabel $root
        if ($currentBranch -and $currentBranch -notmatch '^agent/') {
            @{
                hookSpecificOutput = @{
                    hookEventName      = 'PreToolUse'
                    permissionDecision = 'deny'
                    permissionDecisionReason = "Branch context violation: refactorer is running on branch '$currentBranch' in $root, not on an agent/* branch. Ensure the coordinator created a worktree for this task (Step 0d). Expected branch: agent/{workflow-id}."
                }
            } | ConvertTo-Json -Depth 3 -Compress
            exit 0
        }
    }
}

# Block file and directory creation. Editing an existing file is the whole
# point of the Refactor phase, so only the creating tools are refused --
# matched by name rather than by a substring, which used to let
# `create_and_run_task` into the same branch as `create_file`.
$creationTools = @(
    'create_file'
    'create_directory'
    'create_new_jupyter_notebook'
    'createFile', 'createDirectory', 'createDir'
)
if ($creationTools -contains $toolName) {
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
