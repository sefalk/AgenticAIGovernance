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

# Map scope to test directory
$scopeMap = @{
    'all'        = 'tests/'
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
    $pytestArgs += (Join-Path $workspaceRoot $scopeMap[$Scope])
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

# Run pytest, suppress stderr (PySpark noise), capture stdout
Push-Location $workspaceRoot
try {
    $stdout = & $python $pytestArgs 2>$null
    $pytestExit = $LASTEXITCODE
} finally {
    Pop-Location
}

# ---------- Update test log (.github/test-log.json) ----------
$testLogPath = Join-Path $workspaceRoot '.github/test-log.json'

# Parse pytest summary line: "619 passed in 5.33s" or "617 passed, 2 failed in 5.33s"
$passed = 0; $failed = 0; $errors = 0; $runtime = 0
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

# Read existing log (cumulative merge)
$testLog = @{}
if (Test-Path $testLogPath) {
    try {
        $testLog = Get-Content $testLogPath -Raw | ConvertFrom-Json -AsHashtable
    } catch {
        $testLog = @{}
    }
}

# Build scope entry
$entry = @{
    last_run        = (Get-Date -Format 'o')
    passed          = $passed
    failed          = $failed
    errors          = $errors
    total           = $total
    runtime_seconds = $runtime
    run_by          = 'run-tests.ps1'
    exit_code       = $pytestExit
    coverage_percent = $null
}

# If coverage was requested and output contains coverage %, extract it
if ($Coverage -and $stdout) {
    $covLine = ($stdout -split "`n" | Where-Object { $_ -match '^TOTAL\s+' } | Select-Object -Last 1)
    if ($covLine -and $covLine -match '(\d+)%') {
        $entry.coverage_percent = [int]$Matches[1]
    }
}

# Determine which scopes to update
if ($File) {
    # File-specific run: detect scope from path
    $fileScope = 'file'
    if ($File -match 'tests/domain')     { $fileScope = 'domain' }
    if ($File -match 'tests/adapters')   { $fileScope = 'adapters' }
    if ($File -match 'tests/properties') { $fileScope = 'properties' }
    if ($File -match 'tests/contracts')  { $fileScope = 'contracts' }
    if ($fileScope -ne 'file') {
        $testLog[$fileScope] = $entry
    }
} elseif ($Scope -eq 'all') {
    # 'all' scope: update a summary entry
    $testLog['all'] = $entry
} else {
    $testLog[$Scope] = $entry
}

# Write merged log
$testLog | ConvertTo-Json -Depth 3 | Set-Content -Path $testLogPath -Encoding utf8

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

# Footer
Write-Output "=== Exit Code: $pytestExit ==="

exit $pytestExit
