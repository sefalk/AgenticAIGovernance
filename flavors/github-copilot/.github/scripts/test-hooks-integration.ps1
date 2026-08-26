# Hook Integration Verification -- VS Code Output Channel Analysis
#
# Parses the "GitHub Copilot Chat Hooks" output channel log to verify
# that VS Code is actually invoking hooks during agent sessions.
#
# Unlike test-hooks.ps1 (which tests script logic by piping JSON),
# this script answers: "Are hooks firing in real VS Code sessions?"
#
# Usage:
#   .github/scripts/test-hooks-integration.ps1              # Analyse current session
#   .github/scripts/test-hooks-integration.ps1 -All         # Analyse all sessions
#   .github/scripts/test-hooks-integration.ps1 -Verbose     # Show per-invocation detail
#
# Exit codes: 0 = hooks are firing, 1 = problems detected, 2 = no log found

param(
    [switch]$All,
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'

# -- Locate hook log files ------------------------------------------------

$logsRoot = "$env:APPDATA\Code\logs"
if (-not (Test-Path $logsRoot)) {
    Write-Output "ERROR: VS Code logs directory not found at $logsRoot"
    exit 2
}

# Find all hook log files, sorted newest first
$hookLogs = Get-ChildItem $logsRoot -Recurse -File -Filter 'GitHub Copilot Chat Hooks.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending

if ($hookLogs.Count -eq 0) {
    Write-Output "ERROR: No 'GitHub Copilot Chat Hooks.log' files found."
    Write-Output "       Ensure chat.useCustomAgentHooks is true in .vscode/settings.json"
    Write-Output "       and that at least one agent session has been run."
    exit 2
}

if (-not $All) {
    # Only analyse the most recent log
    $hookLogs = @($hookLogs[0])
}

Write-Output "=== Hook Integration Verification ==="
Write-Output "  Analysing $($hookLogs.Count) log file(s)"
Write-Output ""

# -- Parse and analyse ----------------------------------------------------

$script:totalInvocations = 0
$script:totalEvents = @{}       # EventName -> count
$script:hookScripts = @{}       # script path -> count
$script:toolsSeen = @{}         # tool_name -> count
$script:failures = 0
$script:denials = 0
$script:warnings = @()
$script:hookCounts = @{}        # EventName -> set of hook counts seen

foreach ($logFile in $hookLogs) {
    $sessionDir = $logFile.Directory.Parent.Parent.Parent.Name  # session timestamp
    $windowDir = $logFile.Directory.Parent.Parent.Name          # windowN
    if ($Verbose) {
        Write-Output "--- Session: $sessionDir / $windowDir ---"
    }

    $lines = Get-Content $logFile.FullName -ErrorAction SilentlyContinue
    if (-not $lines -or $lines.Count -eq 0) {
        if ($Verbose) { Write-Output "  (empty log)" }
        continue
    }

    foreach ($line in $lines) {
        # Parse: YYYY-MM-DD HH:MM:SS.mmm [level] [#NNN] [EventName] message
        if ($line -match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+ \[info\] \[#(\d+)\] \[(\w+)\] (.+)$') {
            $seqNum = $Matches[1]
            $event = $Matches[2]
            $message = $Matches[3]

            # Every pattern below is anchored to the start of the message.
            #
            # The log records each tool's response, so anything printed into a
            # terminal -- including an excerpt of this very log, or this script's
            # own output -- comes back as text inside a later PostToolUse line.
            # Unanchored patterns match that quoted text and count it as hook
            # activity. Observed: printing one raw 'Running: ... session-context.ps1'
            # line made the next run report that hook as firing, with no hook
            # having run in between. 'Completed (Failure)' is the costly case,
            # since a phantom match fails the suite and turns the CI gate red.

            # Track Executing lines (show hook count per event)
            if ($message -match '^Executing (\d+) hook\(s\)') {
                $hookCount = [int]$Matches[1]
                $script:totalInvocations++
                if (-not $script:totalEvents.ContainsKey($event)) {
                    $script:totalEvents[$event] = 0
                }
                $script:totalEvents[$event]++
                if (-not $script:hookCounts.ContainsKey($event)) {
                    $script:hookCounts[$event] = @{}
                }
                $script:hookCounts[$event]["$hookCount"] = $true
            }

            # Track which scripts are being run
            if ($message -match '^Running:.*?File\s+[^\s]+\\\\([^\\]+\.ps1)') {
                $scriptName = $Matches[1]
                if (-not $script:hookScripts.ContainsKey($scriptName)) {
                    $script:hookScripts[$scriptName] = 0
                }
                $script:hookScripts[$scriptName]++
            }
            elseif ($message -match '^Running:.*?scripts/([^/"]+\.sh)') {
                $scriptName = $Matches[1]
                if (-not $script:hookScripts.ContainsKey($scriptName)) {
                    $script:hookScripts[$scriptName] = 0
                }
                $script:hookScripts[$scriptName]++
            }

            # Track tool names from Input JSON
            if ($message -match '^Input:.*?"tool_name":"([^"]+)"') {
                $toolName = $Matches[1]
                if (-not $script:toolsSeen.ContainsKey($toolName)) {
                    $script:toolsSeen[$toolName] = 0
                }
                $script:toolsSeen[$toolName]++
            }

            # Track failures
            if ($message -match '^Completed \(Failure\)') {
                $script:failures++
                $script:warnings += "FAILURE: [$event] #$seqNum in $sessionDir"
            }

            # Track denials (hook returned output suggesting deny/ask)
            if ($message -match '^Completed.*with output') {
                $script:denials++
                if ($Verbose) {
                    Write-Output "  [#$seqNum] [$event] returned output (deny/ask/advisory)"
                }
            }
        }
    }
}

# -- Report ---------------------------------------------------------------

Write-Output "## Hook Firing Summary"
Write-Output ""

if ($script:totalInvocations -eq 0) {
    Write-Output "  NO HOOKS FIRED -- this means hooks are not being invoked by VS Code."
    Write-Output "  Check:"
    Write-Output "    1. chat.useCustomAgentHooks = true in .vscode/settings.json"
    Write-Output "    2. hooks: key present in agent .agent.md frontmatter"
    Write-Output "    3. .github/hooks/agent-hooks.json is valid JSON (if using global hooks)"
    exit 1
}

Write-Output "  Total hook invocations: $($script:totalInvocations)"
Write-Output ""

Write-Output "  Events:"
foreach ($ev in ($script:totalEvents.Keys | Sort-Object)) {
    $counts = ($script:hookCounts[$ev].Keys | Sort-Object) -join ', '
    Write-Output "    $ev : $($script:totalEvents[$ev]) times (hook count per event: $counts)"
}
Write-Output ""

Write-Output "  Scripts invoked:"
foreach ($s in ($script:hookScripts.Keys | Sort-Object)) {
    Write-Output "    $s : $($script:hookScripts[$s]) times"
}
Write-Output ""

Write-Output "  Tools intercepted:"
$topTools = $script:toolsSeen.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 15
foreach ($t in $topTools) {
    Write-Output "    $($t.Key) : $($t.Value) times"
}
Write-Output ""

# -- Checks ---------------------------------------------------------------

Write-Output "## Integration Checks"
Write-Output ""

$checksPassed = 0
$checksFailed = 0

# Check 1: Hooks are firing
if ($script:totalInvocations -gt 0) {
    Write-Output "  PASS  Hooks are firing ($($script:totalInvocations) invocations)"
    $checksPassed++
} else {
    Write-Output "  FAIL  No hook invocations detected"
    $checksFailed++
}

# Check 2: PreToolUse hooks present
if ($script:totalEvents.ContainsKey('PreToolUse')) {
    Write-Output "  PASS  PreToolUse hooks active ($($script:totalEvents['PreToolUse']) invocations)"
    $checksPassed++
} else {
    Write-Output "  FAIL  No PreToolUse hooks detected"
    $checksFailed++
}

# Check 3: PostToolUse hooks present
if ($script:totalEvents.ContainsKey('PostToolUse')) {
    Write-Output "  PASS  PostToolUse hooks active ($($script:totalEvents['PostToolUse']) invocations)"
    $checksPassed++
} else {
    Write-Output "  FAIL  No PostToolUse hooks detected"
    $checksFailed++
}

# Check 4: No failures
if ($script:failures -eq 0) {
    Write-Output "  PASS  No hook failures"
    $checksPassed++
} else {
    Write-Output "  FAIL  $($script:failures) hook failure(s) detected"
    $checksFailed++
}

# Check 5: Expected scripts present — based on coordinator (the most commonly used agent)
$expectedScripts = @(
    'coordinator-pretooluse.ps1',
    'coordinator-posttooluse.ps1'
)
foreach ($es in $expectedScripts) {
    if ($script:hookScripts.ContainsKey($es)) {
        Write-Output "  PASS  $es is being invoked ($($script:hookScripts[$es]) times)"
        $checksPassed++
    } else {
        Write-Output "  WARN  $es not seen in analysed session(s)"
        # Warn, not fail — may depend on which agent was used
    }
}

# Check 6: Verify the hooks declared in agent-hooks.json are firing.
#
# Split by scope. One combined list conflates two findings with very
# different base rates, and so reports the harmless one as if it were a fault:
#
#   Tool-scoped hooks fire on every matching tool call. Their absence from a
#   log holding hundreds of invocations is real evidence of a problem.
#
#   SessionStart fires once per session, but this log file is created per
#   window. A window reload opens a fresh log mid-session, and that log can
#   never contain the SessionStart that preceded it. Absence is the normal
#   case, not a defect.
#
# Measured across 8 logs (7,127 recorded hook events): exactly 1 SessionStart,
# and it ran session-context.ps1 to completion (Success, 3330ms, returning
# additionalContext). The event works; it is simply rarely captured.
$globalToolScripts = @(
    'block-dangerous.ps1',
    'scan-secrets.ps1',
    'stop-tests.ps1'
)
$globalSessionScripts = @(
    'session-context.ps1',
    'session-mcp-readiness.ps1'
)
$globalMissing = @($globalToolScripts | Where-Object { -not $script:hookScripts.ContainsKey($_) })
$sessionMissing = @($globalSessionScripts | Where-Object { -not $script:hookScripts.ContainsKey($_) })

if ($globalMissing.Count -eq 0) {
    Write-Output "  PASS  Tool-scoped global hooks (agent-hooks.json) are firing"
    $checksPassed++
} else {
    Write-Output "  WARN  Tool-scoped global hooks NOT firing: $($globalMissing -join ', ')"
    Write-Output "        -> Check the matcher in agent-hooks.json against the tools"
    Write-Output "           this log actually contains, and that the script path resolves."
    # Advisory — but important to track
}

if ($sessionMissing.Count -gt 0) {
    Write-Output "  INFO  No SessionStart record in this log for: $($sessionMissing -join ', ')"
    Write-Output "        Expected whenever the log began mid-session. This is not"
    Write-Output "        evidence that agent-hooks.json is unloaded -- the tool-scoped"
    Write-Output "        hooks reported above are declared in that same file."
}

# Check 7: Verify multiple tools are being intercepted
if ($script:toolsSeen.Count -ge 3) {
    Write-Output "  PASS  Multiple tool types intercepted ($($script:toolsSeen.Count) distinct tools)"
    $checksPassed++
} else {
    Write-Output "  WARN  Only $($script:toolsSeen.Count) distinct tool type(s) seen"
}

Write-Output ""

# -- Warnings -------------------------------------------------------------

if ($script:warnings.Count -gt 0) {
    Write-Output "## Warnings"
    foreach ($w in $script:warnings) {
        Write-Output "  $w"
    }
    Write-Output ""
}

# -- Orphan Detection -----------------------------------------------------

# List all hook scripts in the project and flag ones never seen in the log
$projectHooksDir = Join-Path (Get-Location) '.github/hooks/scripts'
if (Test-Path $projectHooksDir) {
    $allHookScripts = Get-ChildItem $projectHooksDir -Filter '*.ps1' |
        Where-Object { $_.Name -ne 'hook-utils.ps1' } |
        ForEach-Object { $_.Name }

    $orphaned = $allHookScripts | Where-Object { -not $script:hookScripts.ContainsKey($_) }
    if ($orphaned.Count -gt 0) {
        Write-Output "## Orphan Candidates"
        Write-Output "  Scripts in hooks/scripts/ not seen in this log:"
        foreach ($o in ($orphaned | Sort-Object)) {
            Write-Output "    $o"
        }
        Write-Output ""
        Write-Output "  These scripts were not called during the sessions this log covers."
        Write-Output "  That is not proof they are orphaned: a hook bound to an agent or"
        Write-Output "  an event that never occurred here looks identical to an unused one."
        Write-Output "  Confirm against the declarations before deleting anything -- check"
        Write-Output "  agent-hooks.json and the hooks: frontmatter of every .agent.md."
        Write-Output ""
    }
}

# -- Summary --------------------------------------------------------------

Write-Output "=== Summary ==="
Write-Output "  Checks passed: $checksPassed"
Write-Output "  Checks failed: $checksFailed"

if ($checksFailed -gt 0) {
    Write-Output "  RESULT: PROBLEMS DETECTED"
    exit 1
} else {
    Write-Output "  RESULT: HOOKS ARE WORKING"
    exit 0
}
