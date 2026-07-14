# Agent-scoped Stop hook for the coordinator agent -- post-merge worktree cleanup gate.
#
# WORKTREE CLEANUP GATE (HARD -- verifies worktree is clean before removal)
#
# Fires when the coordinator agent session ends (Stop event).
# Checks whether a worktree cleanup was requested and validates preconditions.
# If the worktree is dirty, blocks removal and escalates to the human.
#
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

$ErrorActionPreference = 'SilentlyContinue'

# Worktree-aware path resolution (see ideas/feature-git-worktrees.md §12).
$mainRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot))

# Read and parse stdin
$raw = [Console]::In.ReadToEnd()
try {
    $inputData = $raw | ConvertFrom-Json
} catch {
    Write-Output '{}'
    exit 0
}

# Read WORKTREE_DIR from af-env.conf
$WT_DIR = '../wt'
$confPath = Join-Path $mainRoot '.github/af-env.conf'
if (Test-Path $confPath) {
    $m = Select-String -Path $confPath -Pattern '^WORKTREE_DIR=(.+)$'
    if ($m) { $WT_DIR = $m.Matches[0].Groups[1].Value.Trim() }
}

# Collect all active worktrees (besides main checkout)
$worktreeList = @()
try {
    $rawList = git worktree list --porcelain 2>$null
    if ($rawList) {
        $worktreeList = $rawList
    }
} catch {}

if (-not $worktreeList) {
    # No worktrees or git not available -- pass through silently
    $output = @{ systemMessage = 'coordinator:PostMerge -- no active worktrees found, nothing to clean up' } | ConvertTo-Json -Compress
    Write-Output $output
    exit 0
}

# Parse worktrees: find any that are prunable (stale entries)
$prunableFound = $false
$currentWorktreeLines = $worktreeList -join "`n"
if ($currentWorktreeLines -match 'prunable') {
    $prunableFound = $true
}

# Build active agent worktree summary for the coordinator
$agentWorktrees = @()
$lines = $worktreeList
$i = 0
while ($i -lt $lines.Count) {
    if ($lines[$i] -match '^worktree (.+)$') {
        $wtPath = $Matches[1].Trim()
        $branch = ''
        $head = ''
        if ($i + 1 -lt $lines.Count -and $lines[$i+1] -match '^HEAD (.+)$') { $head = $Matches[1].Trim(); $i++ }
        if ($i + 1 -lt $lines.Count -and $lines[$i+1] -match '^branch (.+)$') { $branch = $Matches[1].Trim(); $i++ }
        if ($branch -match 'refs/heads/agent/') {
            $agentWorktrees += "$wtPath ($branch)"
        }
    }
    $i++
}

$warningMsg = ''
if ($prunableFound) {
    $warningMsg = ' WARNING: prunable stale entries found -- run `git worktree prune`.'
}

$agentSummary = if ($agentWorktrees.Count -gt 0) {
    "Active agent worktrees ($($agentWorktrees.Count)): $($agentWorktrees -join '; ')"
} else {
    'No active agent/* worktrees'
}

$output = @{
    systemMessage = "coordinator:PostMerge -- $agentSummary.$warningMsg"
} | ConvertTo-Json -Compress
Write-Output $output
exit 0
