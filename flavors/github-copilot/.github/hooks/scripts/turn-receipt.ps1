# Global Stop hook: name this turn's NOT RUN, block, deny and error verdicts under the answer (issue #478).
#
# Thin dialect wrapper (issue #287). Reading the hook log and choosing what to
# report live in turn-receipt.py. Everything here is interpreter resolution and
# stdin marshalling.

$ErrorActionPreference = 'SilentlyContinue'

. "$PSScriptRoot/_common.ps1"

$raw = Read-AfStdin
$core = Join-Path $PSScriptRoot 'turn-receipt.py'

if (-not $AfPython -or -not (Test-Path $core)) {
    # Advisory: no interpreter, no receipt; the verdicts stay in their subagent blocks.
    Write-Output '{}'
    exit 0
}

$raw | & $AfPython $core
exit 0
