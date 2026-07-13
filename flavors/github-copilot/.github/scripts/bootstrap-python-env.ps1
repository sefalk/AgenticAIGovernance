# copilot:generated | implementer | 2026-04-14
# Bootstrap Python environment for AF workflows.
#
# Usage:
#   .github/scripts/bootstrap-python-env.ps1
#   .github/scripts/bootstrap-python-env.ps1 -SkipDeps
#
# Exit codes:
#   0 = environment ready
#   1 = python executable not found
#   2 = venv creation failed
#   3 = dependency install failed

param(
    [switch]$SkipDeps
)

$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path "$PSScriptRoot/../..").Path
$venvPython = Join-Path $workspaceRoot '.venv/Scripts/python.exe'
$venvPip = Join-Path $workspaceRoot '.venv/Scripts/pip.exe'
$confPath = Join-Path $workspaceRoot '.github/af-env.conf'

Write-Output '=== Bootstrap Python Environment ==='
Write-Output "Workspace: $workspaceRoot"

function Resolve-SystemPython {
    $candidates = @('python', 'py', 'python3')
    foreach ($cmd in $candidates) {
        $c = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($c) {
            if ($cmd -eq 'py') {
                return @($c.Source, '-3')
            }
            return @($c.Source)
        }
    }
    return @()
}

# 1) Create venv if missing
if (-not (Test-Path $venvPython)) {
    $pythonCmd = Resolve-SystemPython
    if (-not $pythonCmd -or $pythonCmd.Count -eq 0) {
        Write-Output 'ERROR: No Python executable found (python/py/python3).'
        exit 1
    }

    Write-Output 'Creating .venv ...'
    Push-Location $workspaceRoot
    try {
        if ($pythonCmd.Count -gt 1) {
            & $pythonCmd[0] $pythonCmd[1] -m venv .venv
        } else {
            & $pythonCmd[0] -m venv .venv
        }
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $venvPython)) {
            Write-Output 'ERROR: Failed to create .venv.'
            exit 2
        }
    } finally {
        Pop-Location
    }
}

# 2) Upgrade base tooling
if (-not (Test-Path $venvPip)) {
    Write-Output "ERROR: pip not found at $venvPip"
    exit 2
}

Write-Output 'Upgrading pip/setuptools/wheel ...'
& $venvPython -m pip install --upgrade pip setuptools wheel
if ($LASTEXITCODE -ne 0) {
    Write-Output 'ERROR: Failed to upgrade base packaging tools.'
    exit 3
}

if ($SkipDeps) {
    Write-Output 'Dependency installation skipped (-SkipDeps).'
    Write-Output 'Environment ready.'
    exit 0
}

# 3) Install deps from af-env.conf if available
$depFile = ''
$depDevFile = ''
if (Test-Path $confPath) {
    $m = Select-String -Path $confPath -Pattern '^DEP_FILE=(.+)$'
    if ($m) { $depFile = $m.Matches[0].Groups[1].Value.Trim() }
    $m = Select-String -Path $confPath -Pattern '^DEP_DEV_FILE=(.+)$'
    if ($m) { $depDevFile = $m.Matches[0].Groups[1].Value.Trim() }
}

$depTargets = @()
if ($depFile) { $depTargets += $depFile }
if ($depDevFile -and $depDevFile -ne $depFile) { $depTargets += $depDevFile }

Push-Location $workspaceRoot
try {
    foreach ($dep in $depTargets) {
        $depPath = Join-Path $workspaceRoot $dep
        if (-not (Test-Path $depPath)) {
            Write-Output "WARN: Dependency file not found, skipping: $dep"
            continue
        }

        $ext = [System.IO.Path]::GetExtension($depPath)
        if ($ext -eq '.txt') {
            Write-Output "Installing deps from $dep ..."
            & $venvPip install -r $depPath
        } else {
            Write-Output "Installing package editable from $dep ..."
            & $venvPip install -e .
        }

        if ($LASTEXITCODE -ne 0) {
            Write-Output "ERROR: Dependency installation failed for $dep"
            exit 3
        }
    }
} finally {
    Pop-Location
}

# 4) Register nbstripout git filter if NOTEBOOKS_ENABLED=true
$notebooksEnabled = $false
if (Test-Path $confPath) {
    if (Select-String -Path $confPath -Pattern '^NOTEBOOKS_ENABLED=true$' -Quiet) {
        $notebooksEnabled = $true
    }
}

if ($notebooksEnabled) {
    Write-Output 'Registering nbstripout git filter (NOTEBOOKS_ENABLED=true) ...'
    Push-Location $workspaceRoot
    try {
        & $venvPython -m nbstripout --install
        if ($LASTEXITCODE -eq 0) {
            Write-Output 'nbstripout git filter registered.'
        } else {
            Write-Output 'WARN: nbstripout --install failed. Ensure nbstripout is in requirements-dev.txt.'
        }
    } finally {
        Pop-Location
    }

    $gaPath = Join-Path $workspaceRoot '.gitattributes'
    if (-not (Test-Path $gaPath) -or -not (Select-String -Path $gaPath -Pattern 'filter=nbstripout' -Quiet)) {
        Write-Output 'WARN: .gitattributes is missing or has no nbstripout filter entry.'
        Write-Output '  Add to .gitattributes: *.ipynb filter=nbstripout'
        Write-Output '  Reference: .github/templates/gitattributes-notebooks.txt'
    }
}

# copilot:generated | implementer | 2026-07-13
# 5) Register the large-file commit guard (real git pre-commit hook)
$largeFileHook = Join-Path $workspaceRoot '.github/hooks/git/pre-commit'
if (Test-Path $largeFileHook) {
    Push-Location $workspaceRoot
    try {
        $currentHooksPath = (git config --get core.hooksPath 2>$null)
        if ($currentHooksPath -and $currentHooksPath -ne '.github/hooks/git') {
            Write-Output "WARN: core.hooksPath is already '$currentHooksPath' -- not overwriting (large-file guard not wired)."
            Write-Output '  To enable the guard, invoke check-large-files.py from your existing hook, or run:'
            Write-Output '    git config core.hooksPath .github/hooks/git'
        } else {
            Write-Output 'Registering .github/hooks/git as core.hooksPath (large-file commit guard) ...'
            git config core.hooksPath .github/hooks/git
            if ($LASTEXITCODE -eq 0) {
                Write-Output 'core.hooksPath registered.'
            } else {
                Write-Output 'WARN: git config core.hooksPath failed.'
            }
        }
    } finally {
        Pop-Location
    }
}

Write-Output 'Environment ready.'
exit 0
