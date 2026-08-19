# SessionStart hook: Injects git and environment context into the agent session.
# Input:  JSON via stdin (common fields + source)
# Output: JSON with additionalContext
#
# This gives every agent session automatic awareness of the current branch,
# last commit, and Python version -- no manual prompting needed.

$ErrorActionPreference = 'SilentlyContinue'

# Root and interpreter come from this script's location, never from the cwd
# the agent happens to run in (issue #54).
. "$PSScriptRoot/_common.ps1"

# Consume stdin (required even if we don't use the input)
try { [Console]::In.ReadToEnd() | Out-Null } catch {}

# Gather context
$branch  = (git rev-parse --abbrev-ref HEAD 2>$null)
if (-not $branch) { $branch = 'unknown' }

$commit  = (git log -1 --format='%h %s' 2>$null)
if (-not $commit) { $commit = 'unknown' }

$pyVer   = if ($AfPython) { & $AfPython --version 2>&1 } else { 'unknown' }
if (-not $pyVer) { $pyVer = 'unknown' }

$repoRoot = $AfCodeRoot
$project  = if ($repoRoot) { Split-Path $repoRoot -Leaf } else { 'unknown' }

# Test log summary
$testLogSummary = ''
$testLogPath = Join-Path $AfMainRoot '.github/test-log.json'
if ($testLogPath -and (Test-Path $testLogPath -ErrorAction SilentlyContinue)) {
    try {
        $log = Get-Content $testLogPath -Raw | ConvertFrom-Json
        $parts = @()
        foreach ($scope in @('domain', 'adapters', 'properties', 'contracts', 'all')) {
            if ($log.PSObject.Properties.Name -contains $scope) {
                $s = $log.$scope
                $age = ''
                try {
                    $elapsed = (Get-Date) - [DateTime]::Parse($s.last_run)
                    if ($elapsed.TotalMinutes -lt 60) {
                        $age = "$([int]$elapsed.TotalMinutes)m ago"
                    } else {
                        $age = "$([int]$elapsed.TotalHours)h ago"
                    }
                } catch { $age = '?' }
                $status = if ($s.exit_code -eq 0) { 'PASS' } else { 'FAIL' }
                $parts += "$scope=$($s.passed)/$($s.total)($status,$age)"
            }
        }
        if ($parts.Count -gt 0) {
            $testLogSummary = " | Tests: $($parts -join ', ')"
        }
    } catch {}
}

# Build context string
$context = "Project: $project | Branch: $branch | Last commit: $commit | $pyVer$testLogSummary"

# Return JSON
@{
    hookSpecificOutput = @{
        hookEventName     = 'SessionStart'
        additionalContext = $context
    }
} | ConvertTo-Json -Depth 3 -Compress
