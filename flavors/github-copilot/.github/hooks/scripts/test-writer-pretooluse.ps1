# Agent-scoped PreToolUse hook for the test-writer agent.
#
# TDD PHASE ISOLATION (HARD -- blocks test-writer from editing production code)
# BRANCH CONTEXT PROOF (HARD -- blocks file edits if not on agent/* branch)
#
# The Red phase must only create/edit test files. If the test-writer modifies
# production code under SRC_DIR/, the tests may pass immediately and the
# Green phase becomes a no-op -- violating the most fundamental TDD invariant.
#
# Fires only when the test-writer agent is active.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

$ErrorActionPreference = 'SilentlyContinue'

. "$PSScriptRoot/_common.ps1"

# Worktree-aware path resolution (see ideas/feature-git-worktrees.md §12).
$mainRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot))
$codeRoot = $mainRoot
$sentinel = Join-Path $mainRoot '.github/.active-worktree'
if (Test-Path $sentinel) {
    $p = (Get-Content $sentinel -Raw -ErrorAction SilentlyContinue).Trim()
    if ($p -and (Test-Path $p)) { $codeRoot = $p }
}

# Load project config
$SRC_DIR = 'src'
$confPath = Join-Path $mainRoot '.github/af-env.conf'
if (Test-Path $confPath) {
    $m = Select-String -Path $confPath -Pattern '^SRC_DIR=(.+)$'
    if ($m) { $SRC_DIR = $m.Matches[0].Groups[1].Value.Trim() }
}

# Read and parse stdin
$raw = [Console]::In.ReadToEnd()
try {
    $inputData = $raw | ConvertFrom-Json
} catch {
    Write-Output '{}'
    exit 0
}

# Only inspect file-modifying tools (not read/search tools that contain 'File')
$toolName = $inputData.tool_name
if (-not (Test-AfWriteTool $toolName)) {
    Write-Output '{}'
    exit 0
}

# Branch context proof -- block file edits if not on an agent/* branch
$currentBranch = git -C $codeRoot branch --show-current 2>$null
if (-not $currentBranch) {
    # Detached HEAD is not an agent branch either; outside a repo there is
    # nothing to prove, so stay silent there.
    if ((git -C $codeRoot rev-parse --is-inside-work-tree 2>$null) -eq 'true') {
        $currentBranch = '(detached HEAD)'
    }
}
if ($currentBranch -and $currentBranch -notmatch '^agent/') {
    @{
        hookSpecificOutput = @{
            hookEventName      = 'PreToolUse'
            permissionDecision = 'deny'
            permissionDecisionReason = "Branch context violation: test-writer is running on branch '$currentBranch', not on an agent/* branch. Ensure the coordinator created a worktree for this task (Step 0d). Expected branch: agent/{workflow-id}."
        }
    } | ConvertTo-Json -Depth 3 -Compress
    exit 0
}

# Extract every file path the call refers to. A batched edit names several,
# and one production path among them is still a production edit.
$filePaths = @(Get-AfWritePaths $inputData.tool_input)
if ($filePaths.Count -eq 0) {
    Write-Output '{}'
    exit 0
}

# Resolve to absolute paths and check against the production source directory
try {
    $prodRoot = [System.IO.Path]::GetFullPath($SRC_DIR)

    foreach ($filePath in $filePaths) {
        $resolved = [System.IO.Path]::GetFullPath($filePath)
        if (-not $resolved.StartsWith($prodRoot, [System.StringComparison]::OrdinalIgnoreCase)) { continue }

        @{
            hookSpecificOutput = @{
                hookEventName      = 'PreToolUse'
                permissionDecision = 'deny'
                permissionDecisionReason = "TDD phase isolation: test-writer cannot modify production code under $SRC_DIR/ (offending path: $filePath). Only test files should be created or edited during the Red phase."
            }
        } | ConvertTo-Json -Depth 3 -Compress
        exit 0
    }
} catch {
    # Path resolution failed -- allow (don't block on parse errors)
    Write-Output '{}'
    exit 0
}

# Not a production file -- allow
Write-Output '{}'
