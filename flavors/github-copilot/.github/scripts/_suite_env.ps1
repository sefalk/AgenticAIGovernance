# Where a regression suite runs decides what it may assert (#349).
#
# The suites ship into every consumer, but some assertions are facts about this
# framework's own repository -- its CHANGELOG, deploy.ps1, the shipped-default
# af-env.conf. Run inside a consumer they failed for layout reasons alone, and a
# suite that is red for no fault teaches the consumer to ignore red. Dot-source
# this file; ask Test-AfSourceTree before asserting a framework-repo fact, and
# report the skip as `  SKIP  <case> -- <reason>` (no colon: `SKIP:` would mark
# the whole suite skipped in run-all-tests.ps1).

function Test-AfSourceTree {
    param([string]$ScriptsDir = $PSScriptRoot)
    # deploy.ps1 sits beside .github only in the framework payload; a consumer never receives it.
    return (Test-Path (Join-Path (Split-Path (Split-Path $ScriptsDir)) 'deploy.ps1'))
}

function Get-AfSuitePython {
    param([string]$ScriptsDir = $PSScriptRoot)
    $payloadRoot = Split-Path (Split-Path $ScriptsDir)
    $candidates = @()
    # A consumer keeps its venv beside .github; the framework repo two levels higher.
    foreach ($root in @($payloadRoot, (Split-Path (Split-Path $payloadRoot)))) {
        if ($root) {
            $candidates += (Join-Path $root '.venv/Scripts/python.exe')
            $candidates += (Join-Path $root '.venv/bin/python')
        }
    }
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }

    # Probed, not merely resolved: python3 on Windows is a Store stub that exits
    # non-zero, and under -ErrorAction Stop its stderr alone would end the suite.
    $ErrorActionPreference = 'Continue'
    foreach ($name in @($env:AF_PYTHON_OVERRIDE, 'python3', 'python', 'py')) {
        if (-not $name) { continue }
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if (-not $cmd -or -not $cmd.Source) { continue }
        $version = & $cmd.Source --version 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and $version -match 'Python 3') { return $cmd.Source }
    }
    return $null
}
