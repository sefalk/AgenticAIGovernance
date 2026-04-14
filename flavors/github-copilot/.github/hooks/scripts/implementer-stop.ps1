# Agent-scoped Stop hook for the implementer agent.
# copilot:modified  | implementer | 2026-03-19 | test log freshness check in stop hooks
#
# GREEN PHASE GATE (HARD -- blocks implementer from completing if tests fail)
#
# Runs the test suite and blocks the implementer subagent if any test fails.
# This converts the Green phase from a self-asserted claim into a
# machine-verified precondition.
#
# Fires as SubagentStop when the implementer is invoked by the coordinator.
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

# Check if stop hook is already active (prevent infinite loop)
# The input JSON contains stop_hook_active but we read it as raw;
# a simple env-based guard is more reliable for scripts.

$pytest = Get-Command pytest -ErrorAction SilentlyContinue
if (-not $pytest) {
    # Cannot verify -- warn but do not block
    $output = @{
        systemMessage = "implementer:Stop -- pytest not found, Green gate skipped"
    } | ConvertTo-Json -Compress
    Write-Output $output
    exit 0
}

if (-not (Test-Path "tests/")) {
    $output = @{
        systemMessage = "implementer:Stop -- no tests/ directory, Green gate skipped"
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
    $result = "Tests: accepted from test log ($($allEntry.passed)/$($allEntry.total) passed, no code changes since)"
} else {
    $scriptPath = Join-Path (Get-Location) '.github/scripts/run-tests.ps1'
    $result = & $scriptPath -Scope all 2>&1
    $exitCode = $LASTEXITCODE
}

if ($exitCode -eq 0 -or $exitCode -eq 5) {
    # Tests pass -- now check provenance markers on changed .py files
    $changedPy = @()
    try {
        $changedPy = git diff --name-only --cached --diff-filter=AM -- '*.py' 2>$null
        if (-not $changedPy) {
            $changedPy = git diff --name-only HEAD --diff-filter=AM -- '*.py' 2>$null
        }
    } catch {}

    $missingMarkers = @()
    foreach ($f in $changedPy) {
        if ($f -and (Test-Path $f)) {
            $firstLines = Get-Content $f -TotalCount 5 -ErrorAction SilentlyContinue | Out-String
            if ($firstLines -and $firstLines -notmatch 'copilot:(generated|modified)') {
                $missingMarkers += $f
            }
        }
    }

    if ($missingMarkers.Count -gt 0) {
        $fileList = $missingMarkers -join ', '
        $output = @{
            hookSpecificOutput = @{
                hookEventName = "Stop"
                decision = "block"
                reason = "Provenance gate: these changed .py files lack copilot:generated or copilot:modified markers in their first 5 lines: $fileList. Add provenance markers per instructions/provenance.instructions.md before completing."
            }
        } | ConvertTo-Json -Compress -Depth 3
        Write-Output $output
        exit 0
    }

    # Python quality hard gate (only when changed files are under SRC_DIR)
    $changedSrcPy = @($changedPy | Where-Object {
        $_ -and ($_ -match '\.py$') -and (($_ -like "$SRC_DIR/*") -or ($_ -like "$SRC_DIR\\*"))
    })

    if ($changedSrcPy.Count -gt 0) {
        $qualityScript = Join-Path (Get-Location) '.github/scripts/check-python-quality.py'
        if (-not (Test-Path $qualityScript)) {
            $output = @{
                hookSpecificOutput = @{
                    hookEventName = "Stop"
                    decision = "block"
                    reason = "Python quality gate: .github/scripts/check-python-quality.py not found. Cannot verify type hints/docstrings/ignore hygiene."
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
                        reason = "Python quality gate: no Python executable found to run check-python-quality.py"
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
                    reason = "Python quality gate failed (type hints/docstrings/ignore hygiene). Summary: $summary"
                }
            } | ConvertTo-Json -Compress -Depth 3
            Write-Output $output
            exit 0
        }
    }

    # ---------- Atomic ignore commit check ----------
    # Each new type: ignore / pyright: ignore / noqa must be its own standalone commit.
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
                reason = "Atomic ignore commit violation: $($newIgnoreLines.Count) new ignore statements in one commit. Each must be its own standalone atomic commit. Format: '[agent:name] justify ignore: file:line RULE -- reason'"
            }
        } | ConvertTo-Json -Compress -Depth 3
        Write-Output $output
        exit 0
    } elseif ($newIgnoreLines.Count -eq 1 -and $otherAddedLines.Count -gt 0) {
        $output = @{
            hookSpecificOutput = @{
                hookEventName = "Stop"
                decision = "block"
                reason = "Atomic ignore commit violation: new ignore statement mixed with $($otherAddedLines.Count) other code changes. Commit code changes first, then add the ignore in its own standalone commit. Format: '[agent:name] justify ignore: file:line RULE -- reason'"
            }
        } | ConvertTo-Json -Compress -Depth 3
        Write-Output $output
        exit 0
    }

    # All gates pass
    $output = @{
        systemMessage = "implementer:Stop -- Green gate PASS: tests $(if ($fromLog) {'accepted from log'} else {'all pass'}), provenance + python quality verified"
    } | ConvertTo-Json -Compress
    Write-Output $output
    exit 0
} else {
    # Tests fail -- block the implementer from completing
    $summary = ($result | Where-Object { $_ -notmatch '^===' } | Select-Object -Last 3 | Out-String).Trim()
    $output = @{
        hookSpecificOutput = @{
            hookEventName = "Stop"
            decision = "block"
            reason = "Green phase violation: tests are failing. Fix the failing tests before completing. Summary: $summary"
        }
    } | ConvertTo-Json -Compress -Depth 3
    Write-Output $output
    exit 0
}
