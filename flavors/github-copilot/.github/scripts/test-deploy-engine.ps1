# The deploy engine's pytest suite, reachable from the local runner (#395).
#
# A deploy_core.py change ran `run-all-tests.ps1 -Changed`, "widened to every
# suite" and reported 35/35 -- none of which executed the code that changed.
# The pytest suite reached CI only through its own workflow step. This wrapper
# puts it in the sweep without re-implementing it: run-deploy-suite.py owns the
# tolerated skip reasons and the floor under executed tests, so delegating keeps
# those rules single-sourced.
#
# Framework-only: mcp-deploy and run-deploy-suite.py never ship into a project.
# CI excludes this suite from its sweep because the dedicated step already runs
# the same script; running it twice would only double the cost.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir '_suite_env.ps1')

if (-not (Test-AfSourceTree $scriptDir)) {
    Write-Output '  SKIP  deploy engine -- mcp-deploy ships only with the framework, not into a project'
    exit 0
}

$payloadRoot = Split-Path (Split-Path $scriptDir)
$repoRoot = Split-Path (Split-Path $payloadRoot)
$runner = Join-Path $repoRoot '.github/scripts/run-deploy-suite.py'
if (-not (Test-Path $runner)) {
    Write-Output "BLOCKED: $runner not found -- the deploy suite cannot be run from here"
    exit 2
}

# The engine's own venv carries pytest and the package; PATH python only does
# where someone installed them (CI does, via pip install -e mcp-deploy[dev]).
$python = $null
foreach ($c in @(
        (Join-Path $payloadRoot 'mcp-deploy/.venv/Scripts/python.exe'),
        (Join-Path $payloadRoot 'mcp-deploy/.venv/bin/python'))) {
    if (Test-Path $c) { $python = $c; break }
}
if (-not $python) { $python = Get-AfSuitePython $scriptDir }

$ErrorActionPreference = 'Continue'
$probe = if ($python) { & $python -c 'import pytest, af_deploy_mcp' 2>&1 | Out-String } else { 'no Python 3 interpreter' }
if (-not $python -or $LASTEXITCODE -ne 0) {
    # Blocked, not skipped and not passed: the suite asserted nothing, and the
    # cause is the environment rather than the code under test.
    Write-Output "BLOCKED: no interpreter with pytest and af_deploy_mcp -- $($probe.Trim())"
    exit 2
}

& $python $runner
exit $LASTEXITCODE
