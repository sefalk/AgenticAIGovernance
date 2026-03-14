# Agent-scoped Stop hook for the refactorer agent.
#
# REFACTOR PHASE GATES (HARD -- blocks refactorer if tests fail or new files created)
#
# Gate 1: All tests must still pass after refactoring.
# Gate 2: No new files created -- refactoring modifies existing files only.
#         Scoped to .py files under mpusage/ and tests/ to avoid false positives
#         from pre-existing untracked files (notebooks, temp files, etc.).
#
# Fires as SubagentStop when the refactorer is invoked by the coordinator.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

$ErrorActionPreference = 'SilentlyContinue'

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

$result = & pytest tests/ -q --tb=line --no-header 2>&1
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0 -and $exitCode -ne 5) {
    $summary = ($result | Select-Object -Last 3 | Out-String).Trim()
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

# ---------- Gate 2: No new .py files under mpusage/ or tests/ ----------

$newFiles = @()

# Check mpusage/ for untracked .py files
$statusMpusage = & git status --porcelain "mpusage/" 2>$null |
    Where-Object { $_ -match '^\?\? ' } |
    ForEach-Object { ($_ -replace '^.. ', '').Trim('"') } |
    Where-Object { $_ -match '\.py$' }
if ($statusMpusage) { $newFiles += $statusMpusage }

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

# All gates passed
$output = @{
    systemMessage = "refactorer:Stop -- all gates PASS: tests green, no new files created"
} | ConvertTo-Json -Compress
Write-Output $output
exit 0
