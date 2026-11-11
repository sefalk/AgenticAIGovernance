# Regression suite: the turn receipt lifts this turn's gate findings to the top level (#478).
#
# Probed 2026-11-02: every hook systemMessage renders, but a subagent's Stop
# verdict sits two collapsed levels deep (coordinator thinking > subagent
# block). That is how "implementer:Stop -- Green gate NOT RUN" stayed unseen
# for a week (#473). A global Stop hook renders under the answer, so it repeats
# the actionable verdicts of this turn there -- and says nothing on a clean
# turn, so its warning badge keeps its meaning.
#
# Source: the hook spans of the session's own debug logs (main.jsonl and each
# subagent log), which carry command, input and output. VS Code's Hooks.log is
# not used: it is per window, mixes every session, and has to be located by
# launch folder -- the newest one can be empty (#492).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$hookDir = Join-Path (Split-Path -Parent $scriptDir) 'hooks/scripts'
$wrapper = Join-Path $hookDir 'turn-receipt.ps1'
$wrapperSh = Join-Path $hookDir 'turn-receipt.sh'
. (Join-Path $scriptDir '_suite_env.ps1')
$python = Get-AfSuitePython $scriptDir
if (-not $python) { Write-Output 'SKIP: no Python 3 interpreter found; cannot run turn-receipt tests.'; exit 0 }

$results = [ordered]@{}
$details = [ordered]@{}
function Add-Result([string]$Name, [bool]$Ok, [string]$Detail) {
    $script:results[$Name] = $Ok
    $script:details[$Name] = $Detail
}

$fixtureDir = Join-Path ([IO.Path]::GetTempPath()) ("af478-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $fixtureDir -Force | Out-Null
$SID = 'a4780000-0000-4000-8000-000000000478'
$NOW = [DateTimeOffset]::new(2026, 11, 3, 10, 0, 0, [TimeSpan]::Zero)
$NOWMS = $NOW.ToUnixTimeMilliseconds()

function Span([string]$Event, [string]$Script, [int]$Offset, [string]$Output, [string]$InputText = '{}') {
    [ordered]@{
        ts = $NOWMS + 1000 * $Offset; dur = 90; sid = $SID; type = 'hook'; name = $Event; spanId = "h$Offset"; status = 'ok'
        attrs = [ordered]@{ command = "powershell -ExecutionPolicy Bypass -File .github\hooks\scripts\$Script"; input = $InputText; output = $Output; resultKind = 'success' }
    } | ConvertTo-Json -Compress -Depth 5
}
function New-Session([string]$Name, [hashtable]$Logs) {
    $dir = Join-Path $fixtureDir $Name
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    foreach ($file in $Logs.Keys) { [IO.File]::WriteAllLines((Join-Path $dir $file), [string[]]$Logs[$file]) }
    return $dir
}
$deny = '{"hookSpecificOutput":{"permissionDecision":"deny","hookEventName":"PreToolUse"}}'
$ask = '{"hookSpecificOutput":{"permissionDecision":"ask","hookEventName":"PreToolUse"}}'
$notRun = '{"systemMessage":"implementer:Stop -- Green gate NOT RUN (no pytest in the code root .venv or on PATH)"}'
$block = '{"decision":"block","reason":"tests failing"}'

$turnDir = New-Session 'turn' @{
    'main.jsonl' = @(
        # The previous turn: its deny and its Stop are before this turn began.
        (Span 'PreToolUse' 'block-dangerous.ps1' -90 $deny),
        (Span 'Stop' 'stop-tests.ps1' -60 '{"gate":"workflow-artifacts","status":"PENDING"}'),
        # This turn.
        (Span 'PreToolUse' 'block-dangerous.ps1' -40 $deny),
        (Span 'PreToolUse' 'block-dangerous.ps1' -35 $deny),
        (Span 'PreToolUse' 'block-dangerous.ps1' -34 $ask),
        # A command that merely mentions NOT RUN is input, not a verdict.
        (Span 'PostToolUse' 'scan-secrets.ps1' -33 '{}' '{"tool_input":"echo Green gate NOT RUN"}'),
        # The current Stop's own sibling hook already renders at the top level.
        (Span 'Stop' 'stop-tests.ps1' 0 $block)
    )
    # Subagent verdicts live in the subagent's own log.
    'runSubagent-implementer-toolu_A1.jsonl' = @((Span 'SubagentStop' 'implementer-stop.ps1' -30 $notRun))
    'runSubagent-refactorer-toolu_B2.jsonl' = @((Span 'SubagentStop' 'refactorer-stop.ps1' -20 '{"systemMessage":"refactorer:Stop -- all gates PASS"}'))
}
$cleanDir = New-Session 'clean' @{
    'main.jsonl' = @(
        (Span 'Stop' 'stop-tests.ps1' -60 '{"status":"PASS"}'),
        (Span 'PreToolUse' 'block-dangerous.ps1' -40 '{}')
    )
    'runSubagent-implementer-toolu_C3.jsonl' = @((Span 'SubagentStop' 'implementer-stop.ps1' -30 '{"systemMessage":"implementer:Stop -- Green gate PASS"}'))
}
$firstDir = New-Session 'first' @{
    'main.jsonl' = @((Span 'PreToolUse' 'block-dangerous.ps1' -40 '{}'))
    'runSubagent-implementer-toolu_D4.jsonl' = @((Span 'SubagentStop' 'implementer-stop.ps1' -30 $notRun))
}

# A guard hook that ends in error let its tool call through unchecked (#515).
function ErrSpan([string]$Event, [string]$Script, [int]$Offset) {
    [ordered]@{
        ts = $NOWMS + 1000 * $Offset; dur = 36000; sid = $SID; type = 'hook'; name = $Event; spanId = "e$Offset"; status = 'error'
        attrs = [ordered]@{ command = "powershell -ExecutionPolicy Bypass -File .github\hooks\scripts\$Script"; input = '{}'; output = ''; resultKind = 'non_blocking_error' }
    } | ConvertTo-Json -Compress -Depth 5
}
$failLog = @((ErrSpan 'PreToolUse' 'block-dangerous.ps1' -40), (ErrSpan 'PreToolUse' 'block-dangerous.ps1' -39),
    (ErrSpan 'PostToolUse' 'scan-secrets.ps1' -38), (ErrSpan 'SubagentStop' 'cost-snapshot.ps1' -30))
$failDir = New-Session 'failopen' @{
    'main.jsonl' = @((Span 'Stop' 'stop-tests.ps1' -60 '{"status":"PASS"}'))
    'runSubagent-ado-work-item-manager-toolu_E5.jsonl' = $failLog
}

$payload = "{`"session_id`":`"$SID`",`"timestamp`":`"$($NOW.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ss.fffZ'))`",`"hook_event_name`":`"Stop`",`"transcript_path`":`"c:\\\\nowhere\\\\transcripts\\\\$SID.jsonl`"}"

function Invoke-Receipt([string]$Dir, [string]$Shell = 'ps') {
    $env:AF_SESSION_DIR = $Dir
    try {
        $ErrorActionPreference = 'Continue'
        if ($Shell -eq 'sh') {
            $out = $payload | & $script:bash $wrapperSh 2>&1 | Out-String
        } else {
            $out = $payload | powershell -NoProfile -ExecutionPolicy Bypass -File $wrapper 2>&1 | Out-String
        }
        return [pscustomobject]@{ Exit = $LASTEXITCODE; Out = $out.Trim() }
    } finally {
        Remove-Item Env:AF_SESSION_DIR -ErrorAction SilentlyContinue
    }
}
function Get-Message([string]$Out) {
    try { $j = $Out | ConvertFrom-Json } catch { return $null }
    if ($j -and $j.PSObject.Properties['systemMessage']) { return [string]$j.systemMessage }
    return ''
}

try {
    $r = Invoke-Receipt $turnDir
    $msg = Get-Message $r.Out
    Add-Result 'R1_findings_of_this_turn_reach_the_top_level' `
        ($r.Exit -eq 0 -and $msg -match 'implementer-stop NOT RUN' -and $msg -match 'block-dangerous deny x2') "exit=$($r.Exit) out=$($r.Out)"
    Add-Result 'R2_only_actionable_verdicts_are_named' `
        ($null -ne $msg -and $msg -notmatch 'ask' -and $msg -notmatch 'refactorer' -and $msg -notmatch 'scan-secrets') "msg=$msg"
    Add-Result 'R3_earlier_turns_are_excluded' ($null -ne $msg -and $msg -notmatch 'x3') "msg=$msg"
    Add-Result 'R4_the_current_stops_own_hooks_are_not_repeated' ($null -ne $msg -and $msg -notmatch 'stop-tests') "msg=$msg"

    $r = Invoke-Receipt $cleanDir
    Add-Result 'C1_a_clean_turn_is_silent' ($r.Exit -eq 0 -and (Get-Message $r.Out) -eq '') "out=$($r.Out)"

    $r = Invoke-Receipt (Join-Path $fixtureDir 'absent')
    Add-Result 'C2_no_session_is_silent_not_an_error' ($r.Exit -eq 0 -and (Get-Message $r.Out) -eq '') "out=$($r.Out)"

    # First turn of a session: no earlier Stop, so the whole session so far counts.
    $r = Invoke-Receipt $firstDir
    Add-Result 'C3_the_first_turn_counts_from_the_session_start' ((Get-Message $r.Out) -match 'implementer-stop NOT RUN') "out=$($r.Out)"

    $r = Invoke-Receipt $failDir
    $msg = Get-Message $r.Out
    Add-Result 'F1_a_guard_error_is_named_fail_open' `
        ($msg -match 'block-dangerous FAIL-OPEN x2' -and $msg -match 'scan-secrets FAIL-OPEN') "msg=$msg"
    Add-Result 'F2_a_non_guard_error_keeps_its_plain_label' `
        ($msg -match 'cost-snapshot error' -and $msg -notmatch 'cost-snapshot FAIL-OPEN') "msg=$msg"

    # When the subagent returns, the coordinator's PostToolUse on runSubagent
    # tells the coordinator itself, before it acts on the result (#515).
    $scan = Join-Path $hookDir 'scan-secrets.ps1'
    $bSid = 'b5150000-0000-4000-8000-000000000515'
    $bChat = Join-Path $fixtureDir 'ws'
    $bLogs = Join-Path $bChat "debug-logs/$bSid"
    New-Item -ItemType Directory -Path $bLogs -Force | Out-Null
    [IO.File]::WriteAllLines((Join-Path $bLogs 'runSubagent-ado-work-item-manager-toolu_E5.jsonl'), [string[]]$failLog)
    [IO.File]::WriteAllLines((Join-Path $bLogs 'runSubagent-planner-toolu_F6.jsonl'), [string[]]@((Span 'PreToolUse' 'block-dangerous.ps1' -10 '{}')))
    function Invoke-SubagentReturn([string]$Agent, [string]$Call) {
        $p = [ordered]@{ hook_event_name = 'PostToolUse'; session_id = $bSid; tool_name = 'runSubagent'
            transcript_path = (Join-Path $bChat "transcripts/$bSid.jsonl"); tool_use_id = "${Call}__vscode-1794005468205"
            tool_input = @{ agentName = $Agent; description = 'x'; prompt = 'x' }; tool_response = 'done' } | ConvertTo-Json -Compress
        $ErrorActionPreference = 'Continue'
        return ($p | powershell -NoProfile -ExecutionPolicy Bypass -File $scan 2>&1 | Out-String).Trim()
    }
    $out = Invoke-SubagentReturn 'ado-work-item-manager' 'toolu_E5'
    Add-Result 'B1_the_coordinator_learns_of_fail_open_guards_when_the_subagent_returns' `
        ($out -match 'additionalContext' -and $out -match 'FAIL-OPEN' -and $out -match 'ado-work-item-manager' -and $out -match 'block-dangerous x2') "out=$out"
    $out = Invoke-SubagentReturn 'planner' 'toolu_F6'
    Add-Result 'B2_a_clean_subagent_adds_no_context' ($out -notmatch 'FAIL-OPEN') "out=$out"

    # #519: the measured context fill rides on the same subagent-return context.
    # Fill = the coordinator's latest panel/* request's inputTokens / that model's max_prompt_tokens.
    $models = '[{"id":"m1","capabilities":{"limits":{"max_prompt_tokens":1000}}}]'
    function Req([int]$Offset, [int]$Tokens, [string]$Debug = 'panel/editAgent') {
        [ordered]@{ ts = $NOWMS + 1000 * $Offset; type = 'llm_request'; name = 'chat:m1'; status = 'ok'
            attrs = [ordered]@{ model = 'm1'; inputTokens = $Tokens; cachedTokens = 0; outputTokens = 10; debugName = $Debug } } | ConvertTo-Json -Compress -Depth 5
    }
    function Invoke-Fill([string[]]$Main, [switch]$NoModels) {
        $dir = Join-Path $bChat "debug-logs/$bSid"
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        [IO.File]::WriteAllLines((Join-Path $dir 'runSubagent-planner-toolu_F6.jsonl'), [string[]]@((Span 'PreToolUse' 'block-dangerous.ps1' -10 '{}')))
        if ($Main) { [IO.File]::WriteAllLines((Join-Path $dir 'main.jsonl'), $Main) }
        if (-not $NoModels) { [IO.File]::WriteAllText((Join-Path $dir 'models.json'), $models) }
        return Invoke-SubagentReturn 'planner' 'toolu_F6'
    }
    $out = Invoke-Fill @((Req -30 100), (Req -20 300))
    Add-Result 'M1_green_fill_is_reported_as_measured' ($out -match 'GREEN' -and $out -match 'fill 30 %' -and $out -match 'measured') "out=$out"
    $out = Invoke-Fill @((Req -20 300), (Req -10 600), (Req -5 900 'summarizeConversationHistory'))
    Add-Result 'M2_yellow_at_50_percent_ignores_non_agent_requests' ($out -match 'YELLOW' -and $out -match 'fill 60 %') "out=$out"
    $out = Invoke-Fill @((Req -20 600), (Req -10 800))
    Add-Result 'M3_red_at_75_percent' ($out -match 'RED' -and $out -match 'fill 80 %') "out=$out"
    $out = Invoke-Fill @((Req -20 800), (Req -10 120))
    Add-Result 'M4_a_compaction_is_named' ($out -match 'GREEN' -and $out -match '(?i)compact' -and $out -match '800' -and $out -match '120') "out=$out"
    $out = Invoke-Fill @((Req -20 800)) -NoModels
    Add-Result 'M5_without_models_json_no_measured_line' ($out -notmatch 'fill \d+ %') "out=$out"
    $out = Invoke-Fill @()
    Add-Result 'M6_without_a_session_log_no_measured_line' ($out -notmatch 'fill \d+ %') "out=$out"
    Add-Result 'M7_no_local_path_reaches_the_context' ($out -notmatch [regex]::Escape($bChat)) "out=$out"

    $hooksJson = Get-Content -Raw (Join-Path (Split-Path -Parent $scriptDir) 'hooks/agent-hooks.json') | ConvertFrom-Json
    $declared = @($hooksJson.hooks.Stop | Where-Object { [string]$_.windows -match 'turn-receipt\.ps1' -and [string]$_.command -match 'turn-receipt\.sh' })
    Add-Result 'D1_registered_as_a_global_stop_hook_in_both_dialects' ($declared.Count -eq 1) "declared=$($declared.Count)"

    $script:bash = $null
    foreach ($candidate in @('C:\Program Files\Git\bin\bash.exe', 'bash')) {
        if (Get-Command $candidate -ErrorAction SilentlyContinue) { $script:bash = $candidate; break }
    }
    if ($script:bash) {
        $rs = Invoke-Receipt $turnDir 'sh'
        $rp = Invoke-Receipt $turnDir
        Add-Result 'P1_both_dialects_print_the_same_line' ($rs.Exit -eq 0 -and $rs.Out -eq $rp.Out -and $rp.Out -match 'systemMessage') "sh=$($rs.Out) ps=$($rp.Out)"
    }
} finally {
    Remove-Item $fixtureDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output '===== turn receipt tests (issue #478) ====='
$failed = 0
foreach ($k in $results.Keys) {
    if ($results[$k]) {
        Write-Output "PASS  $k"
    } else {
        $failed++
        Write-Output "FAIL  $k"
        Write-Output "      $($details[$k])"
    }
}
Write-Output "----- $($results.Count - $failed)/$($results.Count) passed -----"
if ($failed -gt 0) { exit 1 }
exit 0
