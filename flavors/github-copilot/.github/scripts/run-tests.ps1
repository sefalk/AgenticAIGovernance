# Canonical test runner for agent workflows.
# All agents MUST use this script instead of calling pytest directly.
#
# Usage:
#   .github/scripts/run-tests.ps1                                    # Run all tests
#   .github/scripts/run-tests.ps1 -Scope domain                      # Domain tests only
#   .github/scripts/run-tests.ps1 -Scope adapters                    # Adapter tests only
#   .github/scripts/run-tests.ps1 -File tests/domain/test_helper.py  # Specific file
#   .github/scripts/run-tests.ps1 -Filter "test_name"                # Filter by -k
#   .github/scripts/run-tests.ps1 -Scope domain -Coverage            # With coverage
#   .github/scripts/run-tests.ps1 -Scope domain -FailFast            # Stop on first failure
#   .github/scripts/run-tests.ps1 -Scope domain -OutputFile -Force   # Write full output to file
#   .github/scripts/run-tests.ps1 -Traceback long                    # Long tracebacks
#
# Output file: .github/test-output.txt (only when -OutputFile is set)
#
# Exit codes:
#   0 = all tests passed
#   1 = test failures
#   2 = no tests collected
#   5 = no tests matched (pytest exit code)

param(
    [ValidateSet('all', 'domain', 'adapters', 'properties', 'contracts')]
    [string]$Scope = 'all',

    [string]$File = '',
    [string]$Filter = '',
    [ValidateSet('short', 'long', 'line', 'no', 'auto')]
    [string]$Traceback = 'short',

    [switch]$Coverage,
    [switch]$FailFast,
    [switch]$OutputFile,
    [switch]$Force
)

# --- Configuration ---
# Resolve workspace root (script is at .github/scripts/)
$workspaceRoot = (Resolve-Path "$PSScriptRoot/../..").Path

# Load project config for source package name
$covPackage = 'src'
$confPath = Join-Path $workspaceRoot '.github/af-env.conf'
if (Test-Path $confPath) {
    $m = Select-String -Path $confPath -Pattern '^SRC_DIR=(.+)$'
    if ($m) { $covPackage = $m.Matches[0].Groups[1].Value.Trim() }
}

# Resolve venv python
$python = Join-Path $workspaceRoot '.venv/Scripts/python.exe'
if (-not (Test-Path $python -ErrorAction SilentlyContinue)) {
    Write-Output "ERROR: venv python not found at $python"
    exit 1
}

# Validate -File if provided
if ($File) {
    $fullFile = Join-Path $workspaceRoot $File
    if (-not (Test-Path $fullFile -ErrorAction SilentlyContinue)) {
        Write-Output "ERROR: test file not found: $File"
        exit 1
    }
}

# Check output file conflict
$outputFilePath = Join-Path $workspaceRoot '.github/test-output.txt'
if ($OutputFile -and (Test-Path $outputFilePath -ErrorAction SilentlyContinue) -and -not $Force) {
    Write-Output "ERROR: Output file exists at .github/test-output.txt. Use -Force to overwrite."
    exit 1
}

if ($Force -and -not $OutputFile) {
    Write-Output "WARNING: -Force has no effect without -OutputFile"
}

# Map scope to test directory.
# INVARIANT: no value may carry a trailing separator. Join-Path normalises
# 'tests/' to '...\tests\'; when the workspace path contains spaces PowerShell
# quotes the argument and the CRT argv parser reads the resulting \" as an
# escaped quote, swallowing every following argument into argv[1]. pytest then
# collects nothing. Pinned by .github/scripts/test-run-tests.ps1.
$scopeMap = @{
    'all'        = 'tests'
    'domain'     = 'tests/domain'
    'adapters'   = 'tests/adapters'
    'properties' = 'tests/properties'
    'contracts'  = 'tests/contracts'
}

# Build pytest arguments
$pytestArgs = @('-m', 'pytest')
if ($File) {
    $pytestArgs += $fullFile
} else {
    # TrimEnd is defensive belt-and-braces for the invariant above.
    $pytestArgs += (Join-Path $workspaceRoot $scopeMap[$Scope]).TrimEnd('\', '/')
}

$pytestArgs += "--tb=$Traceback", '-q', '--no-header'

if ($Filter) {
    $pytestArgs += '-k', $Filter
}
if ($Coverage) {
    $pytestArgs += "--cov=$covPackage", '--cov-report=term-missing', '--cov-branch'
}
if ($FailFast) {
    $pytestArgs += '-x'
}

# Header
if ($File) {
    $targetDisplay = "file=$File"
} else {
    $targetDisplay = "scope=$Scope"
}
$filterDisplay = if ($Filter) { $Filter } else { 'none' }
Write-Output "=== Test Runner: $targetDisplay filter=$filterDisplay ==="

# ---------- Test log (.github/test-log.json) ----------
$testLogPath = Join-Path $workspaceRoot '.github/test-log.json'

# Which entry this run owns. $null means the run cannot be attributed to a
# scope (a -File run outside the known test trees), and such a run records
# nothing rather than guessing.
function Get-LogScopeKey {
    if ($File) {
        if ($File -match 'tests/domain')     { return 'domain' }
        if ($File -match 'tests/adapters')   { return 'adapters' }
        if ($File -match 'tests/properties') { return 'properties' }
        if ($File -match 'tests/contracts')  { return 'contracts' }
        return $null
    }
    return $Scope
}

# Read existing log (cumulative merge).
#
# Not `ConvertFrom-Json -AsHashtable`: that parameter is PowerShell 6+, and
# Windows PowerShell 5.1 is the default host for the shipped VS Code tasks. It
# threw there on every run, and the catch below turned that into a log holding
# only the scope that had just run.
#
# An absent file is legitimately empty. A file that exists and cannot be parsed
# is data loss, so it is announced and kept -- overwriting it would destroy the
# only artifact that could explain what happened.
#
# The warnings are queued instead of written here: in PowerShell everything a
# function writes joins its return value, so a Write-Output inside this function
# turns the returned hashtable into an array and the caller's $log[$scope]
# assignment fails with "cannot convert 'domain' to System.Int32".
$script:logWarnings = @()
function Read-TestLog {
    $log = @{}
    if (Test-Path $testLogPath) {
        try {
            $existing = Get-Content $testLogPath -Raw | ConvertFrom-Json
            foreach ($p in $existing.PSObject.Properties) { $log[$p.Name] = $p.Value }
        } catch {
            $keptPath = "$testLogPath.unreadable"
            Copy-Item $testLogPath $keptPath -Force -ErrorAction SilentlyContinue
            $script:logWarnings += "WARNING: could not read $testLogPath ($($_.Exception.Message))"
            $script:logWarnings += "WARNING: previously recorded scopes are lost; the unreadable file was kept at $keptPath"
            $log = @{}
        }
    }
    return $log
}

function Show-LogWarnings {
    foreach ($w in $script:logWarnings) { Write-Output $w }
    $script:logWarnings = @()
}

function Save-TestLog($log) {
    $log | ConvertTo-Json -Depth 3 | Set-Content -Path $testLogPath -Encoding utf8
}

# Claim the entry BEFORE pytest starts.
#
# The entry used to be built only after pytest returned. A run that was
# interrupted -- terminal closed, agent cancelled, machine slept -- left the
# previous entry untouched, still saying status ok with yesterday's counters.
# Nothing distinguished it from a fresh green result, and a reader working to a
# once-per-workflow test budget skips the suite on exactly that evidence.
#
# Counters are null, never 0, for the same reason the runner-failure path uses
# null: "0 failed" is indistinguishable from a clean green run.
$logScope  = Get-LogScopeKey
$startedAt = (Get-Date -Format 'o')
if ($logScope) {
    $startLog = Read-TestLog
    Show-LogWarnings
    $startLog[$logScope] = @{
        last_run         = $startedAt
        started          = $startedAt
        passed           = $null
        failed           = $null
        errors           = $null
        total            = $null
        runtime_seconds  = $null
        run_by           = 'run-tests.ps1'
        exit_code        = $null
        coverage_percent = $null
        status           = 'running'
    }
    Save-TestLog $startLog
}

# Run pytest. stderr is captured to a file rather than discarded: it is noise
# on a successful run (PySpark), but it is the ONLY diagnosis when the runner
# itself fails, and discarding it is what made this failure mode silent.
$stderrPath = Join-Path ([IO.Path]::GetTempPath()) ("af-run-tests-$PID.err")
Push-Location $workspaceRoot
try {
    $stdout = & $python $pytestArgs 2>$stderrPath
    $pytestExit = $LASTEXITCODE
} finally {
    Pop-Location
}
$stderrText = ''
if (Test-Path $stderrPath) {
    $stderrText = (Get-Content $stderrPath -Raw -ErrorAction SilentlyContinue)
    Remove-Item $stderrPath -ErrorAction SilentlyContinue
}

# ---------- Update test log (.github/test-log.json) ----------

# Parse pytest summary line: "619 passed in 5.33s" or "617 passed, 2 failed in 5.33s"
$passed = 0; $failed = 0; $errors = 0; $runtime = 0
$summaryLine = $null
if ($stdout) {
    $summaryLine = ($stdout -split "`n" | Where-Object { $_ -match '\d+ passed' -or $_ -match '\d+ failed' -or $_ -match '\d+ error' } | Select-Object -Last 1)
    if ($summaryLine) {
        if ($summaryLine -match '(\d+) passed')  { $passed  = [int]$Matches[1] }
        if ($summaryLine -match '(\d+) failed')  { $failed  = [int]$Matches[1] }
        if ($summaryLine -match '(\d+) error')   { $errors  = [int]$Matches[1] }
        if ($summaryLine -match 'in (\d+\.?\d*)s') { $runtime = [double]$Matches[1] }
    }
}
$total = $passed + $failed + $errors

# A run that produced no parseable summary AND exited non-zero never executed a
# test: wrong interpreter, missing dependency, usage error, nothing collected.
# Reporting that as "0 failed" is indistinguishable from a clean green run, so
# the counters are recorded as null and the entry is labelled an error instead.
$runnerFailed = ((-not $summaryLine) -and $pytestExit -ne 0)

# Re-read: the interim write above is not the only thing that may have touched
# the file, and the other scopes' entries must survive this write too.
$testLog = Read-TestLog
Show-LogWarnings

# Build scope entry
$entry = @{
    last_run        = (Get-Date -Format 'o')
    started         = $startedAt
    passed          = $passed
    failed          = $failed
    errors          = $errors
    total           = $total
    runtime_seconds = $runtime
    run_by          = 'run-tests.ps1'
    exit_code       = $pytestExit
    coverage_percent = $null
    status          = 'ok'
}

if ($runnerFailed) {
    $entry.status = 'error'
    $entry.passed = $null
    $entry.failed = $null
    $entry.errors = $null
    $entry.error_message = if ($stderrText) {
        (($stderrText -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 3) -join ' | ').Trim()
    } else {
        "pytest produced no output and exited with code $pytestExit"
    }
}

# If coverage was requested and output contains coverage %, extract it
if ($Coverage -and $stdout) {
    $covLine = ($stdout -split "`n" | Where-Object { $_ -match '^TOTAL\s+' } | Select-Object -Last 1)
    if ($covLine -and $covLine -match '(\d+)%') {
        $entry.coverage_percent = [int]$Matches[1]
    }
}

# Record the result under the entry claimed before the run.
if ($logScope) {
    $testLog[$logScope] = $entry
}

# Write merged log
Save-TestLog $testLog

# Write output file if requested
if ($OutputFile) {
    if ($stdout) {
        $stdout | Out-File -FilePath $outputFilePath -Encoding utf8
        $lineCount = ($stdout -split "`n").Count
        Write-Output "(Full output: .github/test-output.txt - $lineCount lines)"
    } else {
        "(no pytest output)" | Out-File -FilePath $outputFilePath -Encoding utf8
        Write-Output "(Full output: .github/test-output.txt - empty)"
    }
}

# Show summary (last 5 lines of stdout)
if ($stdout) {
    $lines = $stdout -split "`n"
    $summaryCount = [Math]::Min(5, $lines.Count)
    $startIdx = $lines.Count - $summaryCount
    $lines[$startIdx..($lines.Count - 1)] | ForEach-Object { Write-Output $_ }
} else {
    Write-Output "(no pytest output)"
}

# Surface the runner failure instead of leaving the caller with a bare exit code.
if ($runnerFailed) {
    Write-Output "ERROR: pytest did not run -- no test results were produced."
    if ($stderrText) {
        $stderrText -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 10 | ForEach-Object { Write-Output "  $_" }
    }
    Write-Output "(test-log.json entry recorded as status=error, not as a passing run)"
}

# Footer
Write-Output "=== Exit Code: $pytestExit ==="

exit $pytestExit
