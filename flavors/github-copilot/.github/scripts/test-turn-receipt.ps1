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
# not used: measured 2026-11-03, it had not been written for 23 hours while
# hooks kept firing, and it mixes every session of a window.

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
