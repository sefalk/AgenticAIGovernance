# Agent-scoped Stop hook for the implementer agent.
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

$result = & pytest tests/ -q --tb=line --no-header 2>&1
$exitCode = $LASTEXITCODE

if ($exitCode -eq 0 -or $exitCode -eq 5) {
    # Tests pass (or no tests collected) -- Green gate satisfied
    $output = @{
        systemMessage = "implementer:Stop -- Green gate PASS: all tests pass"
    } | ConvertTo-Json -Compress
    Write-Output $output
    exit 0
} else {
    # Tests fail -- block the implementer from completing
    $summary = ($result | Select-Object -Last 3 | Out-String).Trim()
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
