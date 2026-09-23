# run-all-tests.ps1 -- aggregate runner for the framework regression suites.
#
# The suites in this directory are self-contained: each one prints its own
# summary and sets its own exit code. What was missing is a single entry point
# with a single exit code, which is what a CI job needs.
#
# The important part is SKIP handling. Ten of the suites bail out early with
#
#     Write-Host 'SKIP: no Python 3 interpreter found; ...'
#     exit 0
#
# when a prerequisite (Python, ruff, PyYAML) is absent. That is correct for a
# developer laptop -- it is a catastrophe for CI, where it makes the whole gate
# report green while asserting nothing. So a skip is tracked separately and,
# under -FailOnSkip (which CI passes), fails the run.
#
# Usage:
#   .\run-all-tests.ps1                  # local: skips tolerated
#   .\run-all-tests.ps1 -FailOnSkip      # CI: a skipped suite fails the run
#   .\run-all-tests.ps1 -Filter hooks    # only suites whose name matches
#   .\run-all-tests.ps1 -Exclude a.ps1   # leave a suite out (see the workflow)
#   .\run-all-tests.ps1 -Changed         # local: only suites the diff requires
#   .\run-all-tests.ps1 -ListSelection   # show what -Changed would run

[CmdletBinding()]
param(
    [switch]$FailOnSkip,
    [string]$Filter = '*',
    [string[]]$Exclude = @(),
    # The only place the per-suite budget is stated. CI used to pass its own
    # value, so the same suite on the same tree passed there and reported
    # FAILED on a developer's machine, with nothing saying the budget was the
    # variable (#333). 1800 clears the slowest measured suite (788s) with room
    # and stays well under the CI job's own 60-minute cap, so a genuinely hung
    # suite is still killed and still named.
    [int]$TimeoutSeconds = 1800,
    # Overridable so the budget suite can drive this runner against a fixture.
    [string]$BudgetFile = '',
    # Scope a local run to the suites the working diff requires. CI does not
    # pass this and keeps sweeping everything (#334).
    [switch]$Changed,
    [switch]$ListSelection,
    [string]$Since = 'origin/dev',
    [string]$ScopeFile = '',
    # Bypasses git so the scope suite can assert selection deterministically.
    [string[]]$ChangedFiles = @()
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Run the suites with the same PowerShell host that runs this script, so the
# runner works under both Windows PowerShell and pwsh without a hardcoded name.
$psExe = (Get-Process -Id $PID).Path
if (-not $psExe) { $psExe = 'powershell' }

# Runtime ceilings. A suite can pass every assertion it makes and still be a
# defect: #334's nested re-run of test-hooks.ps1 was green for as long as it
# existed and cost a third of the whole sweep. A missing or unreadable file is
# not fatal -- the run still has to happen -- but the budget suite fails on it.
$defaultBudget = 120
$budgets = @{}
if (-not $BudgetFile) { $BudgetFile = Join-Path $scriptDir 'suite-budgets.json' }
if (Test-Path $BudgetFile) {
    try {
        $declared = Get-Content $BudgetFile -Raw | ConvertFrom-Json
        if ($null -ne $declared.default) { $defaultBudget = [int]$declared.default }
        foreach ($entry in $declared.suites.PSObject.Properties) {
            $budgets[$entry.Name] = [int]$entry.Value
        }
    } catch {
        Write-Host "Could not read $BudgetFile -- falling back to ${defaultBudget}s for every suite."
    }
}

$suites = Get-ChildItem -Path $scriptDir -Filter 'test-*.ps1' |
    Where-Object { $_.Name -like "*$Filter*" -or $Filter -eq '*' } |
    Where-Object { $Exclude -notcontains $_.Name } |
    Sort-Object Name

# ── Path-scoped selection ─────────────────────────────────────────────────

# Patterns are matched by suffix so the same map works here, where the tree
# starts at flavors/github-copilot/, and in a project the payload was deployed
# into, where it starts at .github/.
function Test-PathMatchesPattern {
    param([string]$Path, [string]$Pattern)
    $p = ($Path -replace '\\', '/').TrimStart('./')
    if ($Pattern.EndsWith('/**')) {
        $dir = $Pattern.Substring(0, $Pattern.Length - 3)
        return ($p -eq $dir) -or $p.StartsWith("$dir/") -or $p.Contains("/$dir/")
    }
    return ($p -eq $Pattern) -or $p.EndsWith("/$Pattern")
}

function Get-ChangedPaths {
    param([string]$Base)
    $ErrorActionPreference = 'Continue'
    $paths = @()
    $paths += @(git diff --name-only "$Base...HEAD" 2>$null)
    $paths += @(git status --porcelain 2>$null | ForEach-Object { $_.Substring(3).Trim('"') })
    if ($LASTEXITCODE -ne 0 -and $paths.Count -eq 0) { return $null }
    return @($paths | Where-Object { $_ } | Sort-Object -Unique)
}

function Select-Suites {
    param([string[]]$Paths, $Scope, [string[]]$AllSuites)

    $selected = New-Object 'System.Collections.Generic.HashSet[string]'
    $uncovered = @()

    foreach ($path in $Paths) {
        if (@($Scope.ignore | Where-Object { Test-PathMatchesPattern $path $_ }).Count -gt 0) { continue }

        if (@($Scope.always | Where-Object { Test-PathMatchesPattern $path $_ }).Count -gt 0) {
            foreach ($s in $AllSuites) { [void]$selected.Add($s) }
            continue
        }

        $hit = $false
        foreach ($s in $AllSuites) {
            if (Test-PathMatchesPattern $path ".github/scripts/$s") { [void]$selected.Add($s); $hit = $true }
        }
        foreach ($entry in $Scope.suites.PSObject.Properties) {
            foreach ($pattern in @($entry.Value)) {
                if (Test-PathMatchesPattern $path $pattern) { [void]$selected.Add($entry.Name); $hit = $true }
            }
        }
        if (-not $hit) { $uncovered += $path }
    }

    return @{ Selected = @($selected); Uncovered = $uncovered }
}

if ($Changed -or $ListSelection) {
    if (-not $ScopeFile) { $ScopeFile = Join-Path $scriptDir 'suite-scope.json' }
    $allNames = @($suites | Select-Object -ExpandProperty Name)
    $chosen = $allNames
    $uncovered = @()

    $scope = $null
    if (Test-Path $ScopeFile) {
        try { $scope = Get-Content $ScopeFile -Raw | ConvertFrom-Json } catch { $scope = $null }
    }

    $paths = $ChangedFiles
    if ($paths.Count -eq 0) { $paths = Get-ChangedPaths -Base $Since }

    # No map, no diff, or a git that would not answer: sweep everything. Every
    # unknown has to resolve towards more testing, not less.
    if ($null -eq $scope) {
        $uncovered = @("no usable $ScopeFile")
    } elseif ($null -eq $paths) {
        $uncovered = @('could not read the diff')
    } else {
        $selection = Select-Suites -Paths $paths -Scope $scope -AllSuites $allNames
        $uncovered = $selection.Uncovered
        if ($uncovered.Count -eq 0) { $chosen = @($selection.Selected | Sort-Object) }
    }

    if ($ListSelection) {
        Write-Host ''
        Write-Host "=== AF suite selection ($($paths.Count) changed path(s)) ==="
        if ($uncovered.Count -gt 0) {
            Write-Host ("  FALLBACK  no mapping covers: {0} -- running every suite" -f ($uncovered -join ', '))
        }
        if ($chosen.Count -eq 0) {
            Write-Host '  (nothing selected -- no changed path requires a suite)'
        } else {
            foreach ($name in $chosen) { Write-Host "  SELECT  $name" }
        }
        exit 0
    }

    if ($uncovered.Count -gt 0) {
        Write-Host ("Scoped run widened to every suite -- no mapping covers: {0}" -f ($uncovered -join ', '))
    }
    if ($chosen.Count -eq 0) {
        Write-Host 'Nothing to run -- no changed path requires a suite. CI still sweeps everything.'
        exit 0
    }
    $suites = @($suites | Where-Object { $chosen -contains $_.Name })
}

if ($suites.Count -eq 0) {
    Write-Host "No suites matched filter '$Filter'."
    exit 1
}

Write-Host ''
Write-Host "Running $($suites.Count) regression suite(s) from $scriptDir"
Write-Host ("-" * 78)

$results = @()

foreach ($suite in $suites) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $overBudget = ''

    # Deliberately not Start-Process -PassThru: without -Wait it leaves
    # .ExitCode empty, and an empty value compares as non-zero, which reports
    # every passing suite as a failure. -Wait would fix that but gives up the
    # timeout, and a hung suite must not hang CI. System.Diagnostics.Process
    # gives both a real exit code and a real timeout.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $psExe
    $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $suite.FullName
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = (Get-Location).Path

    $proc = [System.Diagnostics.Process]::Start($psi)

    # Drain both pipes asynchronously before waiting. Reading them in sequence
    # after WaitForExit deadlocks as soon as a suite fills the stderr buffer.
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()

    $exited = $proc.WaitForExit($TimeoutSeconds * 1000)
    $sw.Stop()

    if (-not $exited) {
        try { $proc.Kill() } catch { }
        $status = 'TIMEOUT'
        $code = $null
        $output = "Suite exceeded $TimeoutSeconds seconds and was killed."
    }
    else {
        $code = $proc.ExitCode
        $output = [string]$stdoutTask.Result + [string]$stderrTask.Result

        # A suite that bailed out on a missing prerequisite says so on its own
        # line before exiting 0. Exit code alone cannot tell that apart from a
        # genuine pass -- the output has to be read.
        #
        # Exit 2 is the framework's "blocked" code: the suite could not run,
        # which is not the same as the code being wrong. It is reported
        # separately so it can neither masquerade as a pass nor be mistaken
        # for a real regression.
        $skipped = $output -match '(?m)^\s*SKIP:'
        if ($code -eq 2)     { $status = 'BLOCKED' }
        elseif ($code -ne 0) { $status = 'FAIL' }
        elseif ($skipped)    { $status = 'SKIP' }
        else                 { $status = 'PASS' }

        if ($status -eq 'PASS') {
            $budget = if ($budgets.ContainsKey($suite.Name)) { $budgets[$suite.Name] } else { $defaultBudget }
            if ($sw.Elapsed.TotalSeconds -gt $budget) {
                $status = 'SLOW'
                $overBudget = 'Took {0}s against a {1}s budget -- make it faster, or raise the ceiling in suite-budgets.json and say why.' -f [math]::Round($sw.Elapsed.TotalSeconds, 1), $budget
            }
        }
    }

    $proc.Dispose()

    $reason = ''
    if ($status -eq 'SLOW') {
        $reason = $overBudget
    }
    elseif ($status -eq 'SKIP') {
        $m = [regex]::Match($output, '(?m)^\s*SKIP:\s*(.+)$')
        if ($m.Success) { $reason = $m.Groups[1].Value.Trim() }
    }
    elseif ($status -ne 'PASS') {
        $lines = @($output -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
        if ($lines.Count -gt 0) { $reason = $lines[-1].Trim() }
    }

    $results += [pscustomobject]@{
        Suite   = $suite.Name
        Status  = $status
        Code    = $code
        Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        Reason  = $reason
        Output  = $output
    }

    $line = '{0,-36} {1,-7} {2,7:N1}s' -f $suite.Name, $status, $sw.Elapsed.TotalSeconds
    if ($reason) { $line += "  | $reason" }
    Write-Host $line
}

$passed  = @($results | Where-Object { $_.Status -eq 'PASS' })
$slow    = @($results | Where-Object { $_.Status -eq 'SLOW' })
$skipped = @($results | Where-Object { $_.Status -eq 'SKIP' })
$blocked = @($results | Where-Object { $_.Status -eq 'BLOCKED' })
$failed  = @($results | Where-Object { $_.Status -eq 'FAIL' -or $_.Status -eq 'TIMEOUT' })

# Skipped and blocked differ in cause but not in consequence: in both cases the
# suite asserted nothing, so under -FailOnSkip both must stop the run.
$silent = @($skipped) + @($blocked)

# A failing suite's own output is the only diagnostic CI will ever show, so
# echo it in full rather than making someone reproduce the run locally.
foreach ($f in $failed) {
    Write-Host ''
    Write-Host ("=" * 78)
    Write-Host "FAILED: $($f.Suite)  (exit $($f.Code))"
    Write-Host ("=" * 78)
    Write-Host $f.Output
}

Write-Host ''
Write-Host ("-" * 78)
Write-Host ('TOTAL {0} suite(s) in {1:N1}s -- {2} passed, {3} over budget, {4} skipped, {5} blocked, {6} failed' -f `
    $results.Count, (($results | Measure-Object -Property Seconds -Sum).Sum), `
    $passed.Count, $slow.Count, $skipped.Count, $blocked.Count, $failed.Count)

if ($silent.Count -gt 0) {
    Write-Host ''
    Write-Host 'Suites that asserted nothing:'
    foreach ($s in $silent) { Write-Host ("  {0} [{1}]: {2}" -f $s.Suite, $s.Status, $s.Reason) }
}

if ($failed.Count -gt 0) {
    Write-Host ''
    Write-Host 'RESULT: FAILED'
    exit 1
}
if ($slow.Count -gt 0) {
    Write-Host ''
    Write-Host 'Suites over their declared runtime budget:'
    foreach ($s in $slow) { Write-Host ("  {0}: {1}" -f $s.Suite, $s.Reason) }
    Write-Host ''
    Write-Host 'RESULT: FAILED -- a suite costs more than it is allowed to.'
    exit 1
}
if ($FailOnSkip -and $silent.Count -gt 0) {
    Write-Host ''
    Write-Host 'RESULT: FAILED -- suites asserted nothing and -FailOnSkip is set.'
    Write-Host 'Install the missing prerequisites, or exclude a suite that cannot'
    Write-Host 'run in this environment with -Exclude and say why.'
    exit 1
}

Write-Host ''
Write-Host 'RESULT: ALL GREEN'
exit 0
