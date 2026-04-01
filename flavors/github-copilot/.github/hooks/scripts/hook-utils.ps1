# Shared utility functions for Copilot agent hooks.
# copilot:generated | implementer | 2026-04-01
#
# Dot-source this file at the top of each hook script:
#   . "$PSScriptRoot/hook-utils.ps1"
#
# Provides:
#   Write-HookTrace  -- append a JSONL line to .github/logs/hook-trace.jsonl
#
# Trace output goes to a FILE, never stdout, so it cannot interfere
# with the JSON output VS Code expects from hooks.

function Write-HookTrace {
    param(
        [Parameter(Mandatory)][string]$Hook,
        [string]$Event = 'invoked',
        [string]$Tool  = '',
        [string]$Detail = ''
    )
    try {
        $traceDir  = Join-Path (Get-Location) '.github/logs'
        $tracePath = Join-Path $traceDir 'hook-trace.jsonl'
        if (-not (Test-Path $traceDir)) {
            New-Item -ItemType Directory -Path $traceDir -Force | Out-Null
        }
        $entry = [ordered]@{
            ts    = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
            hook  = $Hook
            event = $Event
        }
        if ($Tool)   { $entry.tool   = $Tool }
        if ($Detail) { $entry.detail = $Detail }
        $line = $entry | ConvertTo-Json -Compress
        Add-Content -Path $tracePath -Value $line -ErrorAction SilentlyContinue
    } catch {
        # Never let trace logging break the hook
    }
}
