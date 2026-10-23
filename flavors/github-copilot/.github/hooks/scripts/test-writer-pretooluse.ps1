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

# Every file the call refers to, with the repository it lands in (issue #456).
# A batched edit names several, and one production path among them is still a
# production edit. In a multi-root workspace they need not share a repository.
$targets = @(Get-AfWriteTargets $inputData.tool_input)

# Branch context proof -- block file edits unless each repository written to is
# on an agent/* branch. A call naming no path is judged by the deploying
# repository, as before.
$roots = if ($targets.Count -gt 0) { @($targets | ForEach-Object { $_.Root } | Select-Object -Unique) } else { @($script:AfCodeRoot) }
foreach ($root in $roots) {
    # Outside a repo there is nothing to prove, so the label stays empty there.
    $currentBranch = Get-AfBranchLabel $root
    if ($currentBranch -and $currentBranch -notmatch '^agent/') {
        @{
            hookSpecificOutput = @{
                hookEventName      = 'PreToolUse'
                permissionDecision = 'deny'
                permissionDecisionReason = "Branch context violation: test-writer is running on branch '$currentBranch' in $root, not on an agent/* branch. Ensure the coordinator created a worktree for this task (Step 0d). Expected branch: agent/{workflow-id}."
            }
        } | ConvertTo-Json -Depth 3 -Compress
        exit 0
    }
}

if ($targets.Count -eq 0) {
    Write-Output '{}'
    exit 0
}

# Check each path against the production source directory of its repository
try {
    foreach ($target in $targets) {
        $SRC_DIR = Get-AfRepoConfig -Root $target.Root -Key 'SRC_DIR' -Default 'src'
        if ($null -ne $target.Rel) {
            $src = (($SRC_DIR -replace '\\', '/') -replace '^\./', '').TrimEnd('/')
            $rel = $target.Rel -replace '\\', '/'
            $isProd = (-not $src) -or ($src -eq '.') -or ($rel -eq $src) -or
                $rel.StartsWith("$src/", [System.StringComparison]::OrdinalIgnoreCase)
        } else {
            # Outside any repository: the comparison every release before #456 made.
            $prodRoot = [System.IO.Path]::GetFullPath($SRC_DIR)
            $isProd = [System.IO.Path]::GetFullPath($target.Path).StartsWith($prodRoot, [System.StringComparison]::OrdinalIgnoreCase)
        }
        if (-not $isProd) { continue }

        @{
            hookSpecificOutput = @{
                hookEventName      = 'PreToolUse'
                permissionDecision = 'deny'
                permissionDecisionReason = "TDD phase isolation: test-writer cannot modify production code under $SRC_DIR/ (offending path: $($target.Path)). Only test files should be created or edited during the Red phase."
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
