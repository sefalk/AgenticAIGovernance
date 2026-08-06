# Regression tests for the canonical test runner (run-tests.ps1 / run-tests.sh).
#
# Covers issue #73, which has two independent halves:
#
#   1. Argument mangling (Windows only). A scope path carrying a trailing
#      separator becomes "...\tests\" after Join-Path. PowerShell quotes the
#      argument because the workspace path contains spaces, and the CRT argv
#      parser reads the resulting \" as an escaped quote -- it loses the closing
#      quote and swallows every following argument into argv[1]. pytest then
#      collects 0 tests. Only reproducible from a path containing spaces, which
#      is why it survived (every default OneDrive path contains spaces).
#
#   2. Evidence integrity (both platforms). When the runner itself fails --
#      wrong interpreter, pytest not installed, usage error -- stdout is empty,
#      no summary line parses, and the runner writes passed/failed/errors = 0 to
#      test-log.json. A consumer reading "failed: 0" concludes green for a run
#      that never executed a single test. This half is NOT Windows-specific.
#
# Run from anywhere:
#   powershell -File .github/scripts/test-run-tests.ps1
# Exits non-zero if any scenario fails (CI-friendly).
$ErrorActionPreference = 'Continue'

$scriptDir   = Split-Path -Parent $PSCommandPath
$runTestsPs1 = (Resolve-Path (Join-Path $scriptDir 'run-tests.ps1')).Path
$runTestsSh  = (Resolve-Path (Join-Path $scriptDir 'run-tests.sh')).Path
$repoRootAF  = (Resolve-Path (Join-Path $scriptDir '..' | Join-Path -ChildPath '..')).Path

# Resolve a real Python 3 interpreter (skip the Windows Store alias by probing).
function Resolve-Python {
    foreach ($c in @((Join-Path $repoRootAF '.venv/Scripts/python.exe'),
                     (Join-Path $repoRootAF '.venv/bin/python'))) {
        if (Test-Path $c) { return @($c) }
    }
    foreach ($name in @('python3', 'python')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) {
            $v = & $cmd.Source --version 2>&1
            if ($LASTEXITCODE -eq 0 -and $v -match 'Python 3') { return @($cmd.Source) }
        }
    }
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) { return @($py.Source, '-3') }
    return $null
}

# @(...) is required: PowerShell unwraps a single-element array on return, so
# a bare assignment would yield a string and $python[0] would be a character.
$python = @(Resolve-Python)
if ($python.Count -eq 0 -or -not $python[0]) {
    Write-Host 'SKIP: no Python 3 interpreter found; cannot run test-runner tests.'
    exit 0
}
$pyExe  = $python[0]
$pyPre  = if ($python.Count -gt 1) { $python[1..($python.Count - 1)] } else { @() }

# A workspace path that CONTAINS A SPACE -- mandatory, the defect is invisible
# without one.
function New-SpacedFixture([string]$tag) {
    $p = Join-Path ([IO.Path]::GetTempPath()) ("af rt $tag " + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $p -Force | Out-Null
    return $p
}

# ---- production values, read from the shipped scripts (never hardcoded) ----

# run-tests.ps1: $scopeMap = @{ 'all' = '...'; ... }
function Get-Ps1ScopeMap {
    $text  = Get-Content $runTestsPs1 -Raw
    $block = [regex]::Match($text, '\$scopeMap\s*=\s*@\{(.*?)\n\}', 'Singleline')
    if (-not $block.Success) { return $null }
    $map = @{}
    foreach ($m in [regex]::Matches($block.Groups[1].Value, "'([a-z]+)'\s*=\s*'([^']*)'")) {
        $map[$m.Groups[1].Value] = $m.Groups[2].Value
    }
    return $map
}

# run-tests.sh: case "$SCOPE" in  all) TEST_PATH="$WORKSPACE_ROOT/tests/" ;;
function Get-ShScopeMap {
    $text = Get-Content $runTestsSh -Raw
    $map  = @{}
    foreach ($m in [regex]::Matches($text, '(?m)^\s*([a-z]+)\)\s*TEST_PATH="([^"]*)"')) {
        $map[$m.Groups[1].Value] = $m.Groups[2].Value
    }
    return $map
}

function Invoke-Py([string[]]$argv) {
    if ($pyPre.Count -gt 0) { return & $pyExe @pyPre @argv }
    return & $pyExe @argv
}

$results   = [ordered]@{}
$details   = @{}
$fixtures  = @()
$expected  = @('all', 'domain', 'adapters', 'properties', 'contracts')

try {
    # ---------------------------------------------------------------------
    # A: no scope path in run-tests.ps1 carries a trailing separator.
    # ---------------------------------------------------------------------
    $psMap = Get-Ps1ScopeMap
    if (-not $psMap) {
        $results['A_ps1_scopemap_no_trailing_separator'] = $false
        $details['A_ps1_scopemap_no_trailing_separator'] = 'could not parse $scopeMap from run-tests.ps1'
    } else {
        $bad = @($psMap.Keys | Where-Object { $psMap[$_] -match '[\\/]$' } | ForEach-Object { "$_='$($psMap[$_])'" })
        $missing = @($expected | Where-Object { -not $psMap.ContainsKey($_) })
        $results['A_ps1_scopemap_no_trailing_separator'] = ($bad.Count -eq 0 -and $missing.Count -eq 0)
        $details['A_ps1_scopemap_no_trailing_separator'] = "trailing: [$($bad -join ', ')] missing: [$($missing -join ', ')]"
    }

    # ---------------------------------------------------------------------
    # B: same invariant for run-tests.sh. Harmless on Linux, but the two
    #    runners must not drift -- and the invariant is the contract.
    # ---------------------------------------------------------------------
    $shMap = Get-ShScopeMap
    $shScopes = @($shMap.Keys | Where-Object { $expected -contains $_ })
    if ($shScopes.Count -ne $expected.Count) {
        $results['B_sh_scopemap_no_trailing_separator'] = $false
        $details['B_sh_scopemap_no_trailing_separator'] = "parsed scopes: [$($shScopes -join ', ')]"
    } else {
        $bad = @($shScopes | Where-Object { $shMap[$_] -match '[\\/]$' } | ForEach-Object { "$_='$($shMap[$_])'" })
        $results['B_sh_scopemap_no_trailing_separator'] = ($bad.Count -eq 0)
        $details['B_sh_scopemap_no_trailing_separator'] = "trailing: [$($bad -join ', ')]"
    }

    # ---------------------------------------------------------------------
    # C: the mechanism itself. Build the argument vector exactly as the runner
    #    does, from a space-containing root, using the SHIPPED scope value, and
    #    assert the following arguments survive as separate argv entries.
    #    This is what actually reaches pytest.
    # ---------------------------------------------------------------------
    $fx = New-SpacedFixture 'argv'; $fixtures += $fx
    $dump = Join-Path $fx 'argvdump.py'
    Set-Content -Path $dump -Encoding ascii -Value @'
import sys
for a in sys.argv[1:]:
    print(a)
'@
    foreach ($scope in $expected) {
        $key = "C_argv_intact_scope_$scope"
        if (-not $psMap -or -not $psMap.ContainsKey($scope)) {
            $results[$key] = $false; $details[$key] = 'scope missing from $scopeMap'; continue
        }
        $target = Join-Path $fx $psMap[$scope]
        $out    = @(Invoke-Py (@($dump, $target, '--tb=long', '-q', '--no-header')))
        $ok     = ($out.Count -eq 4) -and ($out[1] -eq '--tb=long') -and ($out[3] -eq '--no-header')
        $results[$key] = $ok
        $details[$key] = "argv count=$($out.Count) argv[1]='$($out[0])'"
    }

    # ---------------------------------------------------------------------
    # D-F: evidence integrity. A runner that never executed a test must not
    #      leave a log entry that reads as a passing run.
    #
    #      The fixture is a real venv created WITHOUT pip, so `python -m pytest`
    #      fails with ModuleNotFoundError: empty stdout, non-zero exit, nothing
    #      to parse. That is precisely the shape produced by the argv defect,
    #      by a missing dependency, or by a usage error -- on any platform.
    # ---------------------------------------------------------------------
    $ws = New-SpacedFixture 'log'; $fixtures += $ws
    New-Item -ItemType Directory -Path (Join-Path $ws '.github/scripts') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $ws 'tests/domain')     -Force | Out-Null
    Copy-Item $runTestsPs1 (Join-Path $ws '.github/scripts/run-tests.ps1')

    Invoke-Py @('-m', 'venv', '--without-pip', (Join-Path $ws '.venv')) *> $null
    $fxPython = Join-Path $ws '.venv/Scripts/python.exe'
    if (-not (Test-Path $fxPython)) { $fxPython = Join-Path $ws '.venv/bin/python' }

    if (-not (Test-Path $fxPython)) {
        foreach ($k in @('D_failed_run_not_logged_as_zero_failures',
                         'E_failed_run_marked_as_error',
                         'F_runner_failure_surfaced_to_console')) {
            $results[$k] = $false; $details[$k] = 'venv fixture could not be created'
        }
    } else {
        $runnerOut = & (Join-Path $ws '.github/scripts/run-tests.ps1') -Scope domain 2>&1
        $runnerTxt = ($runnerOut | Out-String)
        $logPath   = Join-Path $ws '.github/test-log.json'
        $entry     = $null
        if (Test-Path $logPath) {
            try { $entry = (Get-Content $logPath -Raw | ConvertFrom-Json).domain } catch { $entry = $null }
        }

        # D: the core lie. No entry may claim zero failures for a run that
        #    executed nothing. Either no entry at all, or a non-zero/absent
        #    failure count -- but never "failed: 0" next to a non-zero exit.
        $lies = ($null -ne $entry) -and ($entry.failed -eq 0) -and ($entry.total -eq 0) -and ($entry.exit_code -ne 0)
        $results['D_failed_run_not_logged_as_zero_failures'] = (-not $lies)
        $details['D_failed_run_not_logged_as_zero_failures'] =
            if ($null -eq $entry) { 'no entry written' }
            else { "failed=$($entry.failed) total=$($entry.total) exit_code=$($entry.exit_code)" }

        # E: the entry is positively labelled as a runner error, so a consumer
        #    does not have to infer it from exit_code.
        $results['E_failed_run_marked_as_error'] = ($null -ne $entry) -and ($entry.status -eq 'error')
        $details['E_failed_run_marked_as_error'] = "status=$($entry.status)"

        # F: the underlying cause is visible to the caller instead of being
        #    swallowed by the stderr redirect.
        $results['F_runner_failure_surfaced_to_console'] = ($runnerTxt -match 'pytest' -and $runnerTxt -match 'ERROR')
        $details['F_runner_failure_surfaced_to_console'] = ($runnerTxt -replace '\s+', ' ').Trim()
    }
}
finally {
    foreach ($f in $fixtures) { Remove-Item $f -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host '===== test-runner regression tests (issue #73) ====='
$allPass = $true
foreach ($k in $results.Keys) {
    if ($results[$k]) {
        Write-Host ("PASS  {0}" -f $k)
    } else {
        $allPass = $false
        Write-Host ("FAIL  {0}" -f $k)
        if ($details[$k]) { Write-Host ("      {0}" -f $details[$k]) }
    }
}
$passCount = @($results.Values | Where-Object { $_ }).Count
Write-Host ("----- {0}/{1} passed -----" -f $passCount, $results.Count)
if (-not $allPass) { exit 1 }
exit 0
