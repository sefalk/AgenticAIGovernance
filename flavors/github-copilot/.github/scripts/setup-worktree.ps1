# copilot:generated | implementer | 2026-04-14
# Bootstrap a new git worktree for an agent task.
#
# Usage:
#   .github/scripts/setup-worktree.ps1 -WorkflowId feat-auth
#   .github/scripts/setup-worktree.ps1 -WorkflowId fix-db-pool -BaseBranch main
#   .github/scripts/setup-worktree.ps1 -WorkflowId feat-auth -SkipVenv
#
# What it does:
#   1. Reads WORKTREE_DIR from af-env.conf (default: ../wt)
#   2. Validates the workflow ID slug
#   3. Checks for stale worktrees and prunes them
#   4. Creates the worktree at {WORKTREE_DIR}/{WorkflowId} on branch agent/{WorkflowId}
#   5. Bootstraps the Python venv (sym-link strategy or fresh install)
#   6. Verifies .github/ hooks are accessible
#   7. Prints the worktree path for the coordinator to record
#
# Exit codes:
#   0 = success, worktree ready
#   1 = validation failure (ID invalid, path collision, repo unhealthy)
#   2 = worktree creation failed
#   3 = venv bootstrap failed (non-fatal if -SkipVenv)

param(
    [Parameter(Mandatory = $true)]
    [string]$WorkflowId,

    [string]$BaseBranch = 'dev',

    [switch]$SkipVenv
)

$ErrorActionPreference = 'Stop'

# --- Configuration ---
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot   = (Resolve-Path "$scriptDir/../..").Path
$confPath   = Join-Path $repoRoot '.github/af-env.conf'

$WT_DIR     = '../wt'
$BRANCH_PREFIX = 'agent'

if (Test-Path $confPath) {
    $m = Select-String -Path $confPath -Pattern '^WORKTREE_DIR=(.+)$'
    if ($m) { $WT_DIR = $m.Matches[0].Groups[1].Value.Trim() }
    $m2 = Select-String -Path $confPath -Pattern '^WORKTREE_BRANCH_PREFIX=(.+)$'
    if ($m2) { $BRANCH_PREFIX = $m2.Matches[0].Groups[1].Value.Trim() }
}

# --- Validation ---
if ($WorkflowId -notmatch '^[a-z0-9][a-z0-9-]*$') {
    Write-Error "Invalid workflow ID '$WorkflowId'. Must match '^[a-z0-9][a-z0-9-]+' (e.g. feat-auth, fix-db-pool)."
    exit 1
}

$branchName = "$BRANCH_PREFIX/$WorkflowId"
$wtPath     = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $WT_DIR | Join-Path -ChildPath $WorkflowId))

Write-Host ""
Write-Host "=== Worktree Bootstrap ==="
Write-Host "  Workflow ID : $WorkflowId"
Write-Host "  Branch      : $branchName"
Write-Host "  Path        : $wtPath"
Write-Host "  Base        : $BaseBranch"
Write-Host ""

# --- Repo health check ---
Push-Location $repoRoot
try {
    git status --porcelain 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Repository is not healthy (git status failed). Fix repo state before creating a worktree."
        exit 1
    }
} catch {
    Write-Error "Failed to run git status: $_"
    exit 1
}

# --- Base branch check ---
$baseSha = git rev-parse "refs/heads/$BaseBranch" 2>$null
if (-not $baseSha) {
    Write-Error "Base branch '$BaseBranch' does not exist locally. Run 'git fetch' or create the branch first."
    exit 1
}

# --- Stale worktree audit ---
Write-Host "  Checking for stale worktrees..."
$prunable = git worktree list --porcelain 2>$null | Select-String 'prunable'
if ($prunable) {
    Write-Warning "  Prunable stale entries found. Running 'git worktree prune'..."
    git worktree prune
}

# --- Path collision check ---
if (Test-Path $wtPath) {
    Write-Error "Worktree path '$wtPath' already exists. Is another task still running? Run 'git worktree list' to check."
    exit 1
}

# --- Create worktree ---
Write-Host "  Creating worktree..."
git worktree add $wtPath -b $branchName $BaseBranch
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create worktree. Exit code: $LASTEXITCODE"
    exit 2
}
Pop-Location

# --- Verify hooks accessible ---
$hooksPath = Join-Path $wtPath '.github/hooks'
if (-not (Test-Path $hooksPath)) {
    Write-Warning "  .github/hooks not found in worktree. Hooks may not fire correctly (check .git file in worktree)."
} else {
    Write-Host "  .github/hooks accessible: OK"
}

# --- Python venv bootstrap ---
if (-not $SkipVenv) {
    Write-Host "  Setting up Python venv..."
    $mainVenv = Join-Path $repoRoot '.venv'
    $wtVenv   = Join-Path $wtPath '.venv'

    if (Test-Path $mainVenv) {
        # Create a junction (Windows) or symlink to the main venv — avoids full reinstall
        try {
            New-Item -ItemType Junction -Path $wtVenv -Target $mainVenv -ErrorAction Stop | Out-Null
            Write-Host "  Venv: junction to main .venv created ($(Split-Path $mainVenv -Leaf))"
        } catch {
            Write-Warning "  Could not create venv junction: $_. Trying fresh install..."
            $SkipVenv = $true
        }
    }

    if ($SkipVenv -or -not (Test-Path $mainVenv)) {
        Write-Host "  Venv: no shared venv found -- creating fresh..."
        Push-Location $wtPath
        python -m venv .venv
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "  python -m venv failed (exit $LASTEXITCODE). Skipping venv setup."
            Pop-Location
        } else {
            # Install deps using run-deps if available
            $runDeps = Join-Path $wtPath '.github/scripts/run-deps.ps1'
            if (Test-Path $runDeps) {
                & $runDeps -Scope dev
            } else {
                # Fallback: find dep file from af-env.conf
                $depFile = 'requirements-dev.txt'
                $m3 = Select-String -Path $confPath -Pattern '^DEP_DEV_FILE=(.+)$'
                if ($m3) { $depFile = $m3.Matches[0].Groups[1].Value.Trim() }
                $pip = Join-Path $wtPath '.venv/Scripts/pip.exe'
                if (Test-Path $pip) { & $pip install -r $depFile }
            }
            Pop-Location
        }
    }
} else {
    Write-Host "  Venv: skipped (-SkipVenv)"
}

# --- Summary ---
Write-Host ""
Write-Host "=== Worktree Ready ==="
Write-Host "  Path   : $wtPath"
Write-Host "  Branch : $branchName"
Write-Host "  Open   : code `"$wtPath`""
Write-Host ""
Write-Host "  Next: Open the worktree in VS Code and start the agent workflow."
Write-Host "  Record in plan: worktree: $wtPath"
Write-Host ""

exit 0
