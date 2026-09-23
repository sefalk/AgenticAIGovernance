# Regression suite for scoped local runs.
#
# #334, problem 3: regression.yml has no paths filter and run-all-tests.ps1
# sweeps every test-*.ps1, so a developer runs all 20 suites locally and the PR
# then runs the identical 20 in CI. The second run is the one that counts --
# it is the merge gate -- so the local one is the redundant half.
#
# The trade the user approved: local may go green on the changed paths only,
# because CI still re-tests everything. That is only safe while the mapping is
# honest, which is what this suite is for.
#
# Two deliberate design limits, asserted below:
#   - a changed path that no mapping covers falls back to the FULL sweep, never
#     to nothing, so an incomplete map costs time rather than coverage;
#   - patterns are either a concrete path or a directory ending in /**, so both
#     this suite and the runner can match them with plain string comparison and
#     there is no second glob implementation to drift (#287).
#
# Patterns are written WITHOUT the flavors/github-copilot/ prefix so the same
# file works here and in a project the payload was deployed into, where the
# tree starts at .github/ directly.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$scopeFile = Join-Path $scriptDir 'suite-scope.json'
$runner = Join-Path $scriptDir 'run-all-tests.ps1'
$payloadRoot = Resolve-Path (Join-Path $scriptDir '..\..')

$results = [ordered]@{}
$details = @{}

function Add-Result {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    $script:results[$Name] = $Ok
    $script:details[$Name] = $Detail
}

function Invoke-Selection {
    param([string[]]$Paths)
    # Local: stderr from a native command is a terminating error under Stop.
    $ErrorActionPreference = 'Continue'
    $out = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $runner `
        -ListSelection -ChangedFiles $Paths 2>&1 | Out-String
    return $out
}

# ── Declaration ───────────────────────────────────────────────────────────

$scope = $null
$parsed = $false
if (Test-Path $scopeFile) {
    try {
        $scope = Get-Content $scopeFile -Raw | ConvertFrom-Json
        $parsed = ($null -ne $scope.suites) -and ($null -ne $scope.always) -and ($null -ne $scope.ignore)
    } catch {
        $parsed = $false
    }
}
Add-Result 'S1_scope_file_declares_suites_always_and_ignore' $parsed "parsed=$parsed"

$suiteNames = @(Get-ChildItem -Path $scriptDir -Filter 'test-*.ps1' | Select-Object -ExpandProperty Name)
$mappedNames = @()
$patterns = @()
if ($parsed) {
    $mappedNames = @($scope.suites.PSObject.Properties.Name)
    foreach ($entry in $scope.suites.PSObject.Properties) { $patterns += @($entry.Value) }
    $patterns += @($scope.always)
}

# An unmapped suite would never be selected by a scoped run, which is the
# failure mode that silently removes coverage rather than adding cost.
$unmapped = @($suiteNames | Where-Object { $mappedNames -notcontains $_ })
Add-Result 'S2_every_suite_is_mapped' ($unmapped.Count -eq 0) "unmapped=$($unmapped -join ', ')"

$stale = @($mappedNames | Where-Object { $suiteNames -notcontains $_ })
Add-Result 'S3_no_mapping_names_a_suite_that_is_gone' ($stale.Count -eq 0) "stale=$($stale -join ', ')"

$badShape = @($patterns | Where-Object { $_ -match '\*' -and $_ -notmatch '/\*\*$' })
Add-Result 'S4_patterns_are_a_concrete_path_or_a_directory' ($badShape.Count -eq 0) "bad=$($badShape -join ', ')"

# A pattern pointing at something that no longer exists is a mapping that can
# never fire again -- the suite quietly stops being selected.
$dead = @()
foreach ($p in $patterns) {
    $rel = $p -replace '/\*\*$', ''
    if (-not (Test-Path (Join-Path $payloadRoot $rel))) { $dead += $p }
}
Add-Result 'S5_every_pattern_points_at_something_that_exists' ($dead.Count -eq 0) "dead=$($dead -join ', ')"

# ── Selection ─────────────────────────────────────────────────────────────

$hookChange = Invoke-Selection -Paths @('flavors/github-copilot/.github/hooks/scripts/block-dangerous.ps1')
Add-Result 'S6_a_hook_change_selects_hook_suites_only' `
    (($hookChange -match 'SELECT\s+test-hooks\.ps1') -and ($hookChange -notmatch 'SELECT\s+test-worktree-scripts\.ps1')) `
    'hook change'

# The fallback is the whole reason an incomplete map is survivable.
$unknown = Invoke-Selection -Paths @('some/place/nobody/mapped.txt')
Add-Result 'S7_an_unmapped_path_falls_back_to_the_full_sweep' `
    (($unknown -match 'FALLBACK') -and ($unknown -match 'SELECT\s+test-worktree-scripts\.ps1')) `
    'unmapped path'

$ignored = Invoke-Selection -Paths @('flavors/github-copilot/VERSION')
Add-Result 'S8_a_change_only_in_ignored_paths_selects_nothing' `
    ($ignored -match 'nothing selected') `
    'ignored path'

# VERSION is bumped by the pre-commit hook on every single commit. Without it
# in the ignore list every scoped run would see a changed file that no suite
# covers, hit the fallback, and degrade straight back to a full sweep.
$versionIgnored = $false
if ($parsed) { $versionIgnored = @($scope.ignore) -contains 'VERSION' }
Add-Result 'S9_the_auto_bumped_VERSION_file_is_ignored' $versionIgnored 'VERSION in ignore'

# Changing the selector itself must not be scoped by the selector.
$runnerChange = Invoke-Selection -Paths @('flavors/github-copilot/.github/scripts/run-all-tests.ps1')
Add-Result 'S10_a_change_to_the_runner_selects_every_suite' `
    (($runnerChange -match 'SELECT\s+test-worktree-scripts\.ps1') -and ($runnerChange -notmatch 'FALLBACK')) `
    'runner change'

# Editing a suite must run that suite. Without this the map would need 22
# self-referential entries, and forgetting one would send every edit to a suite
# through the fallback.
$selfChange = Invoke-Selection -Paths @('flavors/github-copilot/.github/scripts/test-retry-economy.ps1')
Add-Result 'S11_editing_a_suite_selects_that_suite' `
    (($selfChange -match 'SELECT\s+test-retry-economy\.ps1') -and ($selfChange -notmatch 'FALLBACK') -and ($selfChange -notmatch 'SELECT\s+test-hooks\.ps1')) `
    'self change'

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
