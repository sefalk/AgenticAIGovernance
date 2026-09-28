# Regression suite: every shipped CLI option has a production caller (#253).
#
# The same check runs inside test-hooks.ps1, but that suite is scoped to the
# hooks: a new option in scripts/*.py never selected it locally and surfaced
# only in CI (#305, --write-baseline). This suite carries the scripts' scope.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$githubDir = Split-Path -Parent $scriptDir
$checker = Join-Path $scriptDir 'check-cli-callers.py'

. (Join-Path $scriptDir '_suite_env.ps1')
$python = Get-AfSuitePython $scriptDir
if (-not $python) {
    Write-Host 'SKIP: no Python 3 interpreter found; cannot run the CLI caller check.'
    exit 0
}

Write-Output '===== CLI caller tests (issue #253) ====='
if (-not (Test-AfSourceTree $scriptDir)) {
    # deploy.ps1 and deploy.sh pass some options and never ship into a project (#349).
    Write-Output '  SKIP  C1_every_shipped_cli_option_has_a_production_caller -- deploy scripts are callers and do not ship here'
    exit 0
}

$ErrorActionPreference = 'Continue'
$out = & $python $checker $scriptDir $githubDir (Split-Path -Parent $githubDir) 2>&1 | Out-String
$code = $LASTEXITCODE
$ErrorActionPreference = 'Stop'

if ($code -eq 0) {
    Write-Output 'PASS  C1_every_shipped_cli_option_has_a_production_caller'
    Write-Output '----- 1/1 passed -----'
    exit 0
}
Write-Output 'FAIL  C1_every_shipped_cli_option_has_a_production_caller'
foreach ($line in ($out.Trim() -split "`r?`n")) { Write-Output "      $line" }
Write-Output '----- 0/1 passed -----'
exit 1
