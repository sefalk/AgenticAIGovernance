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

[CmdletBinding()]
param(
    [switch]$FailOnSkip,
    [string]$Filter = '*',
    [string[]]$Exclude = @(),
    [int]$TimeoutSeconds = 600
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Run the suites with the same PowerShell host that runs this script, so the
# runner works under both Windows PowerShell and pwsh without a hardcoded name.
$psExe = (Get-Process -Id $PID).Path
if (-not $psExe) { $psExe = 'powershell' }

$suites = Get-ChildItem -Path $scriptDir -Filter 'test-*.ps1' |
    Where-Object { $_.Name -like "*$Filter*" -or $Filter -eq '*' } |
    Where-Object { $Exclude -notcontains $_.Name } |
    Sort-Object Name

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
    }

    $proc.Dispose()

    $reason = ''
    if ($status -eq 'SKIP') {
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
Write-Host ("TOTAL {0} suite(s) in {1:N1}s -- {2} passed, {3} skipped, {4} blocked, {5} failed" -f `
    $results.Count, (($results | Measure-Object -Property Seconds -Sum).Sum), `
    $passed.Count, $skipped.Count, $blocked.Count, $failed.Count)

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
