# Regression tests for the shared venv resolver of the runners (#579).
#
# The runners looked for an interpreter in exactly one place,
# <workspaceRoot>/.venv. A git worktree made by setup-worktree in its default
# WORKTREE_VENV_MODE=shared has no venv of its own, and in the framework repo
# the payload root (flavors/github-copilot) has none either. Both runners
# therefore stopped with "venv python not found" wherever agents actually work,
# and the only way left to format or lint was a bare `ruff` -- outside
# LINTING_STRICTNESS (#124), and how #577 was hit.
#
# Every case runs the SHIPPED runners in real git repositories with real venvs
# (created --without-pip, so no network), in both dialects:
#   A  plain checkout, own .venv          -> uses it, says nothing extra
#   B  worktree, shared, main has .venv   -> uses the main checkout's venv
#   C  worktree, isolated, no own .venv   -> BLOCKED, names setup-worktree
#   D  payload below the git toplevel     -> uses <toplevel>/.venv
#   E  run-tests in B                     -> runs, and ruff on PATH is the venv's
#   F  run-tests, shared venv carries an editable install of the main checkout
#                                         -> BLOCKED, names isolated
#   G  no venv anywhere, PY_ENV_BOOTSTRAP unset (default always)
#                                         -> the runner bootstraps, then runs
#   H  no venv anywhere, PY_ENV_BOOTSTRAP=ask
#                                         -> BLOCKED, names the bootstrap script
#   I  no venv anywhere, bootstrap fails  -> BLOCKED, says the bootstrap failed
#   J  venv ruff differs from the ruff==X pin in DEP_DEV_FILE -> WARN, still runs
#   K  venv ruff matches the pin          -> no WARN
#   L  hook Get-AfPytest / af_resolve_pytest, payload below the toplevel
#                                         -> the toplevel venv, as the runners
#   M  coordinator hook, PY_ENV_BOOTSTRAP=always, no venv
#                                         -> raw python denied (bootstrap named),
#                                            runner passes, nothing installed
# The bootstrap is a stub in G-I: it makes a --without-pip venv, no network.
#
# Run from anywhere:
#   powershell -File .github/scripts/test-venv-resolver.ps1
# Exits non-zero if any case fails.
$ErrorActionPreference = 'Continue'

$scriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptDir '_suite_env.ps1')

$python = @(Get-AfSuitePython $scriptDir)
if ($python.Count -eq 0 -or -not $python[0]) {
    Write-Host 'SKIP: no Python 3 interpreter found; cannot build venv fixtures.'
    exit 0
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host 'SKIP: git not found; the resolver cases need real worktrees.'
    exit 0
}
$psHost = (Get-Process -Id $PID).Path

$bashExe = $null
foreach ($c in @('C:\Program Files\Git\bin\bash.exe', '/bin/bash', '/usr/bin/bash')) {
    if (Test-Path $c) { $bashExe = $c; break }
}
if (-not $bashExe) { $bashExe = (Get-Command bash -ErrorAction SilentlyContinue).Source }

$shipped = @('run-lint.ps1', 'run-lint.sh', 'run-tests.ps1', 'run-tests.sh',
    '_venv.ps1', '_venv.sh', 'check-venv-editable.py')

$results = [ordered]@{}
$details = @{}
$fixtures = @()

function Add-Result([string]$Name, [bool]$Ok, [string]$Detail) {
    $script:results[$Name] = $Ok
    if (-not $Ok) { $script:details[$Name] = $Detail }
}

function Invoke-Git([string]$Dir, [string[]]$GitArgs) {
    & git -C $Dir @GitArgs 2>&1 | Out-Null
}

# A repository whose payload (.github/scripts + af-env.conf) sits at $Payload
# below the root. Paths contain a space on purpose: every default OneDrive path
# does, and a resolver that splits on it is broken where users actually work.
function New-Repo([string]$Tag, [string]$Mode = 'shared', [string]$Payload = '', [string]$Extra = 'PY_ENV_BOOTSTRAP=off') {
    $root = Join-Path ([IO.Path]::GetTempPath()) ("af venv $Tag " + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $script:fixtures += $root
    $payloadDir = if ($Payload) { Join-Path $root $Payload } else { $root }
    $scripts = Join-Path $payloadDir '.github/scripts'
    New-Item -ItemType Directory -Path $scripts -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $payloadDir 'tests') -Force | Out-Null
    foreach ($f in $shipped) {
        $src = Join-Path $scriptDir $f
        if (Test-Path $src) { Copy-Item $src (Join-Path $scripts $f) }
    }
    [IO.File]::WriteAllText((Join-Path $payloadDir '.github/af-env.conf'), "SRC_DIR=src`nWORKTREE_VENV_MODE=$Mode`n$Extra`n")
    [IO.File]::WriteAllText((Join-Path $payloadDir 'tests/test_x.py'), "def test_x():`n    pass`n")
    [IO.File]::WriteAllText((Join-Path $root '.gitignore'), ".venv/`n")
    Invoke-Git $root @('init', '-q')
    Invoke-Git $root @('config', 'user.email', 'suite@example.invalid')
    Invoke-Git $root @('config', 'user.name', 'suite')
    Invoke-Git $root @('add', '--', '.gitignore', (Join-Path $payloadDir '.github'), (Join-Path $payloadDir 'tests'))
    Invoke-Git $root @('commit', '-q', '-m', 'fixture')
    return $root
}

function New-Worktree([string]$Root) {
    $wt = "$Root-wt"
    $script:fixtures += $wt
    Invoke-Git $Root @('worktree', 'add', '-q', '--detach', $wt)
    return $wt
}

# A real venv with a fake pytest and a fake ruff. The fake pytest reports which
# ruff the runner's PATH resolves, so the case observes the PATH it was given
# rather than trusting the runner's own note.
function New-Venv([string]$Dir, [string]$EditableTarget = '') {
    $venv = Join-Path $Dir '.venv'
    $pre = if ($python.Count -gt 1) { $python[1..($python.Count - 1)] } else { @() }
    & $python[0] @pre -m venv --without-pip $venv *> $null
    $py = Join-Path $venv 'Scripts/python.exe'
    $bin = Join-Path $venv 'Scripts'
    if (-not (Test-Path $py)) { $py = Join-Path $venv 'bin/python'; $bin = Join-Path $venv 'bin' }
    if (-not (Test-Path $py)) { return $null }
    $site = (& $py -c "import sysconfig; print(sysconfig.get_paths()['purelib'])" 2>$null)
    if (-not $site) { return $null }
    $pkg = Join-Path $site 'pytest'
    New-Item -ItemType Directory -Path $pkg -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $pkg '__init__.py'), '')
    [IO.File]::WriteAllText((Join-Path $pkg '__main__.py'),
        "import shutil`nprint('ruff-at: ' + str(shutil.which('ruff')))`nprint('3 passed in 0.42s')`n")
    $rpkg = Join-Path $site 'ruff'
    New-Item -ItemType Directory -Path $rpkg -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $rpkg '__init__.py'), '')
    [IO.File]::WriteAllText((Join-Path $rpkg '__main__.py'), "print('ruff 0.0.0')`n")
    if (Test-Path (Join-Path $venv 'Scripts')) {
        [IO.File]::WriteAllText((Join-Path $bin 'ruff.bat'), "@echo ruff 0.0.0`r`n")
    } else {
        [IO.File]::WriteAllText((Join-Path $bin 'ruff'), "#!/bin/sh`necho ruff 0.0.0`n")
        & chmod +x (Join-Path $bin 'ruff')
    }
    if ($EditableTarget) {
        $info = Join-Path $site 'demo-0.1.dist-info'
        New-Item -ItemType Directory -Path $info -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $info 'METADATA'), "Metadata-Version: 2.1`nName: demo`nVersion: 0.1`n")
        $uri = ([Uri](Resolve-Path $EditableTarget).Path).AbsoluteUri
        [IO.File]::WriteAllText((Join-Path $info 'direct_url.json'), "{`"url`": `"$uri`", `"dir_info`": {`"editable`": true}}")
    }
    return $bin
}

# Stands in for bootstrap-python-env in both dialects: says it ran, then either
# makes a bare venv at the workspace root (exit 0) or fails with $Exit.
function Add-BootstrapStub([string]$Payload, [int]$Exit) {
    $scripts = Join-Path $Payload '.github/scripts'
    $py = $python[0] -replace '\\', '/'
    $pre = if ($python.Count -gt 1) { ' ' + ($python[1..($python.Count - 1)] -join ' ') } else { '' }
    $ps = @(
        "Write-Output 'stub-bootstrap ran'"
        "if ($Exit -ne 0) { exit $Exit }"
        "& '$py'$pre -m venv --without-pip (Join-Path `$PSScriptRoot '../../.venv')"
        "exit 0"
    ) -join "`n"
    $sh = @(
        '#!/usr/bin/env bash'
        'echo "stub-bootstrap ran"'
        "[ $Exit -ne 0 ] && exit $Exit"
        "'$py'$pre -m venv --without-pip `"`$(dirname `"`$0`")/../../.venv`""
        'exit 0'
    ) -join "`n"
    [IO.File]::WriteAllText((Join-Path $scripts 'bootstrap-python-env.ps1'), "$ps`n")
    [IO.File]::WriteAllText((Join-Path $scripts 'bootstrap-python-env.sh'), "$sh`n")
}

function Invoke-Runner([string]$Dialect, [string]$Payload, [string]$Runner, [string[]]$PsArgs, [string]$ShArgs) {
    $scripts = Join-Path $Payload '.github/scripts'
    if ($Dialect -eq 'ps') {
        $out = & $psHost -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts "$Runner.ps1") @PsArgs 2>&1 | Out-String
    } else {
        $sh = (Join-Path $scripts "$Runner.sh") -replace '\\', '/'
        $out = & $bashExe -c "'$sh' $ShArgs" 2>&1 | Out-String
    }
    return @{ Out = $out; Code = $LASTEXITCODE }
}

function Test-Lint([string]$Name, [string]$Payload, [scriptblock]$Check) {
    foreach ($d in @('ps', 'sh')) {
        if ($d -eq 'sh' -and -not $bashExe) { Add-Result "${Name}_$d" $false 'no bash interpreter found'; continue }
        # Scope src has no files in the fixture: the runner resolves the venv
        # first, then reports an empty scope -- exit 0 proves resolution alone.
        $r = Invoke-Runner $d $Payload 'run-lint' @('-Scope', 'src') '--scope src'
        Add-Result "${Name}_$d" (& $Check $r) "exit=$($r.Code) out=$($r.Out.Trim())"
    }
}

function Test-Run([string]$Name, [string]$Payload, [scriptblock]$Check) {
    foreach ($d in @('ps', 'sh')) {
        if ($d -eq 'sh' -and -not $bashExe) { Add-Result "${Name}_$d" $false 'no bash interpreter found'; continue }
        $r = Invoke-Runner $d $Payload 'run-tests' @('-Scope', 'all') '--scope all'
        Add-Result "${Name}_$d" (& $Check $r) "exit=$($r.Code) out=$($r.Out.Trim())"
    }
}

try {
    # A: plain checkout with its own venv.
    $a = New-Repo 'a'
    $aBin = New-Venv $a
    Test-Lint 'A_checkout_uses_its_own_venv' $a {
        param($r) $r.Code -eq 0 -and $r.Out -match 'no Python files in scope' -and $r.Out -notmatch 'venv: (shared|toplevel)'
    }

    # B + E: worktree in shared mode; only the main checkout has a venv.
    $b = New-Repo 'b'
    $bBin = New-Venv $b
    $bWt = New-Worktree $b
    Test-Lint 'B_shared_worktree_uses_main_checkout_venv' $bWt {
        param($r) $r.Code -eq 0 -and $r.Out -match 'no Python files in scope' -and $r.Out -match 'venv: shared'
    }
    $bBinLeaf = Split-Path $bBin -Leaf
    Test-Run 'E_shared_worktree_runs_tests_with_venv_ruff' $bWt {
        param($r)
        $at = if ($r.Out -match 'ruff-at: (.+)') { $Matches[1].Trim() -replace '\\', '/' } else { '' }
        # Git Bash reports /c/... for C:/..., so compare from the venv folder down.
        $r.Code -eq 0 -and $r.Out -match '3 passed' -and $at -match "/\.venv/$bBinLeaf/ruff"
    }

    # C: isolated mode never borrows the main checkout's venv, even when it exists.
    $c = New-Repo 'c' 'isolated'
    $null = New-Venv $c
    $cWt = New-Worktree $c
    Test-Lint 'C_isolated_worktree_without_venv_is_blocked' $cWt {
        param($r) $r.Code -eq 1 -and $r.Out -match 'venv python not found' -and $r.Out -match 'BLOCKED' -and $r.Out -match 'setup-worktree'
    }

    # D: the payload sits below the git toplevel (the framework repo's own layout).
    $d = New-Repo 'd' 'shared' 'flavor'
    $null = New-Venv $d
    Test-Lint 'D_payload_below_toplevel_uses_toplevel_venv' (Join-Path $d 'flavor') {
        param($r) $r.Code -eq 0 -and $r.Out -match 'no Python files in scope' -and $r.Out -match 'venv: toplevel'
    }

    # F: the shared venv carries an editable install of the main checkout, so
    # pytest in the worktree would import the main checkout's code.
    $f = New-Repo 'f'
    $null = New-Venv $f $f
    $fWt = New-Worktree $f
    Test-Run 'F_shared_venv_with_editable_main_install_is_blocked' $fWt {
        param($r) $r.Code -eq 1 -and $r.Out -match 'BLOCKED' -and $r.Out -match 'isolated' -and $r.Out -notmatch '3 passed'
    }

    # G-I: one fresh repository per dialect, because a bootstrap that worked
    # in the first dialect would leave a venv behind for the second.
    foreach ($d in @('ps', 'sh')) {
        if ($d -eq 'sh' -and -not $bashExe) {
            foreach ($n in 'G', 'H', 'I') { Add-Result "${n}_$d" $false 'no bash interpreter found' }
            continue
        }
        $g = New-Repo "g$d" 'shared' '' ''
        Add-BootstrapStub $g 0
        $r = Invoke-Runner $d $g 'run-lint' @('-Scope', 'src') '--scope src'
        Add-Result "G_no_venv_default_bootstrap_runs_then_lints_$d" (
            $r.Code -eq 0 -and $r.Out -match 'stub-bootstrap ran' -and $r.Out -match 'no Python files in scope'
        ) "exit=$($r.Code) out=$($r.Out.Trim())"

        $h = New-Repo "h$d" 'shared' '' 'PY_ENV_BOOTSTRAP=ask'
        Add-BootstrapStub $h 0
        $r = Invoke-Runner $d $h 'run-lint' @('-Scope', 'src') '--scope src'
        Add-Result "H_no_venv_bootstrap_ask_is_blocked_$d" (
            $r.Code -eq 1 -and $r.Out -match 'BLOCKED' -and $r.Out -match 'bootstrap-python-env' -and
            $r.Out -match 'PY_ENV_BOOTSTRAP' -and $r.Out -notmatch 'stub-bootstrap ran'
        ) "exit=$($r.Code) out=$($r.Out.Trim())"

        $i = New-Repo "i$d" 'shared' '' ''
        Add-BootstrapStub $i 3
        $r = Invoke-Runner $d $i 'run-lint' @('-Scope', 'src') '--scope src'
        Add-Result "I_no_venv_bootstrap_failure_is_blocked_$d" (
            $r.Code -eq 1 -and $r.Out -match 'stub-bootstrap ran' -and $r.Out -match 'BLOCKED' -and $r.Out -match 'bootstrap.*failed'
        ) "exit=$($r.Code) out=$($r.Out.Trim())"
    }

    # J + K: the fake venv ruff reports 0.0.0.
    $j = New-Repo 'j'
    $null = New-Venv $j
    [IO.File]::WriteAllText((Join-Path $j 'requirements-dev.txt'), "pytest`nruff==0.16.2  # CI pin`n")
    Test-Lint 'J_ruff_differs_from_pin_warns' $j {
        param($r) $r.Code -eq 0 -and $r.Out -match 'WARN' -and $r.Out -match '0\.0\.0' -and $r.Out -match '0\.16\.2'
    }
    $k = New-Repo 'k'
    $null = New-Venv $k
    [IO.File]::WriteAllText((Join-Path $k 'requirements-dev.txt'), "ruff==0.0.0`n")
    Test-Lint 'K_ruff_matches_pin_is_silent' $k {
        param($r) $r.Code -eq 0 -and $r.Out -match 'no Python files in scope' -and $r.Out -notmatch 'WARN'
    }

    # L: the hooks find the project's pytest where the runners do. The hooks
    # are deployed at the payload root, which has no venv of its own here.
    $l = New-Repo 'l' 'shared' 'flavor'
    $null = New-Venv $l
    $lHooks = Join-Path $l 'flavor/.github/hooks/scripts'
    New-Item -ItemType Directory -Path $lHooks -Force | Out-Null
    foreach ($f in '_common.ps1', '_common.sh') {
        Copy-Item (Join-Path $scriptDir "../hooks/scripts/$f") (Join-Path $lHooks $f)
    }
    $expect = '/\.venv/(Scripts|bin)/python'
    $common = Join-Path $lHooks '_common.ps1'
    $out = & $psHost -NoProfile -ExecutionPolicy Bypass -Command ". '$common'; (Get-AfPytest) -join ' '" 2>&1 | Out-String
    $norm = $out.Trim() -replace '\\', '/'
    $lRoot = ((Resolve-Path $l).Path -replace '\\', '/')
    Add-Result 'L_hook_pytest_uses_toplevel_venv_ps' (
        $norm.StartsWith("$lRoot/.venv/") -and $norm -match $expect -and $norm -match '-m pytest$'
    ) "out=$norm"
    if ($bashExe) {
        $sh = (Join-Path $lHooks '_common.sh') -replace '\\', '/'
        $out = & $bashExe -c ". '$sh'; af_resolve_pytest; echo `${AF_PYTEST[*]}" 2>&1 | Out-String
        $norm = $out.Trim()
        Add-Result 'L_hook_pytest_uses_toplevel_venv_sh' (
            $norm -match "$([regex]::Escape((Split-Path $l -Leaf)))/\.venv/" -and $norm -match $expect -and $norm -match '-m pytest$'
        ) "out=$norm"
    } else {
        Add-Result 'L_hook_pytest_uses_toplevel_venv_sh' $false 'no bash interpreter found'
    }

    # M: the coordinator hook never pip-installs inside its timeout. Under
    # PY_ENV_BOOTSTRAP=always with no venv, a raw Python command is denied with
    # the bootstrap named; a runner passes, because it bootstraps itself.
    $m = New-Repo 'm' 'shared' '' 'PY_ENV_BOOTSTRAP=always'
    $mHooks = Join-Path $m '.github/hooks/scripts'
    New-Item -ItemType Directory -Path $mHooks -Force | Out-Null
    foreach ($f in '_common.ps1', '_common.sh', 'coordinator-pretooluse.ps1', 'coordinator-pretooluse.sh') {
        Copy-Item (Join-Path $scriptDir "../hooks/scripts/$f") (Join-Path $mHooks $f)
    }
    $raw = '{"tool_name":"run_in_terminal","tool_input":{"command":"python -c 1"}}'
    $runner = '{"tool_name":"run_in_terminal","tool_input":{"command":".github/scripts/run-lint.ps1 -Scope changed"}}'
    foreach ($d in @('ps', 'sh')) {
        if ($d -eq 'sh' -and -not $bashExe) { Add-Result "M_coordinator_hook_$d" $false 'no bash interpreter found'; continue }
        $outs = foreach ($payload in $raw, $runner) {
            if ($d -eq 'ps') {
                $payload | & $psHost -NoProfile -ExecutionPolicy Bypass -File (Join-Path $mHooks 'coordinator-pretooluse.ps1') 2>&1 | Out-String
            } else {
                $payload | & $bashExe ((Join-Path $mHooks 'coordinator-pretooluse.sh') -replace '\\', '/') 2>&1 | Out-String
            }
        }
        Add-Result "M_coordinator_hook_denies_raw_python_passes_runner_$d" (
            $outs[0] -match '"deny"' -and $outs[0] -match 'bootstrap-python-env' -and $outs[1] -notmatch 'deny|ask' -and
            -not (Test-Path (Join-Path $m '.venv'))
        ) "raw=$($outs[0].Trim()) runner=$($outs[1].Trim())"
    }
} finally {
    foreach ($p in $fixtures) {
        if (Test-Path $p) { Remove-Item -Recurse -Force $p -ErrorAction SilentlyContinue }
    }
}

$failed = @($results.Keys | Where-Object { -not $results[$_] })
foreach ($k in $results.Keys) {
    if ($results[$k]) { Write-Host "  PASS  $k" } else { Write-Host "  FAIL  $k -- $($details[$k])" }
}
Write-Host ''
Write-Host "Passed: $($results.Count - $failed.Count)  Failed: $($failed.Count)"
if ($failed.Count -gt 0) { exit 1 }
exit 0
