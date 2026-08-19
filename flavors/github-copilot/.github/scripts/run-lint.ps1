# Canonical lint runner for agent workflows.
# All agents MUST use this script instead of calling ruff directly, so that the
# rule set always comes from LINTING_STRICTNESS in .github/af-env.conf and the
# executable is always resolved from the project venv. A direct
# `ruff check --select=...` call also will not reproduce this gate's verdict:
# check-python-linting.py applies the project's own ruff `ignore` /
# `per-file-ignores` on top of the selected rules (see project_ignore= in its
# output), so a bare ruff invocation can show violations the gate does not
# have, or vice versa if the project ignore is broader than the selection
# implies (issue #124 finding 2).
#
# The hard gate in implementer-stop / refactorer-stop lints only *changed*
# files. This script is the repo-wide counterpart: it is what you run to find
# drift that accumulated before the gate existed, or after a bulk edit.
#
# -Scope changed reproduces the gate's own file set, so you can see what the
# gate will say before it says it.
#
# check-python-linting.py also runs `ruff format --check` over that same file
# set -- formatting is blocking at every strictness level, independent of
# rule selection and project_ignore (issue #124). -Fix applies both.
#
# Usage:
#   .github/scripts/run-lint.ps1                    # Lint SRC_DIR/ and tests/
#   .github/scripts/run-lint.ps1 -Scope src         # Lint SRC_DIR/ only
#   .github/scripts/run-lint.ps1 -Scope tests       # Lint tests/ only
#   .github/scripts/run-lint.ps1 -Scope changed     # Lint the branch delta + working tree
#   .github/scripts/run-lint.ps1 -Fix               # Apply ruff's safe fixes + ruff format
#   .github/scripts/run-lint.ps1 -Strictness strict # Override af-env.conf
#
# Exit codes (identical to check-python-linting.py):
#   0 = clean (lint and formatting)
#   1 = blocked (venv python or ruff missing, or bad configuration)
#   2 = lint violations found and/or formatting drift

param(
    [ValidateSet('all', 'src', 'tests', 'changed')]
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
$baseBranch = ''
if (Test-Path $confPath) {
    $m = Select-String -Path $confPath -Pattern '^SRC_DIR=(.+)$'
    if ($m) { $srcDir = $m.Matches[0].Groups[1].Value.Trim() }
    $b = Select-String -Path $confPath -Pattern '^BASE_BRANCH=(.+)$'
    if ($b) { $baseBranch = $b.Matches[0].Groups[1].Value.Trim() }
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

# --- Collect target files ---
# Linting scope is wider than the quality scope: ruff violations in tests/ are
# real violations, so both SRC_DIR and tests count.
function Test-LintPath([string]$p) {
    if (-not $p) { return $false }
    $n = $p -replace '\\', '/'
    return ($n -like "$srcDir/*") -or ($n -like 'tests/*')
}

# Deliberately the same set implementer-stop and refactorer-stop gate on:
# uncommitted work plus everything this branch already committed. Files from an
# earlier phase are invisible to a working-tree diff but still ship on merge.
function Get-ChangedLintFile {
    $changed = @()
    $staged = @(git -C $workspaceRoot diff --name-only --cached --diff-filter=AM -- '*.py' 2>$null)
    if ($staged) { $changed += $staged } else {
        $changed += @(git -C $workspaceRoot diff --name-only HEAD --diff-filter=AM -- '*.py' 2>$null)
    }

    $mergeBase = $null
    foreach ($ref in @($baseBranch, "origin/$baseBranch")) {
        if (-not $baseBranch) { break }
        $mergeBase = @(git -C $workspaceRoot merge-base HEAD $ref 2>$null)[0]
        if ($mergeBase) { break }
    }
    if ($mergeBase) {
        $changed += @(git -C $workspaceRoot diff --name-only --diff-filter=AM "$mergeBase..HEAD" -- '*.py' 2>$null)
    }

    $out = @()
    foreach ($f in ($changed | Select-Object -Unique)) {
        if (-not (Test-LintPath $f)) { continue }
        $full = Join-Path $workspaceRoot $f
        if (Test-Path $full) { $out += $full }
    }
    return $out
}

$targets = @()
$files = @()

if ($Scope -eq 'changed') {
    git -C $workspaceRoot rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) {
        # "cannot determine the changed set" is not the same as "nothing changed";
        # reporting clean here would silently weaken the gate this scope mirrors.
        Write-Output "ERROR: -Scope changed needs a git repository at $workspaceRoot"
        Write-Output "=== Exit Code: 1 ==="
        exit 1
    }
    $base = if ($baseBranch) { $baseBranch } else { '(BASE_BRANCH unset -- working tree only)' }
    $targets = @("changed vs $base")
    $files = @(Get-ChangedLintFile)
} else {
    switch ($Scope) {
        'all'   { $targets = @($srcDir, 'tests') }
        'src'   { $targets = @($srcDir) }
        'tests' { $targets = @('tests') }
    }

    foreach ($t in $targets) {
        $full = Join-Path $workspaceRoot $t
        if (Test-Path $full) {
            $files += Get-ChildItem $full -Recurse -Filter '*.py' -File |
                ForEach-Object { $_.FullName }
        }
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
        $checkExit = $LASTEXITCODE

        # Formatting is blocking regardless of strictness (issue #124), so
        # -Fix must apply it too -- otherwise the remedy this gate names does
        # not actually clear the gate in one command.
        & $ruff format @files
        $formatExit = $LASTEXITCODE

        # ruff exits 1 when violations remain after fixing -- map to the
        # documented contract (2 = violations). ruff format itself only fails
        # (non-zero) on an unparsable file, which is a violation too.
        $exitCode = if ($checkExit -eq 0 -and $formatExit -eq 0) { 0 } else { 2 }
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
