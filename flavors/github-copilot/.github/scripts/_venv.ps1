# Shared venv resolution for the runners (#579). Dot-source, then:
#
#   $venv = Resolve-AfVenv $workspaceRoot
#   if (-not $venv.Python) { $venv.Message | Write-Output; exit 1 }
#   Enable-AfVenv $venv
#
# Search order, first hit wins:
#   workspace  <workspaceRoot>/.venv
#   toplevel   <git toplevel>/.venv     -- the payload sits below the repo root
#   shared     <main checkout>/.venv    -- a worktree, only when
#                                          WORKTREE_VENV_MODE=shared (default)
# Nothing found is BLOCKED: creating a venv installs packages, which is a step
# a human approves (setup-worktree / bootstrap-python-env), never a runner.
# _venv.sh is the bash twin of this file; keep both in step.

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

function Resolve-AfVenv([string]$WorkspaceRoot) {
    $ws = ConvertTo-AfFullPath $WorkspaceRoot
    $mode = 'shared'
    $conf = Join-Path $ws '.github/af-env.conf'
    if (Test-Path -LiteralPath $conf) {
        $m = Select-String -LiteralPath $conf -Pattern '^WORKTREE_VENV_MODE=(.+)$' | Select-Object -First 1
        if ($m) { $mode = $m.Matches[0].Groups[1].Value.Trim().Trim('"', "'") }
    }

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
    $message = @(
        "ERROR: venv python not found under $ws/.venv (searched: $searched; WORKTREE_VENV_MODE=$mode)"
        'BLOCKED: no usable venv for this checkout. Creating one installs packages, so a human runs it:'
        '  worktree:       .github/scripts/setup-worktree.ps1 (isolated mode creates the worktree venv)'
        '  plain checkout: .github/scripts/bootstrap-python-env.ps1'
    ) -join [Environment]::NewLine
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
        '  Set WORKTREE_VENV_MODE=isolated in .github/af-env.conf and have a human run .github/scripts/setup-worktree.ps1.'
    ) -join [Environment]::NewLine
}
