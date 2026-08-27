# check-cost-source.ps1 -- report whether the cost-tracking data source is live.
#
# The `cost:` block in a workflow log is only as good as its source: VS Code's
# agent debug log. When that is switched off the collector correctly records
# `available: false`, but that lands in a YAML file nobody opens unless they
# already suspect a problem. A consumer can therefore run for months with an
# empty cost series and never learn why (AAIG issue #228).
#
# The probe measures the EFFECT, not the configuration: it counts session logs
# on disk. Reading the setting itself is unreliable -- it may sit in user,
# workspace, or profile settings, and those files are JSONC, which no JSON
# parser accepts. A session log that exists is proof the source is live.
#
# ADVISORY ONLY. This always exits 0. The setting is experiment-flagged and
# vendor-controlled, so nothing in the framework may gate on it.

[CmdletBinding()]
param(
    # Defaults to the VS Code user directories found on this machine.
    [string[]]$UserDir = @(),
    [switch]$Brief
)

$ErrorActionPreference = 'Stop'

$SETTING = 'github.copilot.chat.agentDebugLog.fileLogging.enabled'

function Get-DefaultUserDir {
    $roots = @()
    if ($env:OS -eq 'Windows_NT') {
        if ($env:APPDATA) { $roots += $env:APPDATA }
    }
    else {
        if ($HOME) {
            $roots += (Join-Path $HOME 'Library/Application Support')
            $roots += (Join-Path $HOME '.config')
        }
    }

    $found = @()
    foreach ($root in $roots) {
        foreach ($variant in @('Code', 'Code - Insiders')) {
            $dir = Join-Path (Join-Path $root $variant) 'User'
            if (Test-Path -LiteralPath $dir) { $found += $dir }
        }
    }
    return $found
}

function Measure-SessionLog([string[]]$dirs) {
    $total = 0
    foreach ($dir in $dirs) {
        $pattern = Join-Path $dir 'workspaceStorage/*/GitHub.copilot-chat/debug-logs/*/main.jsonl'
        $total += @(Get-ChildItem -Path $pattern -Force -ErrorAction SilentlyContinue).Count
    }
    return $total
}

$dirs = if ($UserDir.Count -gt 0) { $UserDir } else { Get-DefaultUserDir }
$sessions = Measure-SessionLog $dirs

if (-not $Brief) { Write-Host '=== Cost Tracking Source ===' }

if ($sessions -gt 0) {
    Write-Host "  OK: agent debug logging is producing session logs ($sessions found)."
    exit 0
}

# Naming the searched locations keeps the advisory falsifiable: a portable or
# relocated VS Code install is a false alarm the consumer can recognise.
$where = if ($dirs.Count -gt 0) { $dirs -join '; ' } else { '(no VS Code user directory found)' }

Write-Host "  ADVISORY: no agent debug logs found -- workflow cost blocks will be empty."
Write-Host "    Searched: $where"
Write-Host "    Enable the VS Code setting: $SETTING"
Write-Host "    While it is off, every workflow log records 'cost: available: false'"
Write-Host "    and no token or credit figures can be reconciled."
Write-Host "    The setting is experiment-flagged and vendor-controlled; it may be"
Write-Host "    withdrawn. Nothing gates on it -- this notice is advisory only."

exit 0
