# Agent-scoped Stop hook for the refactorer agent.
# copilot:modified  | implementer | 2026-03-19 | test log freshness check in stop hooks
#
# REFACTOR PHASE GATES (HARD -- blocks refactorer if tests fail or new files created)
#
# Gate 1: All tests must still pass after refactoring.
# Gate 2: No new files created -- refactoring modifies existing files only.
#         Scoped to .py files under SRC_DIR/ and tests/ to avoid false positives
#         from pre-existing untracked files (notebooks, temp files, etc.).
#
# Fires as SubagentStop when the refactorer is invoked by the coordinator.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

$ErrorActionPreference = 'SilentlyContinue'

# Load project config
$SRC_DIR = 'src'
$confPath = Join-Path (Get-Location) '.github/af-env.conf'
if (Test-Path $confPath) {
    $m = Select-String -Path $confPath -Pattern '^SRC_DIR=(.+)$'
    if ($m) { $SRC_DIR = $m.Matches[0].Groups[1].Value.Trim() }
}

# Read stdin (hook input JSON -- required by protocol)
$null = [Console]::In.ReadToEnd()

# ---------- Gate 1: All tests must pass ----------

$pytest = Get-Command pytest -ErrorAction SilentlyContinue
if (-not $pytest) {
    $output = @{
        systemMessage = "refactorer:Stop -- pytest not found, test gate skipped"
    } | ConvertTo-Json -Compress
    Write-Output $output
    exit 0
}

if (-not (Test-Path "tests/")) {
    $output = @{
        systemMessage = "refactorer:Stop -- no tests/ directory, test gate skipped"
    } | ConvertTo-Json -Compress
    Write-Output $output
    exit 0
}

# ---------- Test Log Freshness Check ----------
# Accept last run if ALL tests passed AND no code changed since (committed or uncommitted).
# No time limit — change detection is the criterion, not elapsed time.
$testLogPath = Join-Path (Get-Location) '.github/test-log.json'
$fromLog = $false
if (Test-Path $testLogPath) {
    try {
        $log = Get-Content $testLogPath -Raw | ConvertFrom-Json
        $allEntry = $null
        if ($log.PSObject.Properties.Name -contains 'all') { $allEntry = $log.all }
        if ($allEntry -and $allEntry.exit_code -eq 0 -and $allEntry.last_run) {
            $commitsSince = git log --oneline --after="$($allEntry.last_run)" -- "$SRC_DIR/" 'tests/' 2>$null
            $uncommitted = git diff --name-only HEAD -- "$SRC_DIR/" 'tests/' 2>$null
            if (-not $commitsSince -and -not $uncommitted) {
                $fromLog = $true
            }
        }
    } catch {}
}

if ($fromLog) {
    $exitCode = 0
} else {
    $scriptPath = Join-Path (Get-Location) '.github/scripts/run-tests.ps1'
    $result = & $scriptPath -Scope all 2>&1
    $exitCode = $LASTEXITCODE
}

if ($exitCode -ne 0 -and $exitCode -ne 5) {
    $summary = ($result | Where-Object { $_ -notmatch '^===' } | Select-Object -Last 3 | Out-String).Trim()
    $output = @{
        hookSpecificOutput = @{
            hookEventName = "Stop"
            decision = "block"
            reason = "Refactor phase violation: tests are failing after refactoring. All tests must remain green. Summary: $summary"
        }
    } | ConvertTo-Json -Compress -Depth 3
    Write-Output $output
    exit 0
}

# ---------- Gate 2: No new .py files under SRC_DIR/ or tests/ ----------

$newFiles = @()

# Check src/ for untracked .py files
$statusSrc = & git status --porcelain "$SRC_DIR/" 2>$null |
    Where-Object { $_ -match '^\?\? ' } |
    ForEach-Object { ($_ -replace '^.. ', '').Trim('"') } |
    Where-Object { $_ -match '\.py$' }
if ($statusSrc) { $newFiles += $statusSrc }

# Check tests/ for untracked .py files
$statusTests = & git status --porcelain "tests/" 2>$null |
    Where-Object { $_ -match '^\?\? ' } |
    ForEach-Object { ($_ -replace '^.. ', '').Trim('"') } |
    Where-Object { $_ -match '\.py$' }
if ($statusTests) { $newFiles += $statusTests }

if ($newFiles.Count -gt 0) {
    $list = $newFiles -join ', '
    $output = @{
        hookSpecificOutput = @{
            hookEventName = "Stop"
            decision = "block"
            reason = "Refactor phase violation: new files were created. Refactoring must only modify existing files. New files: $list"
        }
    } | ConvertTo-Json -Compress -Depth 3
    Write-Output $output
    exit 0
}

# ---------- Gate 3: Python quality on changed source files ----------

$changedSrcPy = @()
try {
    $changedSrcPy = git diff --name-only --cached --diff-filter=AM -- "$SRC_DIR/" 2>$null |
        Where-Object { $_ -match '\.py$' }
    if (-not $changedSrcPy) {
        $changedSrcPy = git diff --name-only HEAD --diff-filter=AM -- "$SRC_DIR/" 2>$null |
            Where-Object { $_ -match '\.py$' }
    }
} catch {}

if ($changedSrcPy.Count -gt 0) {
    $qualityScript = Join-Path (Get-Location) '.github/scripts/check-python-quality.py'
    if (-not (Test-Path $qualityScript)) {
        $output = @{
            hookSpecificOutput = @{
                hookEventName = "Stop"
                decision = "block"
                reason = "Refactor phase violation: python quality script missing (.github/scripts/check-python-quality.py)."
            }
        } | ConvertTo-Json -Compress -Depth 3
        Write-Output $output
        exit 0
    }

    $pythonExe = Join-Path (Get-Location) '.venv/Scripts/python.exe'
    if (-not (Test-Path $pythonExe)) {
        $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
        if ($pythonCmd) {
            $pythonExe = $pythonCmd.Source
        } else {
            $output = @{
                hookSpecificOutput = @{
                    hookEventName = "Stop"
                    decision = "block"
                    reason = "Refactor phase violation: no Python executable found to run quality gate checks."
                }
            } | ConvertTo-Json -Compress -Depth 3
            Write-Output $output
            exit 0
        }
    }

    $qualityResult = & $pythonExe $qualityScript --files @($changedSrcPy) 2>&1
    $qualityExit = $LASTEXITCODE
    if ($qualityExit -ne 0) {
        $summary = ($qualityResult | Select-Object -First 10 | Out-String).Trim()
        $output = @{
            hookSpecificOutput = @{
                hookEventName = "Stop"
                decision = "block"
                reason = "Refactor phase violation: python quality gate failed (type hints/docstrings/ignore hygiene). Summary: $summary"
            }
        } | ConvertTo-Json -Compress -Depth 3
        Write-Output $output
        exit 0
    }
}

# ---------- Gate 4: Atomic ignore commit check ----------
$diffLines = @()
try {
    $diffLines = git diff --cached -- '*.py' 2>$null
    if (-not $diffLines) { $diffLines = git diff HEAD -- '*.py' 2>$null }
} catch {}
$ignorePattern = '#\s*(type:\s*ignore|pyright:\s*ignore|noqa)'
$newIgnoreLines = @($diffLines | Where-Object { $_ -match '^\+[^+]' -and $_ -match $ignorePattern })
$otherAddedLines = @($diffLines | Where-Object { $_ -match '^\+[^+]' -and $_ -notmatch $ignorePattern -and $_ -match '\S' })
if ($newIgnoreLines.Count -gt 1) {
    $output = @{
        hookSpecificOutput = @{
            hookEventName = "Stop"
            decision = "block"
            reason = "Refactor phase violation: $($newIgnoreLines.Count) new ignore statements in one commit. Each must be its own standalone atomic commit. Format: '[agent:name] justify ignore: file:line RULE -- reason'"
        }
    } | ConvertTo-Json -Compress -Depth 3
    Write-Output $output
    exit 0
} elseif ($newIgnoreLines.Count -eq 1 -and $otherAddedLines.Count -gt 0) {
    $output = @{
        hookSpecificOutput = @{
            hookEventName = "Stop"
            decision = "block"
            reason = "Refactor phase violation: new ignore statement mixed with $($otherAddedLines.Count) other code changes. Commit code changes first, then add the ignore in its own standalone commit. Format: '[agent:name] justify ignore: file:line RULE -- reason'"
        }
    } | ConvertTo-Json -Compress -Depth 3
    Write-Output $output
    exit 0
}

# ---------- Gate 5: Python linting on changed source files ----------
$lintStatus = 'no src changes'
if ($changedSrcPy.Count -gt 0) {
    $lintStatus = 'skipped (script/python not available)'
    $lintScript = Join-Path (Get-Location) '.github/scripts/check-python-linting.py'
    if ((Test-Path $lintScript) -and $pythonExe) {
        $lintResult = & $pythonExe $lintScript --files @($changedSrcPy) 2>&1
        $lintExit = $LASTEXITCODE
        if ($lintExit -eq 2) {
            $lintSummary = ($lintResult | Select-Object -First 15 | Out-String).Trim()
            $output = @{
                hookSpecificOutput = @{
                    hookEventName = "Stop"
                    decision = "block"
                    reason = "Refactor phase violation: linting gate failed. Fix with: ruff check --fix <files>. Violations: $lintSummary"
                }
            } | ConvertTo-Json -Compress -Depth 3
            Write-Output $output
            exit 0
        } elseif ($lintExit -eq 1) {
            $lintStatus = 'BLOCKED (ruff not installed)'
        } else {
            $lintStatus = 'clean'
        }
    }
}

# All gates passed
$output = @{
    systemMessage = "refactorer:Stop -- all gates PASS: tests $(if ($fromLog) {'accepted from log'} else {'green'}), no new files created, python quality verified, linting: $lintStatus"
} | ConvertTo-Json -Compress
Write-Output $output
exit 0
