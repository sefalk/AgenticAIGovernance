# Copilot hook lifecycle evidence (#553). No Local output-channel fallback.
# Exit: 0 complete observed lifecycle, 1 hook failure, 2 inconclusive evidence.
param(
    [string]$Workspace = (Get-Location).Path,
    [string]$SessionId,
    [string]$SessionStateRoot = (Join-Path $HOME '.copilot\session-state')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_suite_env.ps1')
$python = Get-AfSuitePython
if (-not $python) {
    Write-Output '{"status":"inconclusive","reason":"python_unavailable"}'
    exit 2
}
$arguments = @((Join-Path $PSScriptRoot 'check-copilot-hook-events.py'),
    '--workspace', $Workspace, '--session-state-root', $SessionStateRoot)
if ($PSBoundParameters.ContainsKey('SessionId')) { $arguments += @('--session-id', $SessionId) }
& $python @arguments
exit $LASTEXITCODE
