# Agent-scoped SubagentStop hook for the compliance-checker (issue #286).
#
# Thin dialect wrapper (issue #287). The gate -- a report quoting `path:line`
# with no read_file call behind it is blocked -- lives in
# compliance-checker-stop.py. Everything here is interpreter resolution and
# stdin marshalling.

$ErrorActionPreference = 'SilentlyContinue'

. "$PSScriptRoot/_common.ps1"

$raw = Read-AfStdin
$core = Join-Path $PSScriptRoot 'compliance-checker-stop.py'

if (-not $AfPython -or -not (Test-Path $core)) {
    # Unmeasured, said out loud: silence would read as a verified report.
    Write-Output (@{ systemMessage = 'compliance-checker:Stop -- read check not measurable (no Python interpreter or compliance-checker-stop.py missing); quotations are unverified, not verified' } | ConvertTo-Json -Compress)
    exit 0
}

$raw | & $AfPython $core
exit 0
