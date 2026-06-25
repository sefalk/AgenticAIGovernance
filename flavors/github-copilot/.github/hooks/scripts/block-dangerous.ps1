# PreToolUse hook: Requires user confirmation for dangerous terminal commands.
# Input:  JSON via stdin with tool_name and tool_input
# Output: JSON with permissionDecision="ask" if dangerous pattern detected
#
# This hook does NOT block commands outright -- it prompts for confirmation.
# Safe commands pass through without interference.

$ErrorActionPreference = 'SilentlyContinue'

# Read and parse stdin
$raw = [Console]::In.ReadToEnd()
try {
    $inputData = $raw | ConvertFrom-Json
} catch {
    Write-Output '{}'
    exit 0
}

# Only inspect terminal tool calls
$toolName = $inputData.tool_name
if ($toolName -notmatch 'terminal|Terminal') {
    Write-Output '{}'
    exit 0
}

# Extract the command string
$command = $inputData.tool_input.command
if (-not $command) {
    Write-Output '{}'
    exit 0
}

# Dangerous patterns -- each triggers a confirmation prompt
$patterns = @(
    'rm\s+-r[f ]'                   # recursive delete (Unix)
    'Remove-Item.*-Recurse'         # recursive delete (PowerShell)
    'DROP\s+(TABLE|DATABASE)'       # SQL destructive
    'TRUNCATE\s+TABLE'              # SQL destructive
    'git\s+push\b.*(--force|-f)\b'  # force push (always confirm)
    'git\s+push\b.*\b(main|master|dev)\b'  # push naming a protected branch
    'git\s+merge\b'                 # any merge (topology change)
    'git\s+branch\s+-[dD]\b'       # branch deletion
    'git\s+rebase\b'               # history rewrite
    'git\s+reset\s+--hard'          # hard reset
    'format\s+[A-Z]:'              # format drive (Windows)
    'mkfs\.'                        # format filesystem (Linux)
    'dd\s+if=.*of=/dev/'           # raw disk write
    '--no-verify'                   # bypass git hooks
    'chmod\s+-R\s+777'             # world-writable permissions
    'git\s+add\s+.*(-f|--force)'   # bypass .gitignore
    'git\s+add\s+(-\S+\s+)*\.$'   # git add . (banned wildcard)
    'git\s+add\s+.*-A'             # git add -A (banned wildcard)
)

foreach ($p in $patterns) {
    if ($command -match $p) {
        @{
            hookSpecificOutput = @{
                hookEventName            = 'PreToolUse'
                permissionDecision       = 'ask'
                permissionDecisionReason = "Safety hook: command matches pattern [$p]. Please confirm this is intentional."
            }
        } | ConvertTo-Json -Depth 3 -Compress
        exit 0
    }
}

# Safe command -- don't override user's approval settings
Write-Output '{}'
