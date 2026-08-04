# Agent-scoped Stop hook for the documenter agent.
#
# DOCUMENTATION ARTIFACT GATE (HARD -- blocks documenter if required artifacts missing)
#
# Verifies the documenter has produced the required workflow artifacts:
#   1. YAML workflow log in .github/logs/{workflow-id}.yaml
#   2. Retro snippet in retros/auto/{workflow-id}.md or .github/retros/auto/
#
# Fires as SubagentStop when the documenter is invoked by the coordinator.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

$ErrorActionPreference = 'SilentlyContinue'

# Read stdin (hook input JSON -- required by protocol).
# It carries session_id and transcript_path, which is how the cost block below
# locates the debug log; both name the PARENT session even inside a subagent
# (measured 2026-08-03), so no session has to be guessed.
$stdinRaw = [Console]::In.ReadToEnd()

# Derive workflow-id from current branch
$branch = & git branch --show-current 2>$null
if (-not $branch -or $branch -notmatch '^agent/(.+)$') {
    # Not on an agent branch -- skip artifact checks
    $output = @{
        systemMessage = "documenter:Stop -- not on agent/ branch, artifact gate skipped"
    } | ConvertTo-Json -Compress
    Write-Output $output
    exit 0
}

$workflowId = $Matches[1]
$missing = @()

$BASE_BRANCH = 'dev'
$confPath = Join-Path (Get-Location) '.github/af-env.conf'
if (Test-Path $confPath) {
    $b = Select-String -Path $confPath -Pattern '^BASE_BRANCH=(.+)$'
    if ($b) { $BASE_BRANCH = $b.Matches[0].Groups[1].Value.Trim() }
}

# ---------- Gate 1: Workflow log YAML ----------

$logPath1 = ".github/logs/$workflowId.yaml"
$logPath2 = ".github/logs/$workflowId.yml"
if (-not (Test-Path $logPath1) -and -not (Test-Path $logPath2)) {
    $missing += "workflow log (.github/logs/$workflowId.yaml)"
}

# ---------- Gate 2: Retro snippet ----------

# Canonical location is .github/retros/auto/; the bare path is accepted for
# projects that adopted it before the location was settled.
$retroPath1 = ".github/retros/auto/$workflowId.md"
$retroPath2 = "retros/auto/$workflowId.md"
if (-not (Test-Path $retroPath1) -and -not (Test-Path $retroPath2)) {
    $missing += "retro snippet (.github/retros/auto/$workflowId.md)"
}

# ---------- Verdict ----------

if ($missing.Count -gt 0) {
    $list = $missing -join '; '
    $output = @{
        hookSpecificOutput = @{
            hookEventName = "Stop"
            decision = "block"
            reason = "Documentation phase violation: required artifacts missing for workflow '$workflowId': $list. Create these files before completing."
        }
    } | ConvertTo-Json -Compress -Depth 3
    Write-Output $output
    exit 0
}

# ---------- Cost block (ADVISORY -- never blocks, never fails the hook) ----------
#
# Appended here rather than written by the documenter so the numbers never pass
# through a language model. A vendor setting being off is not a framework
# failure, so every path below degrades silently.

$costNote = ''
try {
    $logPath = if (Test-Path $logPath1) { $logPath1 } else { $logPath2 }

    # Appending twice would produce a duplicate YAML key; first write wins.
    if ((Select-String -Path $logPath -Pattern '^cost:' -Quiet) -ne $true) {
        $hookInput = $null
        if ($stdinRaw) { $hookInput = $stdinRaw | ConvertFrom-Json }
        $sid = $hookInput.session_id
        $transcript = $hookInput.transcript_path

        if ($sid -and $transcript) {
            # <ws>/GitHub.copilot-chat/transcripts/<sid>.jsonl -> .../debug-logs/<sid>
            $chatDir = Split-Path -Parent (Split-Path -Parent $transcript)
            $sessionDir = Join-Path (Join-Path $chatDir 'debug-logs') $sid

            $collector = '.github/scripts/collect-session-cost.py'
            $python = $null
            foreach ($c in @('.venv/Scripts/python.exe', '.venv/bin/python')) {
                if (Test-Path $c) { $python = $c; break }
            }
            if (-not $python) {
                # Validate, do not just resolve: on Windows `python3` is usually
                # the Store stub, which prints an ad and exits non-zero.
                foreach ($n in @('python3', 'python')) {
                    $cmd = Get-Command $n -ErrorAction SilentlyContinue
                    if (-not $cmd) { continue }
                    $v = & $cmd.Source --version 2>&1
                    if ($LASTEXITCODE -eq 0 -and "$v" -match 'Python 3') { $python = $cmd.Source; break }
                }
            }

            if ($python -and (Test-Path $collector)) {
                # Oldest commit on the branch approximates the workflow start;
                # a session that began later means earlier phases are unlogged.
                $collectorArgs = @('--session-dir', $sessionDir)
                $base = if ($BASE_BRANCH) { $BASE_BRANCH } else { 'dev' }
                $stamps = & git log --format=%ct "$base..HEAD" 2>$null
                if ($stamps) {
                    $oldest = @($stamps)[-1]
                    $collectorArgs += @('--workflow-start', ([string]([int64]$oldest * 1000)))
                }

                $block = & $python $collector @collectorArgs 2>$null
                if ($LASTEXITCODE -eq 0 -and $block) {
                    Add-Content -Path $logPath -Value ''
                    Add-Content -Path $logPath -Value $block
                    $costNote = ' + cost block appended'
                }
            }
        }
    }
}
catch {
    $costNote = ''
}

$output = @{
    systemMessage = "documenter:Stop -- artifact gate PASS: workflow log and retro snippet exist for '$workflowId'$costNote"
} | ConvertTo-Json -Compress
Write-Output $output
exit 0
