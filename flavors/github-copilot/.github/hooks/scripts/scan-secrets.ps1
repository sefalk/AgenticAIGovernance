# PostToolUse hook: scan edited files for hardcoded secrets.
#
# Thin dialect wrapper (issue #287). The gate itself lives in scan-secrets.py,
# so the two shells have nothing left to disagree about. Everything here is
# interpreter resolution and stdin marshalling.

$ErrorActionPreference = 'SilentlyContinue'

# A call with nothing to scan, record or announce skips Python (#515).
# Without the helper the full path runs: a missing file must not silence the scan.
$raw = $null
if (Test-Path "$PSScriptRoot/_fastpath.ps1") {
    . "$PSScriptRoot/_fastpath.ps1"
    $raw = Read-AfStdinRaw
    if (Test-AfScanSkippable $raw) { Write-Output '{}'; exit 0 }
}

. "$PSScriptRoot/_common.ps1"
if ($null -eq $raw) { $raw = Read-AfStdin }

$core = Join-Path $PSScriptRoot 'scan-secrets.py'

if (-not $AfPython -or -not (Test-Path $core)) {
    # Loud rather than silent. A scanner that quietly stops scanning is the
    # exact failure this gate exists to prevent, and the Bash twin used to
    # disappear this way whenever Python was missing.
    Write-Output (@{
        gate   = 'secret-scan'
        status = 'WARN'
        detail = 'Secret scanning did not run: no working Python interpreter was found (tried AF_PYTHON_OVERRIDE, python3, python, py), or scan-secrets.py is missing. Install Python 3 or set AF_PYTHON_OVERRIDE.'
    } | ConvertTo-Json -Compress)
    exit 0
}

$raw | & $AfPython $core
exit $LASTEXITCODE
