# copilot:generated | implementer | 2026-04-14
# Safely remove a git worktree after task completion.
#
# Usage:
#   .github/scripts/cleanup-worktree.ps1 -WorkflowId feat-auth
#   .github/scripts/cleanup-worktree.ps1 -WorkflowId feat-auth -Force
#
# What it does:
#   1. Reads WORKTREE_DIR from af-env.conf (default: ../wt)
#   2. Resolves the worktree path for the given workflow ID
#   3. Verifies the worktree exists in git worktree list
#   4. Checks the worktree is clean (git status --porcelain must be empty)
#   5. Removes the worktree
#   6. Prunes stale references
#   7. Verifies removal
#
# Exit codes:
#   0 = success, worktree removed
#   1 = validation failure (worktree not found, or does not match expected path)
#   2 = worktree is dirty -- halts and reports uncommitted changes
#   3 = removal failed

param(
    [Parameter(Mandatory = $true)]
    [string]$WorkflowId,

    # Force removal even if worktree is locked (use only when human has confirmed it is safe)
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# --- Configuration ---
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot  = (Resolve-Path "$scriptDir/../..").Path
$confPath  = Join-Path $repoRoot '.github/af-env.conf'

$WT_DIR        = '../wt'
$BRANCH_PREFIX = 'agent'

if (Test-Path $confPath) {
    $m = Select-String -Path $confPath -Pattern '^WORKTREE_DIR=(.+)$'
    if ($m) { $WT_DIR = $m.Matches[0].Groups[1].Value.Trim() }
    $m2 = Select-String -Path $confPath -Pattern '^WORKTREE_BRANCH_PREFIX=(.+)$'
    if ($m2) { $BRANCH_PREFIX = $m2.Matches[0].Groups[1].Value.Trim() }
}

$branchName = "$BRANCH_PREFIX/$WorkflowId"
$wtPath     = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $WT_DIR | Join-Path -ChildPath $WorkflowId))

Write-Host ""
Write-Host "=== Worktree Cleanup ==="
Write-Host "  Workflow ID : $WorkflowId"
Write-Host "  Branch      : $branchName"
Write-Host "  Path        : $wtPath"
Write-Host ""

Push-Location $repoRoot

# --- Verify worktree exists in git ---
$rawList = git worktree list --porcelain 2>$null
$knownPaths = ($rawList | Select-String '^worktree (.+)$' | ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() })
$isRegistered = $knownPaths | Where-Object { $_ -eq $wtPath -or [System.IO.Path]::GetFullPath($_) -eq $wtPath }

if (-not $isRegistered) {
    Write-Warning "Worktree path '$wtPath' is not registered in 'git worktree list'."
    Write-Host "  Active worktrees:"
    git worktree list
    Write-Host ""
    Write-Host "  If the directory was deleted manually, run: git worktree prune"
    exit 1
}

# --- Check worktree is clean (unless -Force) ---
if (-not $Force) {
    $status = git -C $wtPath status --porcelain 2>$null
    if ($status) {
        Write-Host ""
        Write-Host "ERROR: Worktree is dirty. Uncommitted changes found:" -ForegroundColor Red
        Write-Host $status
        Write-Host ""
        Write-Host "  Options:"
        Write-Host "    Commit   : cd `"$wtPath`" ; git add <files> ; git commit -m `"...`""
        Write-Host "    Discard  : cd `"$wtPath`" ; git checkout -- ."
        Write-Host "    Stash    : cd `"$wtPath`" ; git stash"
        Write-Host ""
        Write-Host "  After cleaning: re-run cleanup-worktree.ps1 -WorkflowId $WorkflowId"
        exit 2
    }
    Write-Host "  Status: clean"
} else {
    Write-Host "  Status: -Force -- skipping dirty check"
}

# --- Remove worktree ---
Write-Host "  Removing worktree..."
if ($Force) {
    git worktree remove --force $wtPath
} else {
    git worktree remove $wtPath
}

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERROR: 'git worktree remove' failed (exit $LASTEXITCODE)." -ForegroundColor Red
    Write-Host "  If the worktree is locked, run:"
    Write-Host "    git worktree unlock `"$wtPath`""
    Write-Host "  Then retry: cleanup-worktree.ps1 -WorkflowId $WorkflowId"
    Write-Host "  Or use -Force if you are certain there is nothing to keep."
    exit 3
}

# --- Prune stale references ---
Write-Host "  Pruning stale references..."
git worktree prune

# --- Verify removal ---
$remainingList = git worktree list 2>$null
if ($remainingList -match [regex]::Escape($wtPath)) {
    Write-Warning "  Path still appears in 'git worktree list'. Manual check recommended."
} else {
    Write-Host "  Verified: worktree removed"
}

Pop-Location

Write-Host ""
Write-Host "=== Cleanup Complete ==="
Write-Host "  Worktree : $wtPath  [REMOVED]"
Write-Host "  Branch   : $branchName  [local branch still exists -- delete when ready]"
Write-Host ""
Write-Host "  To delete the local branch (after confirming merge):"
Write-Host "    git branch -d $branchName"
Write-Host ""

exit 0
