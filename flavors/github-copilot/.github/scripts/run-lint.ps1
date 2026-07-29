# Canonical lint runner for agent workflows.
# All agents MUST use this script instead of calling ruff directly, so that the
# rule set always comes from LINTING_STRICTNESS in .github/af-env.conf and the
# executable is always resolved from the project venv.
#
# The hard gate in implementer-stop / refactorer-stop lints only *changed*
# files. This script is the repo-wide counterpart: it is what you run to find
# drift that accumulated before the gate existed, or after a bulk edit.
#
# Usage:
#   .github/scripts/run-lint.ps1                    # Lint SRC_DIR/ and tests/
#   .github/scripts/run-lint.ps1 -Scope src         # Lint SRC_DIR/ only
#   .github/scripts/run-lint.ps1 -Scope tests       # Lint tests/ only
#   .github/scripts/run-lint.ps1 -Fix               # Apply ruff's safe fixes
#   .github/scripts/run-lint.ps1 -Strictness strict # Override af-env.conf
#
# Exit codes (identical to check-python-linting.py):
#   0 = clean
#   1 = blocked (venv python or ruff missing, or bad configuration)
#   2 = lint violations found

param(
    [ValidateSet('all', 'src', 'tests')]
    [string]$Scope = 'all',

    [ValidateSet('minimal', 'standard', 'strict')]
    [string]$Strictness = '',

    [switch]$Fix
)

# --- Configuration ---
# Resolve workspace root (script is at .github/scripts/)
$workspaceRoot = (Resolve-Path "$PSScriptRoot/../..").Path
$confPath = Join-Path $workspaceRoot '.github/af-env.conf'

$srcDir = 'src'
if (Test-Path $confPath) {
    $m = Select-String -Path $confPath -Pattern '^SRC_DIR=(.+)$'
    if ($m) { $srcDir = $m.Matches[0].Groups[1].Value.Trim() }
}

# Resolve venv python (same contract as run-tests.ps1)
$python = Join-Path $workspaceRoot '.venv/Scripts/python.exe'
if (-not (Test-Path $python -ErrorAction SilentlyContinue)) {
    $python = Join-Path $workspaceRoot '.venv/bin/python'
}
if (-not (Test-Path $python -ErrorAction SilentlyContinue)) {
    Write-Output "ERROR: venv python not found under $workspaceRoot/.venv"
    exit 1
}

# --- Collect target directories ---
$targets = @()
switch ($Scope) {
    'all'   { $targets = @($srcDir, 'tests') }
    'src'   { $targets = @($srcDir) }
    'tests' { $targets = @('tests') }
}

$files = @()
foreach ($t in $targets) {
    $full = Join-Path $workspaceRoot $t
    if (Test-Path $full) {
        $files += Get-ChildItem $full -Recurse -Filter '*.py' -File |
            ForEach-Object { $_.FullName }
    }
}

Write-Output "=== Lint Runner: scope=$Scope targets=$($targets -join ', ') files=$($files.Count) ==="

if ($files.Count -eq 0) {
    Write-Output "(no Python files in scope)"
    Write-Output "=== Exit Code: 0 ==="
    exit 0
}

Push-Location $workspaceRoot
try {
    if ($Fix) {
        # --- Fix mode ---
        # ruff has no fix mode behind check-python-linting.py, so the rule set is
        # mapped here. Source of truth for the GATE remains
        # check-python-linting.py -- this map only widens/narrows what gets
        # auto-fixed, never what blocks. Keep in sync when adding a level.
        $strictnessRules = @{
            'minimal'  = 'F8'
            'standard' = 'E,F,I'
            'strict'   = 'E,F,I,B,UP,SIM,C90'
        }

        $level = $Strictness
        if (-not $level -and (Test-Path $confPath)) {
            $m = Select-String -Path $confPath -Pattern '^LINTING_STRICTNESS=(.+)$'
            if ($m) { $level = $m.Matches[0].Groups[1].Value.Trim() }
        }
        if (-not $level) { $level = 'standard' }
        if (-not $strictnessRules.ContainsKey($level)) {
            Write-Output "ERROR: unknown LINTING_STRICTNESS '$level'. Valid: minimal, standard, strict"
            Write-Output "=== Exit Code: 1 ==="
            exit 1
        }

        $ruff = Join-Path $workspaceRoot '.venv/Scripts/ruff.exe'
        if (-not (Test-Path $ruff -ErrorAction SilentlyContinue)) {
            $ruff = Join-Path $workspaceRoot '.venv/bin/ruff'
        }
        if (-not (Test-Path $ruff -ErrorAction SilentlyContinue)) {
            $ruffCmd = Get-Command ruff -ErrorAction SilentlyContinue
            if ($ruffCmd) { $ruff = $ruffCmd.Source } else { $ruff = $null }
        }
        if (-not $ruff) {
            Write-Output "ERROR: ruff not found in .venv or PATH. Install with: pip install ruff"
            Write-Output "=== Exit Code: 1 ==="
            exit 1
        }

        & $ruff check "--select=$($strictnessRules[$level])" --fix @files
        $ruffExit = $LASTEXITCODE
        # ruff exits 1 when violations remain after fixing -- map to the
        # documented contract (2 = violations).
        $exitCode = if ($ruffExit -eq 0) { 0 } else { 2 }
    } else {
        # --- Check mode: delegate to the gate's own checker ---
        $lintScript = Join-Path $workspaceRoot '.github/scripts/check-python-linting.py'
        if (-not (Test-Path $lintScript)) {
            Write-Output "ERROR: .github/scripts/check-python-linting.py not found"
            Write-Output "=== Exit Code: 1 ==="
            exit 1
        }
        $checkArgs = @($lintScript, '--files') + $files
        if ($Strictness) { $checkArgs += @('--strictness', $Strictness) }
        & $python @checkArgs
        $exitCode = $LASTEXITCODE
    }
} finally {
    Pop-Location
}

Write-Output "=== Exit Code: $exitCode ==="
exit $exitCode
