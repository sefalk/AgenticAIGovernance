# Agent-scoped Stop hook for the implementer agent.
#
# GREEN PHASE GATE (HARD -- blocks implementer from completing if tests fail)
#
# Runs the test suite and blocks the implementer subagent if any test fails.
# This converts the Green phase from a self-asserted claim into a
# machine-verified precondition.
#
# Further hard gates: provenance markers, python quality (SRC_DIR/), atomic
# ignore commits, and ruff linting (SRC_DIR/ AND tests/). Linting is mirrored
# here from refactorer-stop because the Refactor step is optional.
#
# Fires as SubagentStop when the implementer is invoked by the coordinator.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

$ErrorActionPreference = 'SilentlyContinue'

# Worktree-aware path resolution (see ideas/feature-git-worktrees.md §12).
# $mainRoot: main checkout where .github/ is deployed (derived from script location).
# $codeRoot: active worktree if .active-worktree sentinel exists, else $mainRoot.
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

if (-not (Test-Path (Join-Path $codeRoot 'tests'))) {
    $output = @{
        systemMessage = "implementer:Stop -- no tests/ directory, Green gate skipped"
    } | ConvertTo-Json -Compress
    Write-Output $output
    exit 0
}

# ---------- Test Log Freshness Check ----------
# Accept last run if ALL tests passed AND no code changed since (committed or uncommitted).
# No time limit — change detection is the criterion, not elapsed time.
$testLogPath = Join-Path $mainRoot '.github/test-log.json'
$fromLog = $false
if (Test-Path $testLogPath) {
    try {
        $log = Get-Content $testLogPath -Raw | ConvertFrom-Json
        $allEntry = $null
        if ($log.PSObject.Properties.Name -contains 'all') { $allEntry = $log.all }
        if ($allEntry -and $allEntry.exit_code -eq 0 -and $allEntry.last_run) {
            $commitsSince = git -C $codeRoot log --oneline --after="$($allEntry.last_run)" -- "$SRC_DIR/" 'tests/' 2>$null
            $uncommitted = git -C $codeRoot diff --name-only HEAD -- "$SRC_DIR/" 'tests/' 2>$null
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
    $scriptPath = Join-Path $mainRoot '.github/scripts/run-tests.ps1'
    Push-Location $codeRoot
    $result = & $scriptPath -Scope all 2>&1
    $exitCode = $LASTEXITCODE
    Pop-Location
}

if ($exitCode -eq 0 -or $exitCode -eq 5) {
    # Tests pass -- now check provenance markers on changed .py files
    $changedPy = @()
    try {
        $changedPy = git -C $codeRoot diff --name-only --cached --diff-filter=AM -- '*.py' 2>$null
        if (-not $changedPy) {
            $changedPy = git -C $codeRoot diff --name-only HEAD --diff-filter=AM -- '*.py' 2>$null
        }
    } catch {}

    $missingMarkers = @()
    foreach ($f in $changedPy) {
        if ($f -and (Test-Path (Join-Path $codeRoot $f))) {
            $firstLines = Get-Content (Join-Path $codeRoot $f) -TotalCount 5 -ErrorAction SilentlyContinue | Out-String
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

    # Linting scope is wider than the quality scope: type hints and NumPy
    # docstrings do not apply to test functions, but ruff violations in tests/
    # are real violations.
    $changedLintPy = @($changedPy | Where-Object {
        $_ -and ($_ -match '\.py$') -and (
            ($_ -like "$SRC_DIR/*") -or ($_ -like "$SRC_DIR\\*") -or
            ($_ -like 'tests/*') -or ($_ -like 'tests\\*')
        )
    })

    # Resolve Python once -- the quality gate and the linting gate both need it.
    $pythonExe = Join-Path $codeRoot '.venv/Scripts/python.exe'
    if (-not (Test-Path $pythonExe)) {
        $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
        $pythonExe = if ($pythonCmd) { $pythonCmd.Source } else { $null }
    }

    if ($changedSrcPy.Count -gt 0) {
        $qualityScript = Join-Path $mainRoot '.github/scripts/check-python-quality.py'
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

        if (-not $pythonExe) {
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

        Push-Location $codeRoot
        $qualityResult = & $pythonExe $qualityScript --files @($changedSrcPy) 2>&1
        $qualityExit = $LASTEXITCODE
        Pop-Location
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

    # ---------- Linting hard gate (source AND tests) ----------
    # Mirrors refactorer-stop Gate 5. The Refactor step is optional, so binding
    # linting to it alone meant "no refactorer => no lint at all" (issue #6).
    $lintStatus = 'no python changes'
    if ($changedLintPy.Count -gt 0) {
        $lintStatus = 'skipped (script/python not available)'
        $lintScript = Join-Path $mainRoot '.github/scripts/check-python-linting.py'
        if ((Test-Path $lintScript) -and $pythonExe) {
            # cwd must be the code root: check-python-linting.py resolves ruff
            # from ./.venv and walks up from cwd to find .github/af-env.conf.
            Push-Location $codeRoot
            $lintResult = & $pythonExe $lintScript --files @($changedLintPy) 2>&1
            $lintExit = $LASTEXITCODE
            Pop-Location
            if ($lintExit -eq 2) {
                $lintSummary = ($lintResult | Select-Object -First 15 | Out-String).Trim()
                $output = @{
                    hookSpecificOutput = @{
                        hookEventName = "Stop"
                        decision = "block"
                        reason = "Green phase violation: linting gate failed. Fix with: ruff check --fix <files>. Violations: $lintSummary"
                    }
                } | ConvertTo-Json -Compress -Depth 3
                Write-Output $output
                exit 0
            } elseif ($lintExit -eq 1) {
                $output = @{
                    hookSpecificOutput = @{
                        hookEventName = "Stop"
                        decision = "block"
                        reason = "Green phase blocked: linting gate unavailable because ruff is not installed. Install dev dependencies or run: pip install ruff"
                    }
                } | ConvertTo-Json -Compress -Depth 3
                Write-Output $output
                exit 0
            } else {
                $lintStatus = 'clean'
            }
        }
    }

    # ---------- Atomic ignore commit check ----------
    # Each new type: ignore / pyright: ignore / noqa must be its own standalone commit.
    $diffLines = @()
    try {
        $diffLines = git -C $codeRoot diff --cached -- '*.py' 2>$null
        if (-not $diffLines) { $diffLines = git -C $codeRoot diff HEAD -- '*.py' 2>$null }
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
        systemMessage = "implementer:Stop -- Green gate PASS: tests $(if ($fromLog) {'accepted from log'} else {'all pass'}), provenance + python quality verified, linting: $lintStatus"
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
