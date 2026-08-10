# Agent-scoped Stop hook for the documenter agent.
#
# DOCUMENTATION ARTIFACT GATE (HARD -- blocks documenter FINALISATION if
# required artifacts are missing)
#
# Verifies the documenter has produced the required workflow artifacts:
#   1. YAML workflow log in .github/logs/{workflow-id}.yaml
#   2. Retro snippet in retros/auto/{workflow-id}.md or .github/retros/auto/
#
# The gate applies only to finalisation, which is recognised by the plan file
# being marked COMPLETED. A mid-workflow documenter call (plan persistence,
# Step 1 of Full TDD) terminates without these artifacts -- see Gate 0.
#
# Fires as SubagentStop when the documenter is invoked by the coordinator.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

$ErrorActionPreference = 'SilentlyContinue'

# Root, config and interpreter come from this script's location, never from
# the cwd the agent happens to run in (issue #54).
. "$PSScriptRoot/_common.ps1"

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

$BASE_BRANCH = Get-AfConfig -Key 'BASE_BRANCH' -Default 'dev'

# ---------- Gate 0: Which lifecycle is this? ----------
#
# The documenter has two chartered jobs: persist plan files mid-workflow, and
# finalise at the end. This gate used to fire on both, so a mid-workflow call
# could only terminate by inventing a COMPLETED workflow log and retro for a
# workflow still running -- the hook mechanically compelled the false artifact
# it existed to guarantee (issue #72).
#
# Intent is not on stdin, so it is read off the plan file: a plan marked
# COMPLETED is the documenter's own claim that it finalised, and that claim is
# what this gate holds it to.

$plan = Get-AfPlanLifecycle -WorkflowId $workflowId -Root $AfCodeRoot

if (-not $plan.Found) {
    # Unclassifiable is not the same as fine, and saying nothing would repeat
    # the defect this gate is meant to prevent. Completeness is still enforced
    # once, by the compliance-checker post-flight gate.
    $output = @{
        systemMessage = "documenter:Stop -- no plan file names 'agent/$workflowId', so a mid-workflow call cannot be told from finalisation; artifact gate not applied. Completeness is enforced by the compliance-checker post-flight gate."
    } | ConvertTo-Json -Compress
    Write-Output $output
    exit 0
}

if ($plan.Status -ne 'COMPLETED') {
    $seen = if ($plan.Status) { $plan.Status } else { 'unset' }
    $output = @{
        systemMessage = "documenter:Stop -- plan status is $seen, not COMPLETED: treated as a mid-workflow documenter call, artifact gate not applied."
    } | ConvertTo-Json -Compress
    Write-Output $output
    exit 0
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

# ---------- Timestamps (ADVISORY -- never blocks, never fails the hook) ----------
#
# Stamped here rather than written by the documenter so the values never pass
# through a language model. Measured: a documenter wrote a `completed:` six and
# a half hours into the future, in the same output that declared "zero
# fabricated data" -- and every gate downstream accepted it, because they check
# that the field is present, and an invented value is present (issue #91).
#
# `completed:` is now: this hook fires when the documenter finishes. `started:`
# is the branch's oldest commit, the same approximation the cost collector
# already uses for --workflow-start. Anything the documenter left behind is
# replaced rather than joined -- two `completed:` keys is a YAML file whose
# meaning depends on which one the parser reaches last.

$stampNote = ''
try {
    $logPath = if (Test-Path $logPath1) { $logPath1 } else { $logPath2 }

    $completedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $startedAt = $completedAt
    $base = if ($BASE_BRANCH) { $BASE_BRANCH } else { 'dev' }
    $isoStamps = & git log --format=%cI "$base..HEAD" 2>$null
    if ($isoStamps) { $startedAt = @($isoStamps)[-1] }

    # Top-level keys only: a `started:` indented inside a step belongs to that
    # step and is none of this hook's business.
    $kept = @(Get-Content $logPath | Where-Object { $_ -notmatch '^(started|completed):' })
    $stampLines = @("started: `"$startedAt`"", "completed: `"$completedAt`"")

    $anchor = -1
    for ($i = 0; $i -lt $kept.Count; $i++) {
        if ($kept[$i] -match '^workflow_id:') { $anchor = $i; break }
    }
    if ($anchor -ge 0) {
        $head = @($kept[0..$anchor])
        $tail = if ($anchor -lt ($kept.Count - 1)) { @($kept[($anchor + 1)..($kept.Count - 1)]) } else { @() }
        $kept = $head + $stampLines + $tail
    } else {
        $kept = $stampLines + $kept
    }

    Set-Content -Path $logPath -Value $kept -Encoding UTF8
    $stampNote = ' + timestamps measured'
}
catch {
    $stampNote = ''
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
                # The shared preamble already validated the interpreter by
                # running it -- a resolvable-but-dead stub never gets here.
                $python = $AfPython
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

# ---------- Scratch task audit (ADVISORY -- never blocks) ----------
#
# createAndRunTask writes its payload into .vscode/tasks.json, so every one-off
# invocation becomes a permanent entry. Report the leftovers at workflow end;
# the human decides whether to keep or prune them.

$scratchNote = ''
try {
    $checker = '.github/hooks/scripts/check-scratch-tasks.py'
    if ((Test-Path $checker) -and (Test-Path '.vscode/tasks.json')) {
        $scratchPy = $null
        foreach ($c in @('.venv/Scripts/python.exe', '.venv/bin/python')) {
            if (Test-Path $c) { $scratchPy = $c; break }
        }
        if (-not $scratchPy) {
            # The shared preamble already validated the interpreter by running
            # it -- a resolvable-but-dead stub never gets here.
            $scratchPy = $AfPython
        }
        if ($scratchPy) {
            $found = @(& $scratchPy $checker '.vscode/tasks.json' 2>$null)
            if ($found.Count -gt 0) {
                $scratchNote = " + scratch tasks to prune ($($found.Count)): " + ($found -join '; ')
            }
        }
    }
}
catch {
    $scratchNote = ''
}

$output = @{
    systemMessage = "documenter:Stop -- artifact gate PASS: workflow log and retro snippet exist for '$workflowId'$stampNote$costNote$scratchNote"
} | ConvertTo-Json -Compress
Write-Output $output
exit 0
