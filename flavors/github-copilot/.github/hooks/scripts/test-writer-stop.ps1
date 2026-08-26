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

# Root resolution AND the shared provenance detector both come from here. The
# hand-rolled worktree block this replaced left Test-AfProvenanceMarker
# undefined, and PowerShell abandons the enclosing `if` on a command-not-found
# error, so Gate 2 silently never fired (issue #175).
. "$PSScriptRoot/_common.ps1"
$codeRoot = $AfCodeRoot

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

if (-not (Test-Path (Join-Path $codeRoot 'tests'))) {
    $output = @{
        systemMessage = "test-writer:Stop -- no tests/ directory, Red gate skipped"
    } | ConvertTo-Json -Compress
    Write-Output $output
    exit 0
}

# ---------- Gate 1: Red phase -- new tests must FAIL ----------

Push-Location $codeRoot
$result = & pytest tests/ -q --tb=line --no-header 2>&1
$exitCode = $LASTEXITCODE
Pop-Location

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

# Not every red is a red. A file that cannot be imported (exit 2) or a test that
# errors before it runs -- missing fixture, fixture raising -- never reaches the
# behaviour it claims to guard, and it stays red after a perfect implementation.
# Everything but 0 and 5 used to fall through to "Red phase satisfied", which
# sent the Green phase hunting for a defect that does not exist (issue #123).
#
# Read off the summary line as well as the exit code: a missing fixture reports
# `1 error` and still exits 1, indistinguishable from a genuine failure by exit
# code alone. Measured 2026-08-24.
$summaryLine = ($result | Where-Object { "$_".Trim() } | Select-Object -Last 1 | Out-String).Trim()
if ($exitCode -eq 2 -or $summaryLine -match '\d+ error') {
    $output = @{
        hookSpecificOutput = @{
            hookEventName = "Stop"
            decision      = "block"
            reason        = "Red phase invalid: the suite reported collection or setup ERRORS, not test failures. A test that cannot be collected or set up never reaches the behaviour it claims to guard, and it stays red after a correct implementation. Fix the test construction -- imports, syntax, fixtures, schema-less DataFrames -- so the red comes from an assertion. Summary: $summaryLine"
        }
    } | ConvertTo-Json -Compress -Depth 3
    Write-Output $output
    exit 0
}

# Tests are failing -- Red phase satisfied. Now check provenance.

# ---------- Gate 2: Provenance markers on new test files (H5) ----------

$newTestFiles = & git -C $codeRoot status --porcelain "tests/" 2>$null |
    Where-Object { $_ -match '^\?\? ' -or $_ -match '^A ' } |
    ForEach-Object { ($_ -replace '^.. ', '').Trim('"') } |
    Where-Object { $_ -match '\.py$' }

$missingMarkers = @()
foreach ($f in $newTestFiles) {
    if (Test-Path (Join-Path $codeRoot $f)) {
        if (-not (Test-AfProvenanceMarker -Path (Join-Path $codeRoot $f) -Kind 'generated')) {
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
            reason = "Provenance violation: these new test files carry no 'copilot:generated' marker anywhere: $list. See instructions/provenance.instructions.md for where to put it."
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
