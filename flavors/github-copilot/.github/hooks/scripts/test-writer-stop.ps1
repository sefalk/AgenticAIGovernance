# Agent-scoped Stop hook for the test-writer agent.
#
# RED PHASE GATE (HARD -- blocks test-writer if new tests do NOT fail)
#
# The Red phase requires that all newly written tests FAIL against the
# existing production code. If tests pass, the test-writer has not
# expressed a genuine requirement gap.
#
# Also checks provenance markers on newly created test files (H5).
#
# Fires as SubagentStop when the test-writer is invoked by the coordinator.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

$ErrorActionPreference = 'SilentlyContinue'

# Read stdin (hook input JSON -- required by protocol)
$null = [Console]::In.ReadToEnd()

$pytest = Get-Command pytest -ErrorAction SilentlyContinue
if (-not $pytest) {
    $output = @{
        systemMessage = "test-writer:Stop -- pytest not found, Red gate skipped"
    } | ConvertTo-Json -Compress
    Write-Output $output
    exit 0
}

if (-not (Test-Path "tests/")) {
    $output = @{
        systemMessage = "test-writer:Stop -- no tests/ directory, Red gate skipped"
    } | ConvertTo-Json -Compress
    Write-Output $output
    exit 0
}

# ---------- Gate 1: Red phase -- new tests must FAIL ----------

$result = & pytest tests/ -q --tb=line --no-header 2>&1
$exitCode = $LASTEXITCODE

# Exit code 0 = all tests pass → Red phase violation (tests should fail)
# Exit code 1 = some tests fail → Red phase satisfied
# Exit code 5 = no tests collected → skip (nothing to verify)
if ($exitCode -eq 0) {
    $output = @{
        hookSpecificOutput = @{
            hookEventName = "Stop"
            decision = "block"
            reason = "Red phase violation: all tests PASS. New tests must FAIL against the existing production code to express a genuine requirement gap. Ensure your tests assert behaviour that is not yet implemented."
        }
    } | ConvertTo-Json -Compress -Depth 3
    Write-Output $output
    exit 0
}

if ($exitCode -eq 5) {
    $output = @{
        systemMessage = "test-writer:Stop -- no tests collected, Red gate skipped"
    } | ConvertTo-Json -Compress
    Write-Output $output
    exit 0
}

# Tests are failing -- Red phase satisfied. Now check provenance.

# ---------- Gate 2: Provenance markers on new test files (H5) ----------

$newTestFiles = & git status --porcelain "tests/" 2>$null |
    Where-Object { $_ -match '^\?\? ' -or $_ -match '^A ' } |
    ForEach-Object { ($_ -replace '^.. ', '').Trim('"') } |
    Where-Object { $_ -match '\.py$' }

$missingMarkers = @()
foreach ($f in $newTestFiles) {
    if (Test-Path $f) {
        $header = Get-Content $f -TotalCount 5 -ErrorAction SilentlyContinue
        $headerText = $header -join "`n"
        if ($headerText -notmatch 'copilot:generated') {
            $missingMarkers += $f
        }
    }
}

if ($missingMarkers.Count -gt 0) {
    $list = $missingMarkers -join ', '
    $output = @{
        hookSpecificOutput = @{
            hookEventName = "Stop"
            decision = "block"
            reason = "Provenance violation: new test files missing 'copilot:generated' marker in first 5 lines: $list"
        }
    } | ConvertTo-Json -Compress -Depth 3
    Write-Output $output
    exit 0
}

# All gates passed
$summary = ($result | Select-Object -Last 1 | Out-String).Trim()
$output = @{
    systemMessage = "test-writer:Stop -- Red gate PASS: tests are failing as expected. Provenance OK. Summary: $summary"
} | ConvertTo-Json -Compress
Write-Output $output
exit 0
