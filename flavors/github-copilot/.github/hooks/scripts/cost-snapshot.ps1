# Global Stop / SubagentStop hook: refresh the session cost store (issue #457).
#
# Thin dialect wrapper (issue #287). Locating the session log and starting the
# collector in the background live in cost-snapshot.py. Everything here is
# interpreter resolution and stdin marshalling.

$ErrorActionPreference = 'SilentlyContinue'

. "$PSScriptRoot/_common.ps1"

$raw = Read-AfStdin
$core = Join-Path $PSScriptRoot 'cost-snapshot.py'

if (-not $AfPython -or -not (Test-Path $core)) {
    # Advisory: no interpreter, no refresh; the documenter run still reads the log.
    Write-Output '{}'
    exit 0
}

$raw | & $AfPython $core
exit 0
