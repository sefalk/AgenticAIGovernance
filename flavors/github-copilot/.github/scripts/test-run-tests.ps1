# Regression tests for the canonical test runner (run-tests.ps1 / run-tests.sh).
#
# Covers issues #73, #93 and #179. All three are the same class: the runner
# writes an artifact that looks authoritative and is wrong, and exits 0 while
# doing it.
#
# #179 -- the log entry was built only after pytest returned. A run that was
#         interrupted (terminal closed, agent cancelled, machine slept) left
#         the PREVIOUS entry in place, still saying status ok. Nothing
#         distinguished it from a fresh green result, so the next reader
#         skipped the suite on the strength of a run that never finished.
#
# #93 -- the test log is documented as a cumulative merge across scopes. The
#        read used `ConvertFrom-Json -AsHashtable`, which exists only in
#        PowerShell 6+. On 5.1 -- the default host for the shipped VS Code
#        tasks -- it throws, the catch resets the accumulator, and every run
#        writes a log holding only the scope that just ran. The property has to
#        be stated across TWO runs: a case that checks the scope just run
#        passes either way and never observes the bug.
#
# Issue #73 has two independent halves:
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
# without one. Self-registering, so a fixture abandoned half-built is still
# cleaned up.
function New-SpacedFixture([string]$tag) {
    $p = Join-Path ([IO.Path]::GetTempPath()) ("af rt $tag " + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $p -Force | Out-Null
    $script:fixtures += $p
    return $p
}

# A workspace that runs the SHIPPED run-tests.ps1 against a fake pytest module.
# A real venv is unavoidable: the runner resolves .venv/Scripts/python.exe and
# exits before anything else if it is absent. Returns $null if the fixture
# could not be built, so a missing prerequisite fails the case rather than
# passing it vacuously.
function New-FakePytestWorkspace([string]$tag) {
    $ws = New-SpacedFixture $tag
    New-Item -ItemType Directory -Path (Join-Path $ws '.github/scripts') -Force | Out-Null
    foreach ($d in @('tests', 'tests/domain', 'tests/contracts')) {
        New-Item -ItemType Directory -Path (Join-Path $ws $d) -Force | Out-Null
    }
    Copy-Item $runTestsPs1 (Join-Path $ws '.github/scripts/run-tests.ps1')
    Invoke-Py @('-m', 'venv', '--without-pip', (Join-Path $ws '.venv')) *> $null

    $fxPy = Join-Path $ws '.venv/Scripts/python.exe'
    if (-not (Test-Path $fxPy)) { $fxPy = Join-Path $ws '.venv/bin/python' }
    if (-not (Test-Path $fxPy)) { return $null }

    $site = (& $fxPy -c "import sysconfig; print(sysconfig.get_paths()['purelib'])" 2>$null)
    if (-not $site -or -not (Test-Path $site)) { return $null }

    $pkg = Join-Path $site 'pytest'
    New-Item -ItemType Directory -Path $pkg -Force | Out-Null
    Set-Content -Path (Join-Path $pkg '__init__.py') -Value '' -Encoding ascii
    Set-Content -Path (Join-Path $pkg '__main__.py') -Encoding ascii -Value @'
import json, os, sys
_p = os.environ.get('AF_FAKE_PYTEST_ARGV')
if _p:
    with open(_p, 'w') as fh:
        json.dump(sys.argv[1:], fh)
_s = os.environ.get('AF_FAKE_PYTEST_LOGSNAP')
if _s:
    # Copy the log as it stands WHILE the runner is blocked on pytest. This is
    # the only moment an interrupted run can be observed without a race.
    try:
        with open(os.path.join('.github', 'test-log.json')) as src:
            _t = src.read()
        with open(_s, 'w') as dst:
            dst.write(_t)
    except OSError:
        pass
print('3 passed in 0.42s')
'@
    return $ws
}

function Get-LogScopes([string]$logPath) {
    if (-not (Test-Path $logPath)) { return @() }
    try {
        $obj = Get-Content $logPath -Raw | ConvertFrom-Json
        return @($obj.PSObject.Properties.Name)
    } catch {
        return @()
    }
}

# Block comments and whole-line comments are removed before scanning for
# forbidden constructs: a guard that punishes explaining why a construct is
# absent would delete its own documentation. A trailing comment on a code line
# still counts -- keeping the cut simple avoids the false negative that a `#`
# inside a string literal would otherwise create.
function Remove-PsComments([string]$text) {
    $noBlocks = [regex]::Replace($text, '(?s)<#.*?#>', '')
    return (($noBlocks -split "`n" | Where-Object { $_.TrimStart() -notmatch '^#' }) -join "`n")
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
    $fx = New-SpacedFixture 'argv'
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
    $ws = New-SpacedFixture 'log'
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
        #    swallowed by the stderr redirect. Asserting the interpreter's own
        #    words, not just "an error happened" -- a generic match would also
        #    pass if stderr were still discarded.
        $results['F_runner_failure_surfaced_to_console'] =
            ($runnerTxt -match 'ERROR: pytest did not run') -and ($runnerTxt -match 'No module named')
        $details['F_runner_failure_surfaced_to_console'] = ($runnerTxt -replace '\s+', ' ').Trim()
    }

    # ---------------------------------------------------------------------
    # G: end-to-end success path through the real script. A fake pytest module
    #    inside the fixture venv records the argument vector it received and
    #    prints a summary line. This proves three things at once that the
    #    isolated checks above cannot: the scope path arrives intact through
    #    the production code, the new stderr redirect did not break stdout
    #    capture, and a genuine run is still recorded as status=ok.
    # ---------------------------------------------------------------------
    $ws2 = New-SpacedFixture 'ok'
    New-Item -ItemType Directory -Path (Join-Path $ws2 '.github/scripts') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $ws2 'tests') -Force | Out-Null
    Copy-Item $runTestsPs1 (Join-Path $ws2 '.github/scripts/run-tests.ps1')
    Invoke-Py @('-m', 'venv', '--without-pip', (Join-Path $ws2 '.venv')) *> $null
    $fxPython2 = Join-Path $ws2 '.venv/Scripts/python.exe'
    if (-not (Test-Path $fxPython2)) { $fxPython2 = Join-Path $ws2 '.venv/bin/python' }

    $sitePkgs = $null
    if (Test-Path $fxPython2) {
        $sitePkgs = (& $fxPython2 -c "import sysconfig; print(sysconfig.get_paths()['purelib'])" 2>$null)
    }
    if (-not $sitePkgs -or -not (Test-Path $sitePkgs)) {
        foreach ($k in @('G_success_path_argv_intact', 'G_success_path_recorded_as_ok')) {
            $results[$k] = $false; $details[$k] = 'fake-pytest fixture could not be created'
        }
    } else {
        $fakePkg = Join-Path $sitePkgs 'pytest'
        New-Item -ItemType Directory -Path $fakePkg -Force | Out-Null
        Set-Content -Path (Join-Path $fakePkg '__init__.py') -Value '' -Encoding ascii
        Set-Content -Path (Join-Path $fakePkg '__main__.py') -Encoding ascii -Value @'
import json, os, sys
with open(os.environ['AF_FAKE_PYTEST_ARGV'], 'w') as fh:
    json.dump(sys.argv[1:], fh)
print('3 passed in 0.42s')
'@
        $argvOut = Join-Path $ws2 'received-argv.json'
        $env:AF_FAKE_PYTEST_ARGV = $argvOut
        try {
            & (Join-Path $ws2 '.github/scripts/run-tests.ps1') -Scope all *> $null
        } finally {
            Remove-Item Env:AF_FAKE_PYTEST_ARGV -ErrorAction SilentlyContinue
        }

        # Explicit cast: ConvertFrom-Json emits a JSON array as a single object
        # in PS 5.1, so @(...) would wrap it instead of unrolling it.
        $recv = @()
        if (Test-Path $argvOut) { $recv = [string[]](Get-Content $argvOut -Raw | ConvertFrom-Json) }
        $wantPath = (Join-Path $ws2 'tests')
        $results['G_success_path_argv_intact'] =
            ($recv.Count -ge 4) -and ($recv[0] -eq $wantPath) -and ($recv -contains '--no-header')
        $details['G_success_path_argv_intact'] = "received=[$($recv -join ' | ')]"

        $entry2 = $null
        $log2 = Join-Path $ws2 '.github/test-log.json'
        if (Test-Path $log2) {
            try { $entry2 = (Get-Content $log2 -Raw | ConvertFrom-Json).all } catch { $entry2 = $null }
        }
        $results['G_success_path_recorded_as_ok'] =
            ($null -ne $entry2) -and ($entry2.status -eq 'ok') -and ($entry2.passed -eq 3) -and ($entry2.exit_code -eq 0)
        $details['G_success_path_recorded_as_ok'] = "status=$($entry2.status) passed=$($entry2.passed) exit_code=$($entry2.exit_code)"
    }

    # ---------------------------------------------------------------------
    # H-J (#93): the log is a cumulative merge, and a log the runner cannot
    #            read is not replaced in silence.
    #
    #            One fixture, used four times in sequence. Each block leaves
    #            the log in the state the next one needs.
    # ---------------------------------------------------------------------
    $hKeys = @('H1_merge_survives_a_second_scope',
               'H2_foreign_entry_survives_with_its_values',
               'J1_unreadable_log_is_announced',
               'J2_unreadable_log_is_preserved',
               'J3_absent_log_is_not_announced')
    $wsM = New-FakePytestWorkspace 'merge'
    if (-not $wsM) {
        foreach ($k in $hKeys) { $results[$k] = $false; $details[$k] = 'fake-pytest fixture could not be created' }
    } else {
        $runner = Join-Path $wsM '.github/scripts/run-tests.ps1'
        $logM   = Join-Path $wsM '.github/test-log.json'

        # H1: two runs of different scopes. The second must not evict the
        #     first. A case that inspects only the scope just run passes with
        #     the defect present, which is why the assertion spans two runs.
        & $runner -Scope domain    *> $null
        & $runner -Scope contracts *> $null
        $scopes = Get-LogScopes $logM
        $results['H1_merge_survives_a_second_scope'] =
            ($scopes -contains 'domain') -and ($scopes -contains 'contracts')
        $details['H1_merge_survives_a_second_scope'] = "scopes=[$($scopes -join ', ')]"

        # H2: an entry this runner did not write survives intact -- keys AND
        #     values. The two runners share the file, so a merge that keeps
        #     the name and drops the numbers is no merge.
        Set-Content -Path $logM -Encoding utf8 -Value @'
{
  "properties": {
    "last_run": "2026-01-01T00:00:00+00:00",
    "passed": 7,
    "failed": 0,
    "errors": 0,
    "total": 7,
    "runtime_seconds": 1.5,
    "run_by": "run-tests.sh",
    "exit_code": 0,
    "coverage_percent": null,
    "status": "ok"
  }
}
'@
        & $runner -Scope domain *> $null
        $merged = $null
        if (Test-Path $logM) { try { $merged = Get-Content $logM -Raw | ConvertFrom-Json } catch { $merged = $null } }
        $results['H2_foreign_entry_survives_with_its_values'] =
            ($null -ne $merged) -and ($null -ne $merged.properties) -and ($merged.properties.passed -eq 7) -and
            ($merged.properties.run_by -eq 'run-tests.sh') -and ($null -ne $merged.domain)
        $details['H2_foreign_entry_survives_with_its_values'] =
            "properties.passed=$($merged.properties.passed) run_by=$($merged.properties.run_by) domain=$($null -ne $merged.domain)"

        # J1/J2: a log that exists but cannot be parsed is data loss. Silence
        #        there is the actual defect behind #93 -- the interpreter
        #        incompatibility was survivable, the swallowed exception was
        #        not.
        $garbage = '{ "domain": { "passed": 1317,'
        Set-Content -Path $logM -Value $garbage -Encoding utf8
        $warnTxt = (& $runner -Scope domain 2>&1 | Out-String)
        $results['J1_unreadable_log_is_announced'] =
            ($warnTxt -match 'WARNING') -and ($warnTxt -match 'test-log\.json') -and ($warnTxt -match 'lost')
        $details['J1_unreadable_log_is_announced'] =
            (($warnTxt -split "`n" | Where-Object { $_ -match 'WARNING' }) -join ' ').Trim()

        $keptPath = "$logM.unreadable"
        $kept = if (Test-Path $keptPath) { (Get-Content $keptPath -Raw).Trim() } else { '' }
        $results['J2_unreadable_log_is_preserved'] = ($kept -eq $garbage)
        $details['J2_unreadable_log_is_preserved'] =
            if (Test-Path $keptPath) { "kept='$kept'" } else { "no backup at $keptPath" }

        # J3: an absent log is legitimately empty. Warning there would train
        #     the reader to ignore the warning that matters.
        Remove-Item $logM, $keptPath -Force -ErrorAction SilentlyContinue
        $quietTxt = (& $runner -Scope domain 2>&1 | Out-String)
        $results['J3_absent_log_is_not_announced'] = ($quietTxt -notmatch 'WARNING') -and ($quietTxt.Trim() -ne '')
        $details['J3_absent_log_is_not_announced'] = ($quietTxt -replace '\s+', ' ').Trim()
    }

    # ---------------------------------------------------------------------
    # I (#93): the same property for run-tests.sh. It merges today via sed;
    #          the case exists so the two runners cannot drift apart again --
    #          which is exactly what #93 turned out to be.
    # ---------------------------------------------------------------------
    $bashExe = $null
    foreach ($c in @('C:\Program Files\Git\bin\bash.exe', '/bin/bash', '/usr/bin/bash')) {
        if (Test-Path $c) { $bashExe = $c; break }
    }
    if (-not $bashExe) { $bashExe = (Get-Command bash -ErrorAction SilentlyContinue).Source }

    if (-not $bashExe) {
        $results['I_sh_runner_keeps_foreign_scope'] = $false
        $details['I_sh_runner_keeps_foreign_scope'] = 'no bash interpreter found'
    } else {
        $wsSh = New-SpacedFixture 'sh'
        New-Item -ItemType Directory -Path (Join-Path $wsSh '.github/scripts') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $wsSh 'tests/contracts') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $wsSh '.venv/bin') -Force | Out-Null
        Copy-Item $runTestsSh (Join-Path $wsSh '.github/scripts/run-tests.sh')

        # run-tests.sh only requires .venv/bin/python to be executable; a shim
        # that prints a pytest summary is enough and keeps the case hermetic.
        $shim = Join-Path $wsSh '.venv/bin/python'
        [IO.File]::WriteAllText($shim, "#!/bin/sh`necho '3 passed in 0.42s'`n".Replace("`r", ''))
        $shPosix = ($shim -replace '\\', '/')
        & $bashExe -c "chmod +x '$shPosix'" 2>&1 | Out-Null

        $logSh = Join-Path $wsSh '.github/test-log.json'
        Set-Content -Path $logSh -Encoding utf8 -Value @'
{
  "domain": { "last_run": "2026-01-01T00:00:00+00:00", "passed": 1317, "failed": 0, "errors": 0, "total": 1317, "runtime_seconds": 12.5, "run_by": "run-tests.ps1", "exit_code": 0, "coverage_percent": null, "status": "ok" }
}
'@
        $runnerSh = ((Join-Path $wsSh '.github/scripts/run-tests.sh') -replace '\\', '/')
        $shOut = (& $bashExe -c "'$runnerSh' --scope contracts" 2>&1 | Out-String)
        $shScopes = Get-LogScopes $logSh
        $results['I_sh_runner_keeps_foreign_scope'] =
            ($shScopes -contains 'domain') -and ($shScopes -contains 'contracts')
        $details['I_sh_runner_keeps_foreign_scope'] =
            "scopes=[$($shScopes -join ', ')] runner said: $(($shOut -replace '\s+', ' ').Trim())"
    }

    # ---------------------------------------------------------------------
    # L (#179): a run that was interrupted must not read as the previous run's
    #           result. The marker is asserted from INSIDE the run: the fake
    #           pytest copies the log while the runner is blocked on it. Killing
    #           the runner mid-flight would test the same property with a race,
    #           and a race that usually passes is worse than no case at all.
    # ---------------------------------------------------------------------
    $lKeys = @('L1_running_marker_written_before_pytest',
               'L2_running_marker_carries_no_counters',
               'L3_running_marker_write_keeps_other_scopes',
               'L4_running_marker_replaced_by_the_result')
    $wsR = New-FakePytestWorkspace 'running'
    if (-not $wsR) {
        foreach ($k in $lKeys) { $results[$k] = $false; $details[$k] = 'fake-pytest fixture could not be created' }
    } else {
        $runnerR = Join-Path $wsR '.github/scripts/run-tests.ps1'
        $logR    = Join-Path $wsR '.github/test-log.json'

        # A stale green entry for a DIFFERENT scope, plus a stale green entry
        # for the scope about to run. The second is the one #179 is about: it
        # must stop reading as a result the moment the new run starts.
        Set-Content -Path $logR -Encoding utf8 -Value @'
{
  "domain":    { "last_run": "2026-01-01T00:00:00+00:00", "passed": 1317, "failed": 0, "errors": 0, "total": 1317, "runtime_seconds": 12.5, "run_by": "run-tests.ps1", "exit_code": 0, "coverage_percent": null, "status": "ok" },
  "contracts": { "last_run": "2026-01-01T00:00:00+00:00", "passed": 42,   "failed": 0, "errors": 0, "total": 42,   "runtime_seconds": 2.5,  "run_by": "run-tests.ps1", "exit_code": 0, "coverage_percent": null, "status": "ok" }
}
'@
        $snap = Join-Path $wsR 'log-during-run.json'
        $env:AF_FAKE_PYTEST_LOGSNAP = $snap
        try { & $runnerR -Scope contracts *> $null }
        finally { Remove-Item Env:AF_FAKE_PYTEST_LOGSNAP -ErrorAction SilentlyContinue }

        $during = $null
        if (Test-Path $snap) { try { $during = Get-Content $snap -Raw | ConvertFrom-Json } catch { $during = $null } }

        # L1: while the run is in flight the entry says so, and carries the
        #     start time -- so a reader can tell a live run from an abandoned one.
        $results['L1_running_marker_written_before_pytest'] =
            ($null -ne $during) -and ($during.contracts.status -eq 'running') -and
            ([bool]$during.contracts.started)
        $details['L1_running_marker_written_before_pytest'] =
            if ($null -eq $during) { 'no snapshot taken during the run' }
            else { "status=$($during.contracts.status) started='$($during.contracts.started)'" }

        # L2: null, not 0. Zero counters next to a stale timestamp are exactly
        #     the shape a consumer reads as a clean green run.
        $results['L2_running_marker_carries_no_counters'] =
            ($null -ne $during) -and ($null -eq $during.contracts.passed) -and
            ($null -eq $during.contracts.failed) -and ($null -eq $during.contracts.total)
        $details['L2_running_marker_carries_no_counters'] =
            "passed=$($during.contracts.passed) failed=$($during.contracts.failed) total=$($during.contracts.total)"

        # L3: the interim write is a merge as well. A marker that evicts the
        #     other scopes would trade #179 for #93.
        $results['L3_running_marker_write_keeps_other_scopes'] =
            ($null -ne $during) -and ($during.domain.passed -eq 1317) -and ($during.domain.status -eq 'ok')
        $details['L3_running_marker_write_keeps_other_scopes'] =
            "domain.passed=$($during.domain.passed) domain.status=$($during.domain.status)"

        # L4: and it is replaced, not accumulated -- the completed run is the
        #     record afterwards.
        $after = $null
        if (Test-Path $logR) { try { $after = Get-Content $logR -Raw | ConvertFrom-Json } catch { $after = $null } }
        $results['L4_running_marker_replaced_by_the_result'] =
            ($null -ne $after) -and ($after.contracts.status -eq 'ok') -and
            ($after.contracts.passed -eq 3) -and ($after.domain.passed -eq 1317)
        $details['L4_running_marker_replaced_by_the_result'] =
            "status=$($after.contracts.status) passed=$($after.contracts.passed) domain.passed=$($after.domain.passed)"
    }

    # ---------------------------------------------------------------------
    # M (#179): the same property for run-tests.sh. The two runners write the
    #           same file for the same readers, so a marker in only one of them
    #           is a marker a reader cannot rely on.
    # ---------------------------------------------------------------------
    $mKeys = @('M1_sh_running_marker_written_before_pytest',
               'M2_sh_running_marker_carries_no_counters',
               'M3_sh_running_marker_write_keeps_other_scopes',
               'M4_sh_running_marker_replaced_by_the_result',
               'N_sh_summary_counters_are_parsed')
    if (-not $bashExe) {
        foreach ($k in $mKeys) { $results[$k] = $false; $details[$k] = 'no bash interpreter found' }
    } else {
        $wsS = New-SpacedFixture 'shrun'
        New-Item -ItemType Directory -Path (Join-Path $wsS '.github/scripts') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $wsS 'tests/contracts') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $wsS '.venv/bin') -Force | Out-Null
        Copy-Item $runTestsSh (Join-Path $wsS '.github/scripts/run-tests.sh')

        # The shim copies the log while the runner is blocked on it -- the bash
        # equivalent of the fake pytest snapshot used above.
        $shimS = Join-Path $wsS '.venv/bin/python'
        [IO.File]::WriteAllText($shimS,
            ("#!/bin/sh`ncp .github/test-log.json `"`$AF_SHIM_LOGSNAP`" 2>/dev/null`necho '3 passed in 0.42s'`n" -replace "`r", ''))
        & $bashExe -c "chmod +x '$($shimS -replace '\\', '/')'" 2>&1 | Out-Null

        $logS = Join-Path $wsS '.github/test-log.json'
        Set-Content -Path $logS -Encoding utf8 -Value @'
{
  "domain":    { "last_run": "2026-01-01T00:00:00+00:00", "passed": 1317, "failed": 0, "errors": 0, "total": 1317, "runtime_seconds": 12.5, "run_by": "run-tests.ps1", "exit_code": 0, "coverage_percent": null, "status": "ok" },
  "contracts": { "last_run": "2026-01-01T00:00:00+00:00", "passed": 42, "failed": 0, "errors": 0, "total": 42, "runtime_seconds": 2.5, "run_by": "run-tests.ps1", "exit_code": 0, "coverage_percent": null, "status": "ok" }
}
'@
        $snapS     = Join-Path $wsS 'log-during-run.json'
        $runnerShS = ((Join-Path $wsS '.github/scripts/run-tests.sh') -replace '\\', '/')
        $shRunOut  = (& $bashExe -c "AF_SHIM_LOGSNAP='$($snapS -replace '\\', '/')' '$runnerShS' --scope contracts" 2>&1 | Out-String)

        $duringS = $null
        if (Test-Path $snapS) { try { $duringS = Get-Content $snapS -Raw | ConvertFrom-Json } catch { $duringS = $null } }

        $results['M1_sh_running_marker_written_before_pytest'] =
            ($null -ne $duringS) -and ($duringS.contracts.status -eq 'running') -and ([bool]$duringS.contracts.started)
        $details['M1_sh_running_marker_written_before_pytest'] =
            if ($null -eq $duringS) { "no snapshot taken during the run; runner said: $(($shRunOut -replace '\s+', ' ').Trim())" }
            else { "status=$($duringS.contracts.status) started='$($duringS.contracts.started)'" }

        $results['M2_sh_running_marker_carries_no_counters'] =
            ($null -ne $duringS) -and ($null -eq $duringS.contracts.passed) -and
            ($null -eq $duringS.contracts.failed) -and ($null -eq $duringS.contracts.total)
        $details['M2_sh_running_marker_carries_no_counters'] =
            "passed=$($duringS.contracts.passed) failed=$($duringS.contracts.failed) total=$($duringS.contracts.total)"

        $results['M3_sh_running_marker_write_keeps_other_scopes'] =
            ($null -ne $duringS) -and ($duringS.domain.passed -eq 1317) -and ($duringS.domain.status -eq 'ok')
        $details['M3_sh_running_marker_write_keeps_other_scopes'] =
            "domain.passed=$($duringS.domain.passed) domain.status=$($duringS.domain.status)"

        $afterS = $null
        if (Test-Path $logS) { try { $afterS = Get-Content $logS -Raw | ConvertFrom-Json } catch { $afterS = $null } }
        $results['M4_sh_running_marker_replaced_by_the_result'] =
            ($null -ne $afterS) -and ($afterS.contracts.status -eq 'ok') -and
            ($afterS.contracts.passed -eq 3) -and ($afterS.domain.passed -eq 1317)
        $details['M4_sh_running_marker_replaced_by_the_result'] =
            "status=$($afterS.contracts.status) passed=$($afterS.contracts.passed) domain.passed=$($afterS.domain.passed)"

        # N: the counters in that entry are the ones pytest reported. Found by
        #    M4: the summary pattern used `\d`, which `grep -E` reads as a
        #    literal 'd', so no summary line ever matched and every completed
        #    run was logged as 0 passed / 0 total with status ok. The runtime is
        #    asserted too -- a case that checks only `passed` would still pass
        #    if the parse regressed to matching the first number it finds.
        $results['N_sh_summary_counters_are_parsed'] =
            ($null -ne $afterS) -and ($afterS.contracts.passed -eq 3) -and
            ($afterS.contracts.total -eq 3) -and ($afterS.contracts.runtime_seconds -eq 0.42)
        $details['N_sh_summary_counters_are_parsed'] =
            "passed=$($afterS.contracts.passed) total=$($afterS.contracts.total) runtime=$($afterS.contracts.runtime_seconds)"
    }

    # ---------------------------------------------------------------------
    # K (#93): the class, not the instance. `-AsHashtable` was one PowerShell
    #          6+ construct in a payload that runs on 5.1; nothing stopped the
    #          next one. This scan is the standing guard.
    #
    #          The scanner excludes itself -- it necessarily contains every
    #          pattern it looks for. It runs on the same 5.1 host as the suite,
    #          so a PS6 construct here fails immediately and loudly anyway.
    # ---------------------------------------------------------------------
    $ps6Patterns = @(
        '-AsHashtable', '-Parallel', '-AsByteStream', '-AsPlainText\s+-Force',
        'Test-Json', 'Join-String', '\$IsWindows', '\$IsLinux', '\$IsMacOS'
    )
    $githubDir = Join-Path $repoRootAF '.github'
    $offenders = @()
    if (Test-Path $githubDir) {
        foreach ($f in (Get-ChildItem -Path $githubDir -Recurse -Filter '*.ps1' -File)) {
            if ($f.FullName -eq $PSCommandPath) { continue }
            $text = Remove-PsComments (Get-Content $f.FullName -Raw)
            foreach ($p in $ps6Patterns) {
                if ($text -match $p) {
                    $offenders += ("{0}: {1}" -f $f.Name, ($p -replace '\\', ''))
                }
            }
        }
    } else {
        $offenders += "payload directory not found at $githubDir"
    }
    $results['K_no_ps6_only_construct_in_shipped_scripts'] = ($offenders.Count -eq 0)
    $details['K_no_ps6_only_construct_in_shipped_scripts'] = ($offenders -join '; ')
}
finally {
    foreach ($f in $fixtures) { Remove-Item $f -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host '===== test-runner regression tests (issues #73, #93, #179) ====='
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
