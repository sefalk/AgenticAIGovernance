# SessionStart hook: Injects git and environment context into the agent session.
# Input:  JSON via stdin (common fields + source)
# Output: JSON with additionalContext
#
# This gives every agent session automatic awareness of the current branch,
# last commit, and Python version -- no manual prompting needed.

$ErrorActionPreference = 'SilentlyContinue'

# Consume stdin (required even if we don't use the input)
try { [Console]::In.ReadToEnd() | Out-Null } catch {}

# Gather context
$branch  = (git rev-parse --abbrev-ref HEAD 2>$null)
if (-not $branch) { $branch = 'unknown' }

$commit  = (git log -1 --format='%h %s' 2>$null)
if (-not $commit) { $commit = 'unknown' }

$pyVer   = (python --version 2>&1)
if (-not $pyVer) { $pyVer = 'unknown' }

$repoRoot = (git rev-parse --show-toplevel 2>$null)
$project  = if ($repoRoot) { Split-Path $repoRoot -Leaf } else { 'unknown' }

# Build context string
$context = "Project: $project | Branch: $branch | Last commit: $commit | $pyVer"

# Return JSON
@{
    hookSpecificOutput = @{
        hookEventName     = 'SessionStart'
        additionalContext = $context
    }
} | ConvertTo-Json -Depth 3 -Compress
