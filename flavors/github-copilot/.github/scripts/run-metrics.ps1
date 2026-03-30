# Metrics collection script for agent workflows.
# copilot:generated | implementer | 2026-03-30
# Agents invoke this via predefined tasks (run_task) or createAndRunTask.
#
# Usage:
#   .github/scripts/run-metrics.ps1 -Metric complexity     # Cyclomatic complexity
#   .github/scripts/run-metrics.ps1 -Metric ratio           # Test-to-code ratio
#   .github/scripts/run-metrics.ps1 -Metric audit           # pip-audit (CVE check)

param(
    [Parameter(Mandatory)]
    [ValidateSet('complexity', 'ratio', 'audit')]
    [string]$Metric
)

# --- Configuration ---
$workspaceRoot = (Resolve-Path "$PSScriptRoot/../..").Path

# Load source package name from af-env.conf
$srcDir = 'src'
$confPath = Join-Path $workspaceRoot '.github/af-env.conf'
if (Test-Path $confPath) {
    $m = Select-String -Path $confPath -Pattern '^SRC_DIR=(.+)$'
    if ($m) { $srcDir = $m.Matches[0].Groups[1].Value.Trim() }
}

$srcPath = Join-Path $workspaceRoot $srcDir
$testsPath = Join-Path $workspaceRoot 'tests'

# Resolve venv python
$python = Join-Path $workspaceRoot '.venv/Scripts/python.exe'
if (-not (Test-Path $python -ErrorAction SilentlyContinue)) {
    Write-Output "ERROR: venv python not found at $python"
    exit 1
}

Push-Location $workspaceRoot
try {
    switch ($Metric) {
        'complexity' {
            Write-Output "=== Cyclomatic Complexity: $srcDir/ ==="
            Write-Output ""
            & $python -m radon cc $srcDir/ -a -s -n C
            if ($LASTEXITCODE -ne 0) {
                Write-Output ""
                Write-Output "ERROR: radon failed (exit $LASTEXITCODE). Install with: pip install radon"
                exit 1
            }
        }
        'ratio' {
            Write-Output "=== Test-to-Code Ratio ==="
            Write-Output ""

            $prodLines = 0
            $testLines = 0

            if (Test-Path $srcPath) {
                $prodFiles = Get-ChildItem $srcPath -Recurse -Filter '*.py'
                foreach ($f in $prodFiles) {
                    $lines = (Get-Content $f.FullName | Where-Object {
                        $_ -match '\S' -and $_ -notmatch '^\s*#'
                    }).Count
                    $prodLines += $lines
                }
            }

            if (Test-Path $testsPath) {
                $testFiles = Get-ChildItem $testsPath -Recurse -Filter '*.py'
                foreach ($f in $testFiles) {
                    $lines = (Get-Content $f.FullName | Where-Object {
                        $_ -match '\S' -and $_ -notmatch '^\s*#'
                    }).Count
                    $testLines += $lines
                }
            }

            $ratio = if ($prodLines -gt 0) { [math]::Round($testLines / $prodLines, 2) } else { 'N/A' }

            Write-Output "  Production code ($srcDir/):  $prodLines lines"
            Write-Output "  Test code (tests/):          $testLines lines"
            Write-Output "  Ratio (test:prod):           ${ratio}:1"
        }
        'audit' {
            Write-Output "=== Dependency Audit (pip-audit) ==="
            Write-Output ""
            & $python -m pip_audit
            if ($LASTEXITCODE -ne 0) {
                Write-Output ""
                Write-Output "WARNING: pip-audit found vulnerabilities or failed (exit $LASTEXITCODE)."
                Write-Output "Install with: pip install pip-audit"
                exit $LASTEXITCODE
            }
        }
    }
} finally {
    Pop-Location
}
