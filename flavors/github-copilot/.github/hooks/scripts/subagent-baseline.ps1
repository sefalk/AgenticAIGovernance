# Global SubagentStart hook: snapshot the working tree a producer starts from (issue #101).
#
# Thin dialect wrapper (issue #287). Which agents are recorded, what is
# snapshotted and where it is stored live in subagent-baseline.py / _baseline.py.
# Everything here is interpreter resolution and stdin marshalling.

$ErrorActionPreference = 'SilentlyContinue'

. "$PSScriptRoot/_common.ps1"

$raw = Read-AfStdin
$core = Join-Path $PSScriptRoot 'subagent-baseline.py'

if (-not $AfPython -or -not (Test-Path $core)) {
    # Advisory: no record means the stop gate subtracts nothing.
    Write-Output '{}'
    exit 0
}

$raw | & $AfPython $core --root $AfMainRoot --code-root $AfCodeRoot
exit 0
