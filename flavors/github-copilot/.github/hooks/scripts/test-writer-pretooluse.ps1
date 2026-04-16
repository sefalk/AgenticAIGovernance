# copilot:generated | implementer | 2026-03-16
# copilot:modified  | implementer | 2026-04-14 | add branch context proof gate
# copilot:modified  | implementer | 2026-04-16 | worktree-aware path resolution via active-worktree sentinel
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
if ($toolName -notmatch 'editFile|createFile|createDir|editNotebook') {
    Write-Output '{}'
    exit 0
}

# Branch context proof -- block file edits if not on an agent/* branch
$currentBranch = git -C $codeRoot branch --show-current 2>$null
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

# Extract the file path from tool input
$filePath = $inputData.tool_input.filePath
if (-not $filePath) {
    # Try alternate property names
    $filePath = $inputData.tool_input.path
}
if (-not $filePath) {
    Write-Output '{}'
    exit 0
}

# Resolve to absolute path and check against production source directory
try {
    $resolved = [System.IO.Path]::GetFullPath($filePath)
    $prodRoot = [System.IO.Path]::GetFullPath($SRC_DIR)

    if ($resolved.StartsWith($prodRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        @{
            hookSpecificOutput = @{
                hookEventName      = 'PreToolUse'
                permissionDecision = 'deny'
                permissionDecisionReason = "TDD phase isolation: test-writer cannot modify production code under $SRC_DIR/. Only test files should be created or edited during the Red phase."
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
