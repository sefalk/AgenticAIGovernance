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
. "$PSScriptRoot/hook-utils.ps1"

# Load project config
$SRC_DIR = 'src'
$confPath = Join-Path (Get-Location) '.github/af-env.conf'
if (Test-Path $confPath) {
    $m = Select-String -Path $confPath -Pattern '^SRC_DIR=(.+)$'
    if ($m) { $SRC_DIR = $m.Matches[0].Groups[1].Value.Trim() }
}

# Read stdin (hook input JSON -- required by protocol)
$null = [Console]::In.ReadToEnd()
Write-HookTrace -Hook 'refactorer-stop' -Event 'invoked'

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
    Write-HookTrace -Hook 'refactorer-stop' -Event 'block' -Detail 'tests failing after refactoring'
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

if ($newFiles.Count -gt 0) {\n    Write-HookTrace -Hook 'refactorer-stop' -Event 'block' -Detail \"new files: $($newFiles -join ', ')\"
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

# All gates passed
$output = @{
    systemMessage = "refactorer:Stop -- all gates PASS: tests $(if ($fromLog) {'accepted from log'} else {'green'}), no new files created"
} | ConvertTo-Json -Compress
Write-Output $output
exit 0
