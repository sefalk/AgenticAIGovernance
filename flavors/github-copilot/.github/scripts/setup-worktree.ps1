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
#   5. Configures Python interpreter mode (shared or isolated)
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
$WORKTREE_VENV_MODE = 'shared'

if (Test-Path $confPath) {
    $m = Select-String -Path $confPath -Pattern '^WORKTREE_DIR=(.+)$'
    if ($m) { $WT_DIR = $m.Matches[0].Groups[1].Value.Trim() }
    $m2 = Select-String -Path $confPath -Pattern '^WORKTREE_BRANCH_PREFIX=(.+)$'
    if ($m2) { $BRANCH_PREFIX = $m2.Matches[0].Groups[1].Value.Trim() }
    $m3 = Select-String -Path $confPath -Pattern '^WORKTREE_VENV_MODE=(.+)$'
    if ($m3) { $WORKTREE_VENV_MODE = $m3.Matches[0].Groups[1].Value.Trim().ToLowerInvariant() }
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

# --- Python interpreter bootstrap ---
function Set-WorktreeInterpreter {
    param(
        [string]$WorktreePath,
        [string]$InterpreterPath
    )

    $vscodeDir = Join-Path $WorktreePath '.vscode'
    $settingsPath = Join-Path $vscodeDir 'settings.json'

    if (-not (Test-Path $vscodeDir)) {
        New-Item -ItemType Directory -Path $vscodeDir -Force | Out-Null
    }

    $settings = @{}
    if (Test-Path $settingsPath) {
        try {
            $existing = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
            if ($existing) {
                $settings = @{}
                foreach ($p in $existing.PSObject.Properties) {
                    $settings[$p.Name] = $p.Value
                }
            }
        } catch {
            Write-Warning "  Could not parse existing settings.json. Overwriting with minimal interpreter settings."
            $settings = @{}
        }
    }

    $settings['python.defaultInterpreterPath'] = $InterpreterPath
    ($settings | ConvertTo-Json -Depth 20) | Set-Content -Path $settingsPath
    Write-Host "  VS Code interpreter configured: $InterpreterPath"
}

if (-not $SkipVenv) {
    Write-Host "  Configuring Python interpreter mode..."
    $mainPython = Join-Path $repoRoot '.venv/Scripts/python.exe'
    $wtPython = Join-Path $wtPath '.venv/Scripts/python.exe'
    $effectiveMode = $WORKTREE_VENV_MODE

    if ($effectiveMode -ne 'shared' -and $effectiveMode -ne 'isolated') {
        Write-Warning "  Unknown WORKTREE_VENV_MODE '$WORKTREE_VENV_MODE'. Falling back to 'shared'."
        $effectiveMode = 'shared'
    }

    if ($effectiveMode -eq 'shared' -and (Test-Path $mainPython)) {
        Set-WorktreeInterpreter -WorktreePath $wtPath -InterpreterPath $mainPython
        Write-Host "  Venv mode: shared (parent repo .venv)"
    } else {
        if ($effectiveMode -eq 'shared') {
            Write-Warning "  Shared mode requested but parent .venv not found. Falling back to isolated mode for this worktree."
        }

        Push-Location $wtPath
        python -m venv .venv
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "  python -m venv failed (exit $LASTEXITCODE). Interpreter may prompt in VS Code."
            Pop-Location
        } else {
            # Install deps using run-deps if available
            $runDeps = Join-Path $wtPath '.github/scripts/run-deps.ps1'
            if (Test-Path $runDeps) {
                & $runDeps -Scope dev
            } else {
                # Fallback: find dep file from af-env.conf
                $depFile = 'requirements-dev.txt'
                $mDep = Select-String -Path $confPath -Pattern '^DEP_DEV_FILE=(.+)$'
                if ($mDep) { $depFile = $mDep.Matches[0].Groups[1].Value.Trim() }
                $pip = Join-Path $wtPath '.venv/Scripts/pip.exe'
                if (Test-Path $pip) { & $pip install -r $depFile }
            }
            Pop-Location

            if (Test-Path $wtPython) {
                Set-WorktreeInterpreter -WorktreePath $wtPath -InterpreterPath $wtPython
                Write-Host "  Venv mode: isolated (worktree-local .venv)"
            }
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
