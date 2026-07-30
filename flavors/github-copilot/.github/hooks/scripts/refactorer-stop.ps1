# Agent-scoped Stop hook for the refactorer agent.
#
# REFACTOR PHASE GATES (HARD -- blocks refactorer if tests fail or new files created)
#
# Gate 1: All tests must still pass after refactoring.
# Gate 2: No new files created -- refactoring modifies existing files only.
#         Scoped to .py files under SRC_DIR/ and tests/ to avoid false positives
#         from pre-existing untracked files (notebooks, temp files, etc.).
# Gate 3: Python quality (type hints, docstrings) on changed SRC_DIR/ files.
# Gate 4: Each new type:ignore / pyright:ignore / noqa is its own commit.
# Gate 5: ruff linting on changed files under SRC_DIR/ AND tests/.
#
# Fires as SubagentStop when the refactorer is invoked by the coordinator.
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
$BASE_BRANCH = ''
$confPath = Join-Path $mainRoot '.github/af-env.conf'
if (Test-Path $confPath) {
    $m = Select-String -Path $confPath -Pattern '^SRC_DIR=(.+)$'
    if ($m) { $SRC_DIR = $m.Matches[0].Groups[1].Value.Trim() }
    $b = Select-String -Path $confPath -Pattern '^BASE_BRANCH=(.+)$'
    if ($b) { $BASE_BRANCH = $b.Matches[0].Groups[1].Value.Trim() }
}

# Read stdin (hook input JSON -- required by protocol)
$null = [Console]::In.ReadToEnd()

# ---------- Gate 1: All tests must pass ----------
# A missing test runner disables THIS gate only. Gates 2-5 need neither pytest
# nor a tests/ directory, and exiting here used to take them down too (#12).
$testGateSkipped = $null
if (-not (Get-Command pytest -ErrorAction SilentlyContinue)) {
    $testGateSkipped = 'pytest not found'
} elseif (-not (Test-Path (Join-Path $codeRoot 'tests'))) {
    $testGateSkipped = 'no tests/ directory'
}

# ---------- Test Log Freshness Check ----------
# Accept last run if ALL tests passed AND no code changed since (committed or uncommitted).
# No time limit — change detection is the criterion, not elapsed time.
$testLogPath = Join-Path $mainRoot '.github/test-log.json'
$fromLog = $false
if (-not $testGateSkipped -and (Test-Path $testLogPath)) {
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

if ($testGateSkipped -or $fromLog) {
    $exitCode = 0
} else {
    $scriptPath = Join-Path $mainRoot '.github/scripts/run-tests.ps1'
    Push-Location $codeRoot
    $result = & $scriptPath -Scope all 2>&1
    $exitCode = $LASTEXITCODE
    Pop-Location
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
$statusSrc = & git -C $codeRoot status --porcelain "$SRC_DIR/" 2>$null |
    Where-Object { $_ -match '^\?\? ' } |
    ForEach-Object { ($_ -replace '^.. ', '').Trim('"') } |
    Where-Object { $_ -match '\.py$' }
if ($statusSrc) { $newFiles += $statusSrc }

# Check tests/ for untracked .py files
$statusTests = & git -C $codeRoot status --porcelain "tests/" 2>$null |
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

# ---------- Changed-file sets for Gates 3 and 5 ----------
# Two distinct scopes on purpose:
#   $changedSrcPy  -- production source only. Gate 3 enforces type hints and
#                     NumPy docstrings, which do not apply to test functions.
#   $changedLintPy -- source AND tests. Lint violations in tests/ are real
#                     violations; scoping Gate 5 to SRC_DIR/ let them through.
$changedSrcPy = @()
$changedLintPy = @()
try {
    $changedSrcPy = @(git -C $codeRoot diff --name-only --cached --diff-filter=AM -- "$SRC_DIR/" 2>$null |
        Where-Object { $_ -match '\.py$' })
    if ($changedSrcPy.Count -eq 0) {
        $changedSrcPy = @(git -C $codeRoot diff --name-only HEAD --diff-filter=AM -- "$SRC_DIR/" 2>$null |
            Where-Object { $_ -match '\.py$' })
    }

    $changedLintPy = @(git -C $codeRoot diff --name-only --cached --diff-filter=AM -- "$SRC_DIR/" 'tests/' 2>$null |
        Where-Object { $_ -match '\.py$' })
    if ($changedLintPy.Count -eq 0) {
        $changedLintPy = @(git -C $codeRoot diff --name-only HEAD --diff-filter=AM -- "$SRC_DIR/" 'tests/' 2>$null |
            Where-Object { $_ -match '\.py$' })
    }
} catch {}

# Files committed in an EARLIER phase of this workflow appear in neither diff
# above -- the coordinator commits the test files at the end of the Red phase,
# so they were invisible here and shipped unlinted (issue #13). The unit of
# accountability is the branch delta: what the merge will add.
$inheritedLintPy = @()
$mergeBase = $null
foreach ($ref in @($BASE_BRANCH, "origin/$BASE_BRANCH")) {
    if (-not $BASE_BRANCH) { break }
    $mergeBase = @(git -C $codeRoot merge-base HEAD $ref 2>$null)[0]
    if ($mergeBase) { break }
}
if ($mergeBase) {
    $branchDelta = git -C $codeRoot diff --name-only --diff-filter=AM "$mergeBase..HEAD" -- "$SRC_DIR/" 'tests/' 2>$null
    $inheritedLintPy = @($branchDelta | Where-Object {
        $_ -and ($_ -match '\.py$') -and ($changedLintPy -notcontains $_) -and
        (Test-Path (Join-Path $codeRoot $_))
    })
}

# Resolve Python once -- Gate 3 and Gate 5 both need it. Gate 5 must still run
# when only tests/ changed, so this cannot live inside the Gate 3 branch.
$pythonExe = Join-Path $codeRoot '.venv/Scripts/python.exe'
if (-not (Test-Path $pythonExe)) {
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    $pythonExe = if ($pythonCmd) { $pythonCmd.Source } else { $null }
}

# ---------- Gate 3: Python quality on changed source files ----------

if ($changedSrcPy.Count -gt 0) {
    $qualityScript = Join-Path $mainRoot '.github/scripts/check-python-quality.py'
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

    if (-not $pythonExe) {
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

# ---------- Gate 5: Python linting on changed source AND test files ----------
$lintStatus = 'no python changes'
if ($changedLintPy.Count -gt 0 -or $inheritedLintPy.Count -gt 0) {
    $lintStatus = 'skipped (script/python not available)'
    # Resolve against $mainRoot (where .github/ is deployed), not the cwd the
    # hook happens to inherit -- Get-Location made this gate skip silently.
    $lintScript = Join-Path $mainRoot '.github/scripts/check-python-linting.py'
    if ((Test-Path $lintScript) -and $pythonExe) {
        # cwd must be the code root: check-python-linting.py resolves ruff from
        # ./.venv and walks up from cwd to find .github/af-env.conf.
        Push-Location $codeRoot
        $lintResult = $null
        $lintExit = 0
        if ($changedLintPy.Count -gt 0) {
            $lintResult = & $pythonExe $lintScript --files @($changedLintPy) 2>&1
            $lintExit = $LASTEXITCODE
        }
        # Inherited files are checked separately so the block message can say
        # whose debt this is and which moves are legal.
        $inheritedResult = $null
        $inheritedExit = 0
        if ($lintExit -eq 0 -and $inheritedLintPy.Count -gt 0) {
            $inheritedResult = & $pythonExe $lintScript --files @($inheritedLintPy) 2>&1
            $inheritedExit = $LASTEXITCODE
        }
        Pop-Location
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
        } elseif ($lintExit -eq 1 -or $inheritedExit -eq 1) {
            $output = @{
                hookSpecificOutput = @{
                    hookEventName = "Stop"
                    decision = "block"
                    reason = "Refactor phase blocked: linting gate unavailable because ruff is not installed. Install dev dependencies or run: pip install ruff"
                }
            } | ConvertTo-Json -Compress -Depth 3
            Write-Output $output
            exit 0
        } elseif ($inheritedExit -eq 2) {
            $inheritedSummary = ($inheritedResult | Select-Object -First 15 | Out-String).Trim()
            $output = @{
                hookSpecificOutput = @{
                    hookEventName = "Stop"
                    decision = "block"
                    reason = "Refactor phase violation: linting gate failed on files this branch committed in an EARLIER phase (branch delta vs $BASE_BRANCH). You did not author them in this step, but they ship on merge. Two legal moves: fix them (usually ruff check --fix <files>), or acknowledge each one with '# noqa: RULE  # reason' in its own standalone commit ([agent:name] justify ignore: file:line RULE -- reason). Do not leave them unrecorded. Violations: $inheritedSummary"
                }
            } | ConvertTo-Json -Compress -Depth 3
            Write-Output $output
            exit 0
        } else {
            $lintStatus = if ($inheritedLintPy.Count -gt 0) {
                "clean (incl. $($inheritedLintPy.Count) inherited from earlier phases)"
            } else { 'clean' }
        }
    }
}

# All gates passed
$output = @{
    systemMessage = "refactorer:Stop -- all gates PASS: tests $(if ($testGateSkipped) {"gate skipped ($testGateSkipped)"} elseif ($fromLog) {'accepted from log'} else {'green'}), no new files created, python quality verified, linting: $lintStatus"
} | ConvertTo-Json -Compress
Write-Output $output
exit 0
