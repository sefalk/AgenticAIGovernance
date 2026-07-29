# Regression tests for the Python linting hard gate (issue #6).
#
# The defect: LINTING_STRICTNESS was configured, yet violations shipped.
# Root cause was wiring, not the checker -- the gate's git pathspec covered
# SRC_DIR/ only, and the gate existed solely in the optional refactorer step.
#
# These tests build throwaway git repos, plant a real ruff violation in
# tests/, and drive the actual stop hooks end to end. Run from anywhere:
#   pwsh .github/scripts/test-lint-gate.ps1
# Exits non-zero if any scenario fails (CI-friendly).

$ErrorActionPreference = 'Continue'

$scriptDir = Split-Path -Parent $PSCommandPath
$ghRoot    = (Resolve-Path (Join-Path $scriptDir '..')).Path
$hookDir   = Join-Path $ghRoot 'hooks/scripts'
$repoRoot  = (Resolve-Path (Join-Path $ghRoot '..')).Path

function Resolve-Python {
    foreach ($c in @(
        (Join-Path $repoRoot '.venv/Scripts/python.exe'),
        (Join-Path $repoRoot '.venv/bin/python')
    )) { if (Test-Path $c) { return $c } }
    foreach ($name in @('python3', 'python')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) {
            $v = & $cmd.Source --version 2>&1
            if ($LASTEXITCODE -eq 0 -and $v -match 'Python 3') { return $cmd.Source }
        }
    }
    return $null
}

function Resolve-Ruff {
    foreach ($c in @(
        (Join-Path $repoRoot '.venv/Scripts/ruff.exe'),
        (Join-Path $repoRoot '.venv/bin/ruff')
    )) { if (Test-Path $c) { return $c } }
    $cmd = Get-Command ruff -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$python = Resolve-Python
if (-not $python) {
    Write-Host 'SKIP: no Python 3 interpreter found; cannot run lint gate tests.'
    exit 0
}

$ruff = Resolve-Ruff
if (-not $ruff) {
    Write-Host 'SKIP: ruff not found in .venv or PATH; cannot run lint gate tests.'
    Write-Host '      Install with: pip install ruff'
    exit 0
}

# The hooks resolve ruff through check-python-linting.py, which looks at
# ./.venv first and then PATH. The throwaway repos have no venv, so make the
# resolved ruff reachable via PATH for the child processes.
$origPath = $env:PATH
$env:PATH = (Split-Path -Parent $ruff) + [IO.Path]::PathSeparator + $env:PATH

# pytest is a precondition of both stop hooks (they skip the whole run without
# it). A stub is enough -- test execution itself is not under test here.
$stubBin = Join-Path ([IO.Path]::GetTempPath()) ("lintgate-bin-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $stubBin -Force | Out-Null
"@echo off`r`nexit /b 0" | Set-Content (Join-Path $stubBin 'pytest.cmd') -Encoding ascii
$env:PATH = $stubBin + [IO.Path]::PathSeparator + $env:PATH

$CLEAN_SRC = @'
"""Sample module."""
# copilot:generated | tester | 2026-07-29


def add(a: int, b: int) -> int:
    """Add two numbers.

    Parameters
    ----------
    a : int
        First operand.
    b : int
        Second operand.

    Returns
    -------
    int
        The sum.
    """
    return a + b
'@

$CLEAN_TEST = @'
"""Tests for the sample module."""
# copilot:generated | tester | 2026-07-29

from src.app import add


def test_add():
    assert add(1, 2) == 3
'@

# F401: imported but unused. Caught at every strictness level from 'standard'.
$DIRTY_TEST = @'
"""Tests for the sample module."""
# copilot:generated | tester | 2026-07-29

import os

from src.app import add


def test_add():
    assert add(1, 2) == 3
'@

$CLEAN_TEST_EXTENDED = @'
"""Tests for the sample module."""
# copilot:generated | tester | 2026-07-29

from src.app import add


def test_add():
    assert add(1, 2) == 3


def test_add_zero():
    assert add(1, 0) == 1
'@

$DIRTY_SRC = @'
"""Sample module."""
# copilot:generated | tester | 2026-07-29

import os


def add(a: int, b: int) -> int:
    """Add two numbers.

    Parameters
    ----------
    a : int
        First operand.
    b : int
        Second operand.

    Returns
    -------
    int
        The sum.
    """
    return a + b
'@

function New-GateRepo {
    $repo = Join-Path ([IO.Path]::GetTempPath()) ("lintgate-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $repo -Force | Out-Null

    foreach ($d in @('.github/scripts', '.github/hooks/scripts', 'src', 'tests')) {
        New-Item -ItemType Directory -Path (Join-Path $repo $d) -Force | Out-Null
    }

    "SRC_DIR=src`nLINTING_STRICTNESS=standard" |
        Set-Content (Join-Path $repo '.github/af-env.conf')

    # Real checkers and real hooks -- this is what is under test.
    Copy-Item (Join-Path $ghRoot 'scripts/check-python-linting.py') (Join-Path $repo '.github/scripts/')
    Copy-Item (Join-Path $ghRoot 'scripts/check-python-quality.py') (Join-Path $repo '.github/scripts/')
    Copy-Item (Join-Path $hookDir 'refactorer-stop.ps1') (Join-Path $repo '.github/hooks/scripts/')
    Copy-Item (Join-Path $hookDir 'implementer-stop.ps1') (Join-Path $repo '.github/hooks/scripts/')

    # Stub test runner: the hooks call it for Gate 1, which is not under test.
    "param([string]`$Scope = 'all')`nWrite-Output '1 passed'`nexit 0" |
        Set-Content (Join-Path $repo '.github/scripts/run-tests.ps1')

    $CLEAN_SRC  | Set-Content (Join-Path $repo 'src/app.py')
    $CLEAN_TEST | Set-Content (Join-Path $repo 'tests/test_app.py')

    Push-Location $repo
    try {
        git init -q
        git config user.email t@example.com
        git config user.name tester
        git add -- ':(literal).github' ':(literal)src' ':(literal)tests' | Out-Null
        git commit -qm seed | Out-Null
    } finally { Pop-Location }
    return $repo
}

# Runs a stop hook inside $repo and returns the parsed JSON output.
function Invoke-StopHook {
    param([string]$Repo, [string]$Hook)
    $hookPath = Join-Path $Repo ".github/hooks/scripts/$Hook"
    Push-Location $Repo
    try {
        $out = '{}' | powershell -NoProfile -ExecutionPolicy Bypass -File $hookPath 2>&1
    } finally { Pop-Location }
    $text = ($out | Out-String).Trim()
    return @{ Text = $text; Json = ($text | ConvertFrom-Json -ErrorAction SilentlyContinue) }
}

function Test-Blocked {
    param($Result, [string]$ReasonMatch)
    $d = $Result.Json.hookSpecificOutput.decision
    if ($d -ne 'block') { return $false }
    return ($Result.Json.hookSpecificOutput.reason -match $ReasonMatch)
}

$results = [ordered]@{}
$details = [ordered]@{}
$repos = @()
try {
    # 1. THE REGRESSION: a ruff violation planted in tests/ must block the
    #    refactorer handoff. Before the fix the pathspec was SRC_DIR/ only,
    #    so this returned "all gates PASS".
    $repo = New-GateRepo; $repos += $repo
    $DIRTY_TEST | Set-Content (Join-Path $repo 'tests/test_app.py')
    git -C $repo add -- ':(literal)tests/test_app.py' | Out-Null
    $r = Invoke-StopHook -Repo $repo -Hook 'refactorer-stop.ps1'
    $results['refactorer_blocks_violation_in_tests'] = Test-Blocked $r 'linting gate failed[\s\S]*F401'
    $details['refactorer_blocks_violation_in_tests'] = $r.Text

    # 2. Same violation must block the implementer. Before the fix the lint
    #    gate did not exist there at all, so a skipped Refactor step meant no
    #    linting anywhere.
    $repo = New-GateRepo; $repos += $repo
    $DIRTY_TEST | Set-Content (Join-Path $repo 'tests/test_app.py')
    git -C $repo add -- ':(literal)tests/test_app.py' | Out-Null
    $r = Invoke-StopHook -Repo $repo -Hook 'implementer-stop.ps1'
    $results['implementer_blocks_violation_in_tests'] = Test-Blocked $r 'linting gate failed[\s\S]*F401'
    $details['implementer_blocks_violation_in_tests'] = $r.Text

    # 3. Negative control: a clean edit in tests/ must NOT block. Guards
    #    against "fixed by blocking everything".
    $repo = New-GateRepo; $repos += $repo
    $CLEAN_TEST_EXTENDED | Set-Content (Join-Path $repo 'tests/test_app.py')
    git -C $repo add -- ':(literal)tests/test_app.py' | Out-Null
    $r = Invoke-StopHook -Repo $repo -Hook 'refactorer-stop.ps1'
    $results['refactorer_passes_clean_tests'] = ($r.Json.hookSpecificOutput.decision -ne 'block')
    $details['refactorer_passes_clean_tests'] = $r.Text

    # 4. Scope separation: a violation in tests/ must be reported by the
    #    LINTING gate, not by the quality gate (type hints / docstrings do not
    #    apply to test functions).
    $repo = New-GateRepo; $repos += $repo
    $DIRTY_TEST | Set-Content (Join-Path $repo 'tests/test_app.py')
    git -C $repo add -- ':(literal)tests/test_app.py' | Out-Null
    $r = Invoke-StopHook -Repo $repo -Hook 'implementer-stop.ps1'
    $results['quality_gate_not_applied_to_tests'] =
        ($r.Json.hookSpecificOutput.reason -notmatch 'type hints/docstrings')

    # 5. Violation in SRC_DIR/ still blocks (no regression on the old scope).
    $repo = New-GateRepo; $repos += $repo
    $DIRTY_SRC | Set-Content (Join-Path $repo 'src/app.py')
    git -C $repo add -- ':(literal)src/app.py' | Out-Null
    $r = Invoke-StopHook -Repo $repo -Hook 'refactorer-stop.ps1'
    $results['refactorer_blocks_violation_in_src'] = Test-Blocked $r 'linting gate failed[\s\S]*F401'
    $details['refactorer_blocks_violation_in_src'] = $r.Text
} finally {
    $env:PATH = $origPath
    foreach ($r in $repos) {
        Remove-Item -Recurse -Force $r -ErrorAction SilentlyContinue
    }
    Remove-Item -Recurse -Force $stubBin -ErrorAction SilentlyContinue
}

$failed = 0
Write-Host ''
Write-Host '=== Lint gate regression suite ==='
foreach ($k in $results.Keys) {
    if ($results[$k]) {
        Write-Host ("  PASS  {0}" -f $k)
    } else {
        Write-Host ("  FAIL  {0}" -f $k)
        if ($details.Contains($k)) { Write-Host ("        {0}" -f $details[$k]) }
        $failed++
    }
}
Write-Host ("=== {0}/{1} passed ===" -f ($results.Count - $failed), $results.Count)
exit ($(if ($failed -gt 0) { 1 } else { 0 }))
