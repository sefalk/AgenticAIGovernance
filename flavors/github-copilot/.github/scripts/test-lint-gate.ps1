# Regression tests for the Python linting hard gate (issues #6, #10).
#
# #6 -- the defect: LINTING_STRICTNESS was configured, yet violations shipped.
# Root cause was wiring, not the checker -- the gate's git pathspec covered
# SRC_DIR/ only, and the gate existed solely in the optional refactorer step.
#
# #10 -- the gate passed its rule set as a CLI --select, which outranks the
# project's own ruff `ignore`. Explicit project exceptions now win, except for
# CORE_RULES, which no project configuration may switch off.
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

# F401 (unused import) + F821 (undefined name). F821 is in CORE_RULES and must
# survive any project ignore; F401 is not and may be waived by the project.
$UNDEFINED_TEST = @'
"""Tests for the sample module."""
# copilot:generated | tester | 2026-07-29

import os

from src.app import add


def test_add():
    assert add(1, 2) == undefined_total
'@

# Clean but MODIFIED source: a negative control needs a file that actually
# appears in the changed set, otherwise nothing is linted and it proves nothing.
$CLEAN_SRC_EXTENDED = @'
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


def double(a: int) -> int:
    """Double a number.

    Parameters
    ----------
    a : int
        The operand.

    Returns
    -------
    int
        Twice the operand.
    """
    return a * 2
'@

function New-GateRepo {
    param([string]$Pyproject, [switch]$NoTests)

    $repo = Join-Path ([IO.Path]::GetTempPath()) ("lintgate-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $repo -Force | Out-Null

    $dirs = @('.github/scripts', '.github/hooks/scripts', 'src')
    if (-not $NoTests) { $dirs += 'tests' }
    foreach ($d in $dirs) {
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
    if (-not $NoTests) { $CLEAN_TEST | Set-Content (Join-Path $repo 'tests/test_app.py') }
    if ($Pyproject) { $Pyproject | Set-Content (Join-Path $repo 'pyproject.toml') }

    Push-Location $repo
    try {
        git init -q
        git config user.email t@example.com
        git config user.name tester
        git add -- ':(literal).github' ':(literal)src' | Out-Null
        if (-not $NoTests) { git add -- ':(literal)tests' | Out-Null }
        if ($Pyproject) { git add -- ':(literal)pyproject.toml' | Out-Null }
        git commit -qm seed | Out-Null
    } finally { Pop-Location }
    return $repo
}

# PATH with every directory that provides pytest removed, so the hook cannot
# find a test runner. ruff usually lives in the same venv Scripts directory as
# pytest, so it is copied into $ToolBin (a standalone binary) and prepended --
# otherwise the scenario would pass vacuously with the lint gate skipped for
# lack of ruff. Returns $null when ruff cannot be preserved.
function Get-PathWithoutPytest {
    param([string]$ToolBin)
    $sep = [IO.Path]::PathSeparator
    $ruff = Get-Command ruff -ErrorAction SilentlyContinue
    if (-not $ruff) { return $null }
    $kept = $env:PATH -split $sep | Where-Object {
        if (-not $_) { return $false }
        foreach ($n in @('pytest.exe', 'pytest.cmd', 'pytest.bat', 'pytest')) {
            if (Test-Path (Join-Path $_ $n) -ErrorAction SilentlyContinue) { return $false }
        }
        return $true
    }
    New-Item -ItemType Directory -Path $ToolBin -Force | Out-Null
    Copy-Item $ruff.Source -Destination $ToolBin -Force
    $probe = $env:PATH
    try {
        $env:PATH = (@($ToolBin) + $kept) -join $sep
        if (-not (Get-Command python -ErrorAction SilentlyContinue)) { return $null }
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
        if (Get-Command pytest -ErrorAction SilentlyContinue) { return $null }
        return $env:PATH
    } finally {
        $env:PATH = $probe
    }
}

# Runs a stop hook inside $repo and returns the parsed JSON output.
function Invoke-StopHook {
    param([string]$Repo, [string]$Hook, [string]$PathOverride)
    $hookPath = Join-Path $Repo ".github/hooks/scripts/$Hook"
    $savedPath = $env:PATH
    if ($PathOverride) { $env:PATH = $PathOverride }
    Push-Location $Repo
    try {
        $out = '{}' | powershell -NoProfile -ExecutionPolicy Bypass -File $hookPath 2>&1
    } finally {
        Pop-Location
        $env:PATH = $savedPath
    }
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

    # --- Issue #10: project config precedence ---

    # 6. An explicit project ignore wins over the framework rule set. Before
    #    the fix the CLI --select outranked the project's own ruff config, so
    #    a codebase that is clean by its own contract was blocked.
    $repo = New-GateRepo -Pyproject "[tool.ruff.lint]`nignore = [`"F401`"]"
    $repos += $repo
    $DIRTY_TEST | Set-Content (Join-Path $repo 'tests/test_app.py')
    git -C $repo add -- ':(literal)tests/test_app.py' | Out-Null
    $r = Invoke-StopHook -Repo $repo -Hook 'implementer-stop.ps1'
    $results['project_ignore_is_honoured'] = ($r.Json.hookSpecificOutput.decision -ne 'block')
    $details['project_ignore_is_honoured'] = $r.Text

    # 7. Not selecting a rule is NOT an exception. The project selects only E,
    #    yet the framework floor still enforces F401. Guards against "project
    #    config wins" collapsing into "project config replaces".
    $repo = New-GateRepo -Pyproject "[tool.ruff.lint]`nselect = [`"E`"]"
    $repos += $repo
    $DIRTY_TEST | Set-Content (Join-Path $repo 'tests/test_app.py')
    git -C $repo add -- ':(literal)tests/test_app.py' | Out-Null
    $r = Invoke-StopHook -Repo $repo -Hook 'implementer-stop.ps1'
    $results['floor_applies_to_unselected_rule'] = Test-Blocked $r 'linting gate failed[\s\S]*F401'
    $details['floor_applies_to_unselected_rule'] = $r.Text

    # 8. CORE_RULES survive an EXACT project ignore. ruff resolves selectors by
    #    specificity, so --extend-select alone loses to ignore = ["F821"];
    #    the checker must drop such entries from the passthrough.
    $repo = New-GateRepo -Pyproject "[tool.ruff.lint]`nignore = [`"F821`"]"
    $repos += $repo
    $UNDEFINED_TEST | Set-Content (Join-Path $repo 'tests/test_app.py')
    git -C $repo add -- ':(literal)tests/test_app.py' | Out-Null
    $r = Invoke-StopHook -Repo $repo -Hook 'implementer-stop.ps1'
    $results['core_survives_exact_ignore'] = Test-Blocked $r 'linting gate failed[\s\S]*F821'
    $details['core_survives_exact_ignore'] = $r.Text

    # 9. CORE_RULES survive a BROAD project ignore, while the rest of that
    #    ignore is still honoured: F821 blocks, F401 does not appear.
    $repo = New-GateRepo -Pyproject "[tool.ruff.lint]`nignore = [`"F`"]"
    $repos += $repo
    $UNDEFINED_TEST | Set-Content (Join-Path $repo 'tests/test_app.py')
    git -C $repo add -- ':(literal)tests/test_app.py' | Out-Null
    $r = Invoke-StopHook -Repo $repo -Hook 'implementer-stop.ps1'
    $results['core_survives_broad_ignore'] =
        (Test-Blocked $r 'linting gate failed[\s\S]*F821') -and
        ($r.Json.hookSpecificOutput.reason -notmatch 'F401')
    $details['core_survives_broad_ignore'] = $r.Text

    # --- Issue #12: gate reachability ---
    # The lint gate sits behind the test gate's early returns. A missing test
    # runner must skip the TEST gate only -- ruff needs neither pytest nor a
    # tests/ directory, so linting must still run and still block.

    # 10./11. No tests/ directory: a violation in SRC_DIR/ must still block.
    foreach ($hook in @('implementer-stop.ps1', 'refactorer-stop.ps1')) {
        $repo = New-GateRepo -NoTests; $repos += $repo
        $DIRTY_SRC | Set-Content (Join-Path $repo 'src/app.py')
        git -C $repo add -- ':(literal)src/app.py' | Out-Null
        $r = Invoke-StopHook -Repo $repo -Hook $hook
        $key = 'lint_runs_without_tests_dir_' + $hook.Split('-')[0]
        $results[$key] = Test-Blocked $r 'linting gate failed[\s\S]*F401'
        $details[$key] = $r.Text
    }

    # 12. No pytest on PATH: same expectation. git, python and ruff remain
    #     reachable, only the test runner is gone.
    $toolBin = Join-Path ([IO.Path]::GetTempPath()) ("lintgate-bin-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $repos += $toolBin
    $noPytestPath = Get-PathWithoutPytest -ToolBin $toolBin
    if (-not $noPytestPath) {
        Write-Host '  SKIP  lint_runs_without_pytest (cannot build a pytest-free PATH that keeps git/python/ruff)'
    } else {
        $repo = New-GateRepo; $repos += $repo
        $DIRTY_SRC | Set-Content (Join-Path $repo 'src/app.py')
        git -C $repo add -- ':(literal)src/app.py' | Out-Null
        $r = Invoke-StopHook -Repo $repo -Hook 'implementer-stop.ps1' -PathOverride $noPytestPath
        $results['lint_runs_without_pytest'] = Test-Blocked $r 'linting gate failed[\s\S]*F401'
        $details['lint_runs_without_pytest'] = $r.Text
    }

    # 13. Negative control + visibility: a clean tree without tests/ must NOT
    #     block, and the output must still say the test gate was skipped.
    $repo = New-GateRepo -NoTests; $repos += $repo
    $CLEAN_SRC_EXTENDED | Set-Content (Join-Path $repo 'src/app.py')
    git -C $repo add -- ':(literal)src/app.py' | Out-Null
    $r = Invoke-StopHook -Repo $repo -Hook 'implementer-stop.ps1'
    $results['clean_repo_without_tests_dir_passes'] =
        ($r.Json.hookSpecificOutput.decision -ne 'block') -and
        ($r.Text -match 'skipped')
    $details['clean_repo_without_tests_dir_passes'] = $r.Text
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
