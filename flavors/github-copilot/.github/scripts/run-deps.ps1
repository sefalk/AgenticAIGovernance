# Dependency installation script for agent workflows.
# Reads DEP_FILE / DEP_DEV_FILE from af-env.conf so task definitions
# stay project-agnostic.
#
# Usage:
#   .github/scripts/run-deps.ps1 -Scope dev       # Install dev/test deps
#   .github/scripts/run-deps.ps1 -Scope runtime    # Install runtime package

param(
    [Parameter(Mandatory)]
    [ValidateSet('dev', 'runtime')]
    [string]$Scope
)

# --- Configuration ---
$workspaceRoot = (Resolve-Path "$PSScriptRoot/../..").Path

# Load dep file paths from af-env.conf
$depFile = ''
$depDevFile = ''
$confPath = Join-Path $workspaceRoot '.github/af-env.conf'
if (Test-Path $confPath) {
    $m = Select-String -Path $confPath -Pattern '^DEP_FILE=(.+)$'
    if ($m) { $depFile = $m.Matches[0].Groups[1].Value.Trim() }
    $m = Select-String -Path $confPath -Pattern '^DEP_DEV_FILE=(.+)$'
    if ($m) { $depDevFile = $m.Matches[0].Groups[1].Value.Trim() }
}

# Resolve venv pip
$pip = Join-Path $workspaceRoot '.venv/Scripts/pip.exe'
if (-not (Test-Path $pip -ErrorAction SilentlyContinue)) {
    Write-Output "ERROR: venv pip not found at $pip"
    exit 1
}

Push-Location $workspaceRoot
try {
    switch ($Scope) {
        'dev' {
            if (-not $depDevFile) {
                Write-Output "ERROR: DEP_DEV_FILE not set in .github/af-env.conf"
                exit 1
            }
            $target = Join-Path $workspaceRoot $depDevFile
            if (-not (Test-Path $target)) {
                Write-Output "ERROR: $depDevFile not found at $target"
                exit 1
            }
            Write-Output "=== Installing dev dependencies from $depDevFile ==="
            Write-Output ""
            & $pip install -r $target
            exit $LASTEXITCODE
        }
        'runtime' {
            if (-not $depFile) {
                Write-Output "ERROR: DEP_FILE not set in .github/af-env.conf"
                exit 1
            }
            # Detect file type: requirements.txt → -r, setup.py/pyproject.toml → -e .
            $ext = [System.IO.Path]::GetExtension($depFile)
            if ($ext -eq '.txt') {
                $target = Join-Path $workspaceRoot $depFile
                if (-not (Test-Path $target)) {
                    Write-Output "ERROR: $depFile not found at $target"
                    exit 1
                }
                Write-Output "=== Installing runtime dependencies from $depFile ==="
                Write-Output ""
                & $pip install -r $target
            } else {
                # setup.py, pyproject.toml, setup.cfg → editable install
                Write-Output "=== Installing runtime package (editable) from $depFile ==="
                Write-Output ""
                & $pip install -e .
            }
            exit $LASTEXITCODE
        }
    }
} finally {
    Pop-Location
}
