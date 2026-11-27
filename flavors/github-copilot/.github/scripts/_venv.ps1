# Shared venv resolution for the runners (#579). Dot-source, then:
#
#   $venv = Resolve-AfVenv $workspaceRoot -Bootstrap
#   if (-not $venv.Python) { $venv.Message | Write-Output; exit 1 }
#   Enable-AfVenv $venv
#
# Search order, first hit wins:
#   workspace  <workspaceRoot>/.venv
#   toplevel   <git toplevel>/.venv     -- the payload sits below the repo root
#   shared     <main checkout>/.venv    -- a worktree, only when
#                                          WORKTREE_VENV_MODE=shared (default)
# Nothing found: with -Bootstrap and PY_ENV_BOOTSTRAP=always (default) the
# caller runs bootstrap-python-env, which creates <workspaceRoot>/.venv, and
# resolves again -- an agent must not wait on a human for a venv (#579).
# ask/off, or a failed bootstrap, is BLOCKED and names the script to run.
# Hooks resolve without -Bootstrap: a pip install cannot finish in a hook's
# timeout. _venv.sh is the bash twin of this file; keep both in step.

function Get-AfVenvPython([string]$Dir) {
    foreach ($rel in @('.venv/Scripts/python.exe', '.venv/bin/python')) {
        $p = Join-Path $Dir $rel
        if (Test-Path -LiteralPath $p -PathType Leaf) { return $p }
    }
    return $null
}

function ConvertTo-AfFullPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Get-AfVenvConf([string]$Conf, [string]$Key, [string]$Default) {
    if (-not (Test-Path -LiteralPath $Conf)) { return $Default }
    $m = Select-String -LiteralPath $Conf -Pattern ('^{0}=(.+)$' -f $Key) | Select-Object -First 1
    if ($m) {
        $v = $m.Matches[0].Groups[1].Value.Trim().Trim('"', "'")
        if ($v) { return $v }
    }
    return $Default
}

function Resolve-AfVenv([string]$WorkspaceRoot, [switch]$Bootstrap) {
    $ws = ConvertTo-AfFullPath $WorkspaceRoot
    $conf = Join-Path $ws '.github/af-env.conf'
    $mode = Get-AfVenvConf $conf 'WORKTREE_VENV_MODE' 'shared'

    $candidates = @([pscustomobject]@{ Dir = $ws; Source = 'workspace' })
    $toplevel = $ws
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $top = & git -C $ws rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $top) {
            $toplevel = ConvertTo-AfFullPath $top
            if ($toplevel -ne $ws) {
                $candidates += [pscustomobject]@{ Dir = $toplevel; Source = 'toplevel' }
            }
            if ($mode -eq 'shared') {
                $common = & git -C $ws rev-parse --path-format=absolute --git-common-dir 2>$null
                if ($LASTEXITCODE -ne 0 -or -not $common) {
                    $common = & git -C $ws rev-parse --git-common-dir 2>$null
                    if ($common -and -not [IO.Path]::IsPathRooted($common)) { $common = Join-Path $ws $common }
                }
                # Only a non-bare repository's .git has a checkout as its parent;
                # a submodule's common dir (.git/modules/x) does not.
                if ($common -and (Split-Path -Leaf (ConvertTo-AfFullPath $common)) -eq '.git') {
                    $main = ConvertTo-AfFullPath (Split-Path -Parent (ConvertTo-AfFullPath $common))
                    if ($main -ne $ws -and $main -ne $toplevel) {
                        $candidates += [pscustomobject]@{ Dir = $main; Source = 'shared' }
                    }
                }
            }
        }
    }

    foreach ($c in $candidates) {
        $py = Get-AfVenvPython $c.Dir
        if ($py) {
            return [pscustomobject]@{
                Python   = $py
                Bin      = Split-Path -Parent $py
                Root     = $c.Dir
                Source   = $c.Source
                Toplevel = $toplevel
                Mode     = $mode
                Message  = ''
            }
        }
    }

    $searched = ($candidates | ForEach-Object { Join-Path $_.Dir '.venv' }) -join ', '
    $notFound = "ERROR: venv python not found under $ws/.venv (searched: $searched; WORKTREE_VENV_MODE=$mode)"
    $policy = (Get-AfVenvConf $conf 'PY_ENV_BOOTSTRAP' 'always').ToLower()
    $bootstrapScript = Join-Path $ws '.github/scripts/bootstrap-python-env.ps1'
    if ($Bootstrap -and $policy -eq 'always' -and (Test-Path -LiteralPath $bootstrapScript)) {
        Write-Host "$notFound"
        Write-Host 'NOTE: PY_ENV_BOOTSTRAP=always -- creating the venv with .github/scripts/bootstrap-python-env.ps1'
        $psHost = (Get-Process -Id $PID).Path
        & $psHost -NoProfile -ExecutionPolicy Bypass -File $bootstrapScript 2>&1 | ForEach-Object { Write-Host "$_" }
        $code = $LASTEXITCODE
        if ($code -eq 0) {
            $again = Resolve-AfVenv $ws
            if ($again.Python) { return $again }
        }
        $message = @(
            "BLOCKED: venv bootstrap failed (bootstrap-python-env.ps1 exit $code); its output is above."
            '  Fix the cause and run .github/scripts/bootstrap-python-env.ps1 (task ''env: bootstrap python'').'
        ) -join [Environment]::NewLine
    } else {
        $why = if (-not $Bootstrap) { 'this caller does not create venvs' }
               elseif ($policy -ne 'always') { "PY_ENV_BOOTSTRAP=$policy does not let a runner create one" }
               else { 'bootstrap-python-env.ps1 is not deployed' }
        $message = @(
            $notFound
            "BLOCKED: no usable venv for this checkout, and $why. Create it with:"
            '  .github/scripts/bootstrap-python-env.ps1 (task ''env: bootstrap python'')'
            '  worktree in isolated mode: .github/scripts/setup-worktree.ps1'
            '  or set PY_ENV_BOOTSTRAP=always in .github/af-env.conf so the runners create it.'
        ) -join [Environment]::NewLine
    }
    return [pscustomobject]@{
        Python = $null; Bin = $null; Root = $null; Source = $null
        Toplevel = $toplevel; Mode = $mode; Message = $message
    }
}

# Puts the venv's bin first on PATH, so tools the runner spawns (ruff via
# check-python-linting.py, pytest plugins) come from the same venv as the
# interpreter, and says where the venv came from when it is not the workspace's.
function Enable-AfVenv($Venv) {
    $env:PATH = $Venv.Bin + [IO.Path]::PathSeparator + $env:PATH
    if ($Venv.Source -ne 'workspace') {
        Write-Output "NOTE: venv: $($Venv.Source) -> $($Venv.Root)"
    }
}

# A shared venv is the main checkout's. If the main checkout is installed
# into it editable, pytest in this worktree imports the main checkout's code
# and reports on code nobody changed. Returns $null when safe, else a message.
function Test-AfVenvIsolation($Venv, [string]$ScriptDir) {
    if ($Venv.Source -ne 'shared') { return $null }
    $guard = Join-Path $ScriptDir 'check-venv-editable.py'
    $found = & $Venv.Python $guard --foreign-root $Venv.Root --workspace $Venv.Toplevel 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { return $null }
    return @(
        $found.TrimEnd()
        "BLOCKED: the shared venv at $($Venv.Root) imports code from the main checkout, not this worktree."
        '  Set WORKTREE_VENV_MODE=isolated in .github/af-env.conf and run .github/scripts/setup-worktree.ps1 to create the worktree venv.'
    ) -join [Environment]::NewLine
}

# ruff formats differently between releases, so a local ruff that is not the
# one CI pins passes `ruff format --check` here and fails it there. Reads the
# ruff==X pin from DEP_DEV_FILE (workspace, then git toplevel) and returns a
# warning when the venv's ruff differs, else $null. Never blocks: a project
# without a pin, or a venv without ruff, has nothing to compare.
function Get-AfRuffPinWarning($Venv, [string]$WorkspaceRoot) {
    $ws = ConvertTo-AfFullPath $WorkspaceRoot
    $depFile = Get-AfVenvConf (Join-Path $ws '.github/af-env.conf') 'DEP_DEV_FILE' 'requirements-dev.txt'
    $pin = $null
    foreach ($dir in @($ws, $Venv.Toplevel) | Select-Object -Unique) {
        $p = Join-Path $dir $depFile
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
        $m = [regex]::Match([IO.File]::ReadAllText($p), '(?im)^\s*["'']?ruff\s*==\s*([0-9][0-9A-Za-z.+!-]*)')
        if ($m.Success) { $pin = $m.Groups[1].Value; break }
    }
    if (-not $pin) { return $null }
    $out = (& $Venv.Python -m ruff --version 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $out -notmatch '([0-9][0-9A-Za-z.+!-]*)\s*$') { return $null }
    $have = $Matches[1]
    if ($have -eq $pin) { return $null }
    return "WARN: venv ruff $have differs from the ruff==$pin pin in $depFile; formatting may pass here and fail in CI. Re-run .github/scripts/bootstrap-python-env.ps1 to install the pinned version."
}