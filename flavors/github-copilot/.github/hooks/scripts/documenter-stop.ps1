# Agent-scoped Stop hook for the documenter agent.
#
# DOCUMENTATION ARTIFACT GATE (HARD -- blocks documenter FINALISATION if
# required artifacts are missing)
#
# Verifies the documenter has produced the required workflow artifacts:
#   1. YAML workflow log in .github/logs/{workflow-id}.yaml
#   2. Retro snippet in $RETRO_DIR/{workflow-id}.md (default
#      .github/retros/auto/) -- but only when
#      the workflow log shows there was something to learn (issue #27)
#
# The gate applies only to finalisation, which is recognised by the plan file
# being marked COMPLETED. Any documenter call made before the workflow ends
# terminates without these artifacts -- see Gate 0.
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
# The documenter can be called before the workflow ends as well as to finalise
# it. This gate used to fire on both, so a mid-workflow call
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
    #
    # Review Only and Plan Only never write a plan file, so this branch is the
    # only place their log-only documenter call is observable at all. The
    # notice below is advisory on purpose: a mid-workflow documenter call has
    # no log yet and must not be blocked for it (issue #210).
    $coverage = Get-AfConfig -Key 'AF_WORKFLOW_LOG_COVERAGE' -Default 'all'
    $coverageNote = ''
    if ($coverage -eq 'all' -and
        -not (Test-Path ".github/logs/$workflowId.yaml") -and
        -not (Test-Path ".github/logs/$workflowId.yml")) {
        $coverageNote = " NOTE: AF_WORKFLOW_LOG_COVERAGE=all and .github/logs/$workflowId.yaml does not exist -- if this call is finalising the workflow, write the log now; a run without one is indistinguishable from a cheap run."
    }
    $output = @{
        systemMessage = "documenter:Stop -- no plan file names 'agent/$workflowId', so a mid-workflow call cannot be told from finalisation; artifact gate not applied. Completeness is enforced by the compliance-checker post-flight gate.$coverageNote"
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
#
# One destination. The bare root path used to be accepted too, which did not
# resolve the ambiguity but preserved it: a documenter writing to the wrong
# place was indistinguishable from one writing to the right place, and a
# consumer accumulated 48 retros at the root, 35 of them tracked, with no rule
# telling the two groups apart (issue #98). A legacy file is named rather than
# silently ignored -- rejecting it without saying what to move would be as
# unhelpful as accepting it.
#
# Whether a retro is owed at all is decided from the log, not from the
# documenter's account of its own run (issue #27). WHERE it is owed comes from
# `RETRO_DIR`, because the default destination is gitignored and a project that
# wants retros as reviewable history must be able to say so (issue #117).

$retroDir = Get-AfRetroDir
$retroPath = "$retroDir/$workflowId.md"
$legacyRetroPath = "retros/auto/$workflowId.md"
$retro = Get-AfRetroRequirement -WorkflowId $workflowId
$retroNote = ''

if (-not (Test-Path $retroPath)) {
    if ($retro.Required) {
        if ($legacyRetroPath -ne $retroPath -and (Test-Path $legacyRetroPath)) {
            $missing += "retro snippet at its configured path -- found '$legacyRetroPath', which is no longer accepted; move it to $retroPath"
        } else {
            $missing += "retro snippet ($retroPath), required because $($retro.Reason)"
        }
    } else {
        $retroNote = " -- no retro required ($($retro.Reason))"
    }
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

# ---------- Gate 3: Workflow log schema (issue #137) ----------
#
# The log has had a schema in documenter.agent.md all along and nothing ever
# read a log against it, so the schema recorded an intention while the corpus
# recorded a habit: measured over 55 logs, 16 use a `status` or a `verdict`
# outside the vocabulary they were given and two are not valid YAML at all.
# A log nothing can parse is not a record.
#
# Vocabulary blocks, because it is a choice the documenter can correct.
# `summary.retries` and `summary.escalations` are NOT checked here -- they are
# derived from the steps and rewritten, on the same principle that stamps the
# timestamps below. Asking a model for a number it can get wrong and then
# validating the number is strictly worse than not asking (issue #91).

$schemaNote = ''
try {
    $logPath = if (Test-Path $logPath1) { $logPath1 } else { $logPath2 }
    $schemaChecker = '.github/hooks/scripts/check-workflow-log.py'
    if (Test-Path $schemaChecker) {
        $schemaPy = $null
        foreach ($c in @('.venv/Scripts/python.exe', '.venv/bin/python')) {
            if (Test-Path $c) { $schemaPy = $c; break }
        }
        if (-not $schemaPy) { $schemaPy = $AfPython }

        if ($schemaPy) {
            $schemaOut = @(& $schemaPy $schemaChecker '--log' $logPath '--fix-counters' 2>&1)
            $schemaCode = $LASTEXITCODE
            if (@($schemaOut | Where-Object { $_ -match 'derived ' }).Count -gt 0) {
                $schemaNote = ' + counters derived from steps'
            }
            if ($schemaCode -eq 1) {
                $detail = (@($schemaOut | Where-Object { $_ -notmatch 'derived ' }) -join ' ').Trim()
                $output = @{
                    hookSpecificOutput = @{
                        hookEventName = "Stop"
                        decision = "block"
                        reason = "Workflow log schema violation for '$workflowId': $detail. Fix the log, then finish. Use the vocabulary in your Workflow Log Schema: status is COMPLETED, FAILED or ESCALATED; a step verdict is APPROVED, REJECTED, ESCALATE, RESOLVED, COMPROMISE or null. Do not invent a value to describe a state the schema has no word for -- say it in `action:` instead."
                    }
                } | ConvertTo-Json -Compress -Depth 3
                Write-Output $output
                exit 0
            }
        }
    }
}
catch {
    $schemaNote = ''
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

# ---------- Agent invocations (ADVISORY -- never blocks) ----------
#
# Which subagents actually ran, read from the editor's own subagent log
# filenames so the record never passes through a language model. Measured: a
# Deep-tier workflow log carried a complete `agent: arbiter` step -- action,
# verdict, review findings -- for an arbiter that was never invoked, and only
# the coordinator's cross-check caught it (issue #173).
#
# Advisory rather than blocking, on purpose. The count covers one chat session,
# so a workflow resumed in a later window would fail a gate it did not deserve,
# and a hook that fails honest work is a hook that gets switched off (#108).
# The contradiction is written into the log instead, where any reader meets it.

$invocationNote = ''
try {
    $logPath = if (Test-Path $logPath1) { $logPath1 } else { $logPath2 }

    # Appending twice would produce a duplicate YAML key; first write wins.
    if ((Select-String -Path $logPath -Pattern '^agent_invocations:' -Quiet) -ne $true) {
        $hookInput = $null
        if ($stdinRaw) { $hookInput = $stdinRaw | ConvertFrom-Json }
        $sid = $hookInput.session_id
        $transcript = $hookInput.transcript_path

        if ($sid -and $transcript) {
            $chatDir = Split-Path -Parent (Split-Path -Parent $transcript)
            $sessionDir = Join-Path (Join-Path $chatDir 'debug-logs') $sid

            $recorder = '.github/hooks/scripts/collect-agent-invocations.py'
            $invPython = $null
            foreach ($c in @('.venv/Scripts/python.exe', '.venv/bin/python')) {
                if (Test-Path $c) { $invPython = $c; break }
            }
            if (-not $invPython) { $invPython = $AfPython }

            if ($invPython -and (Test-Path $recorder)) {
                $block = & $invPython $recorder '--session-dir' $sessionDir '--log' $logPath 2>$null
                if ($LASTEXITCODE -eq 0 -and $block) {
                    Add-Content -Path $logPath -Value ''
                    Add-Content -Path $logPath -Value $block
                    $invocationNote = ' + agent invocations measured'
                    if (@($block | Where-Object { $_ -match 'claimed_without_invocation' }).Count -gt 0) {
                        $invocationNote += ' (steps name agents with no invocation log -- check them)'
                    }
                }
            }
        }
    }
}
catch {
    $invocationNote = ''
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
    systemMessage = "documenter:Stop -- artifact gate PASS for '$workflowId'$retroNote$schemaNote$stampNote$costNote$invocationNote$scratchNote"
} | ConvertTo-Json -Compress
Write-Output $output
exit 0
