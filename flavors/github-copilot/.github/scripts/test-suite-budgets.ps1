# Regression suite for per-suite runtime budgets.
#
# #334: test-deploy-flags.ps1 spent 708 of its 788 seconds running
# test-hooks.ps1 a second time, nested inside deploy.ps1 -Preflight, and nothing
# noticed for as long as it existed. The fix for that instance is specific; this
# is the general guard.
#
# A static "no suite may execute another suite" check was tried first and does
# not work: deploy.ps1 legitimately *mentions* test-hooks.ps1 in its check list,
# so a filename scan flags the caller even after it stopped executing anything.
# Runtime is the honest signal. A nested re-run is a ~30x event; any sane
# ceiling catches it, on any machine, without parsing anything.
#
# Ceilings are declared in suite-budgets.json and derived from the SLOWER
# environment. This developer machine runs the full sweep in ~2,209s against
# ~1,204s in CI, so a ceiling set from CI timings would fail locally for no
# reason.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$budgetFile = Join-Path $scriptDir 'suite-budgets.json'
$runner = Join-Path $scriptDir 'run-all-tests.ps1'

$results = [ordered]@{}
$details = @{}

function Add-Result {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    $script:results[$Name] = $Ok
    $script:details[$Name] = $Detail
}

# A fixture budget file plus a real run is the only way to prove the ceiling is
# enforced rather than merely declared. The subject is the cheapest passing
# suite, so the control costs seconds.
function Invoke-RunnerWithBudget {
    param([int]$Budget)

    $fixture = Join-Path ([IO.Path]::GetTempPath()) ("af334-budget-" + [Guid]::NewGuid().ToString('N') + ".json")
    $payload = [ordered]@{
        default = $Budget
        suites  = [ordered]@{ 'test-curation-consistency.ps1' = $Budget }
    }
    ($payload | ConvertTo-Json -Depth 4) | Set-Content -Path $fixture -Encoding UTF8

    $out = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $runner `
        -Filter curation-consistency -BudgetFile $fixture 2>&1 | Out-String
    return @{ Output = $out; ExitCode = $LASTEXITCODE }
}

# ── Declaration ───────────────────────────────────────────────────────────

Add-Result 'A1_budget_file_ships_with_the_suites' (Test-Path $budgetFile) $budgetFile

$declared = $null
$parsed = $false
if (Test-Path $budgetFile) {
    try {
        $declared = Get-Content $budgetFile -Raw | ConvertFrom-Json
        $parsed = ($null -ne $declared.default) -and ($null -ne $declared.suites)
    } catch {
        $parsed = $false
    }
}
Add-Result 'A2_budget_file_declares_a_default_and_a_suite_map' $parsed "parsed=$parsed"

$suiteNames = @(Get-ChildItem -Path $scriptDir -Filter 'test-*.ps1' | Select-Object -ExpandProperty Name)
$declaredNames = @()
if ($parsed) { $declaredNames = @($declared.suites.PSObject.Properties.Name) }

# An unlisted suite would silently inherit the default, which is how an
# expensive suite gets added without anyone deciding it may be expensive.
$missing = @($suiteNames | Where-Object { $declaredNames -notcontains $_ })
Add-Result 'A3_every_suite_has_an_explicit_budget' ($missing.Count -eq 0) "missing=$($missing -join ', ')"

$stale = @($declaredNames | Where-Object { $suiteNames -notcontains $_ })
Add-Result 'A4_no_budget_names_a_suite_that_is_gone' ($stale.Count -eq 0) "stale=$($stale -join ', ')"

# A ceiling above the kill timeout can never be reached: the suite is killed
# first and reported as a timeout, so the budget would assert nothing.
$timeout = 0
$runnerText = Get-Content $runner -Raw
$m = [regex]::Match($runnerText, '\[int\]\s*\$TimeoutSeconds\s*=\s*(\d+)')
if ($m.Success) { $timeout = [int]$m.Groups[1].Value }
$overCap = @()
if ($parsed) {
    $overCap = @($declared.suites.PSObject.Properties | Where-Object { [int]$_.Value -ge $timeout } | Select-Object -ExpandProperty Name)
}
Add-Result 'A5_every_budget_is_below_the_kill_timeout' (($timeout -gt 0) -and ($overCap.Count -eq 0)) "timeout=$timeout over=$($overCap -join ', ')"

# ── Enforcement ───────────────────────────────────────────────────────────

$tight = $null
$generous = $null
# Zero, not one second: a 1 s ceiling depends on runner speed and stopped
# tripping in CI on PR 343. Any measured run exceeds zero.
try { $tight = Invoke-RunnerWithBudget -Budget 0 } catch { $tight = @{ Output = "$_"; ExitCode = -1 } }
try { $generous = Invoke-RunnerWithBudget -Budget 9999 } catch { $generous = @{ Output = "$_"; ExitCode = -1 } }

Add-Result 'B1_a_suite_over_its_budget_is_not_reported_as_passed' `
    (($tight.Output -match 'SLOW') -and ($tight.ExitCode -eq 1)) `
    "exit=$($tight.ExitCode)"

# Without this, a runner that reported SLOW unconditionally would satisfy B1.
Add-Result 'B2_a_suite_within_its_budget_still_passes' `
    (($generous.Output -notmatch 'SLOW') -and ($generous.ExitCode -eq 0)) `
    "exit=$($generous.ExitCode)"

Add-Result 'B3_the_report_states_measured_and_allowed_seconds' `
    ($tight.Output -match 'Took [\d.,]+s against a 0s budget') `
    'wording'

# ── Report ────────────────────────────────────────────────────────────────

$passed = 0
foreach ($name in $results.Keys) {
    if ($results[$name]) {
        $passed++
        Write-Host "PASS: $name" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $name" -ForegroundColor Red
        Write-Host "  $($details[$name])" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "----- $passed/$($results.Count) passed -----"
if ($passed -ne $results.Count) { exit 1 }
exit 0
