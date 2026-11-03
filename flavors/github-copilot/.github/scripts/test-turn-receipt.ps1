# Regression suite: the turn receipt lifts this turn's gate findings to the top level (#478).
#
# Probed 2026-11-02: every hook systemMessage renders, but a subagent's Stop
# verdict sits two collapsed levels deep (coordinator thinking > subagent
# block). That is how "implementer:Stop -- Green gate NOT RUN" stayed unseen
# for a week (#473). A global Stop hook renders under the answer, so it repeats
# the actionable verdicts of this turn there -- and says nothing on a clean
# turn, so its warning badge keeps its meaning.

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
$OTHER = 'b4780000-0000-4000-8000-000000000478'
$NOW = [DateTimeOffset]::new(2026, 11, 3, 10, 0, 0, [TimeSpan]::Zero)
function Iso([int]$OffsetSeconds) { $NOW.AddSeconds($OffsetSeconds).UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') }

$script:seq = 0
function Hook([string]$Event, [string]$Script, [string]$Sid, [int]$Offset, [string]$Output) {
    $script:seq++
    $p = "2026-11-03 11:00:00.000 [info] [#$($script:seq)] [$Event]"
    $lines = @(
        "$p Running: {`"command`":`"powershell -File .github\\hooks\\scripts\\$Script`"}",
        "$p Input: {`"timestamp`":`"$(Iso $Offset)`",`"hook_event_name`":`"$Event`",`"session_id`":`"$Sid`"}"
    )
    if ($Output) { $lines += "$p Completed (Success) in 90ms"; $lines += "$p Output: $Output" }
    else { $lines += "$p Completed (Success) in 90ms, no output" }
    return $lines
}
$deny = '{"hookSpecificOutput":{"permissionDecision":"deny","hookEventName":"PreToolUse"}}'
$ask = '{"hookSpecificOutput":{"permissionDecision":"ask","hookEventName":"PreToolUse"}}'
$notRun = '{"systemMessage":"implementer:Stop -- Green gate NOT RUN (no pytest in the code root .venv or on PATH)"}'
$block = '{"decision":"block","reason":"tests failing"}'

$turn = @()
# The previous turn: its deny and its Stop are before this turn began.
$turn += Hook 'PreToolUse' 'block-dangerous.ps1' $SID -90 $deny
$turn += Hook 'Stop' 'stop-tests.ps1' $SID -60 '{"gate":"workflow-artifacts","status":"PENDING"}'
# This turn.
$turn += Hook 'PreToolUse' 'block-dangerous.ps1' $SID -40 $deny
$turn += Hook 'PreToolUse' 'block-dangerous.ps1' $SID -35 $deny
$turn += Hook 'PreToolUse' 'block-dangerous.ps1' $SID -34 $ask
$turn += Hook 'SubagentStop' 'implementer-stop.ps1' $SID -30 $notRun
$turn += Hook 'SubagentStop' 'refactorer-stop.ps1' $SID -20 '{"systemMessage":"refactorer:Stop -- all gates PASS"}'
# Another session in the same window.
$turn += Hook 'SubagentStop' 'test-writer-stop.ps1' $OTHER -25 '{"systemMessage":"test-writer:Stop -- Red gate NOT RUN"}'
# The current Stop's own sibling hook already renders at the top level.
$turn += Hook 'Stop' 'stop-tests.ps1' $SID 0 $block
$log = Join-Path $fixtureDir 'hooks.log'
[IO.File]::WriteAllLines($log, $turn)

$clean = @()
$clean += Hook 'Stop' 'stop-tests.ps1' $SID -60 '{"status":"PASS"}'
$clean += Hook 'PreToolUse' 'block-dangerous.ps1' $SID -40 ''
$clean += Hook 'SubagentStop' 'implementer-stop.ps1' $SID -30 '{"systemMessage":"implementer:Stop -- Green gate PASS"}'
$cleanLog = Join-Path $fixtureDir 'clean.log'
[IO.File]::WriteAllLines($cleanLog, $clean)

$payload = "{`"session_id`":`"$SID`",`"timestamp`":`"$(Iso 0)`",`"hook_event_name`":`"Stop`",`"transcript_path`":`"c:\\\\nowhere\\\\transcripts\\\\$SID.jsonl`"}"

function Invoke-Receipt([string]$Log, [string]$Shell = 'ps') {
    $env:AF_HOOKS_LOG = $Log
    try {
        $ErrorActionPreference = 'Continue'
        if ($Shell -eq 'sh') {
            $out = $payload | & $script:bash $wrapperSh 2>&1 | Out-String
        } else {
            $out = $payload | powershell -NoProfile -ExecutionPolicy Bypass -File $wrapper 2>&1 | Out-String
        }
        return [pscustomobject]@{ Exit = $LASTEXITCODE; Out = $out.Trim() }
    } finally {
        Remove-Item Env:AF_HOOKS_LOG -ErrorAction SilentlyContinue
    }
}
function Get-Message([string]$Out) {
    try { $j = $Out | ConvertFrom-Json } catch { return $null }
    if ($j -and $j.PSObject.Properties['systemMessage']) { return [string]$j.systemMessage }
    return ''
}

try {
    $r = Invoke-Receipt $log
    $msg = Get-Message $r.Out
    Add-Result 'R1_findings_of_this_turn_reach_the_top_level' `
        ($r.Exit -eq 0 -and $msg -match 'implementer-stop NOT RUN' -and $msg -match 'block-dangerous deny x2') "exit=$($r.Exit) out=$($r.Out)"
    Add-Result 'R2_only_actionable_verdicts_are_named' `
        ($null -ne $msg -and $msg -notmatch 'ask' -and $msg -notmatch 'refactorer' -and $msg -notmatch 'PASS') "msg=$msg"
    Add-Result 'R3_other_sessions_and_earlier_turns_are_excluded' `
        ($null -ne $msg -and $msg -notmatch 'test-writer' -and $msg -notmatch 'x3') "msg=$msg"
    Add-Result 'R4_the_current_stops_own_hooks_are_not_repeated' ($null -ne $msg -and $msg -notmatch 'stop-tests') "msg=$msg"

    $r = Invoke-Receipt $cleanLog
    Add-Result 'C1_a_clean_turn_is_silent' ($r.Exit -eq 0 -and (Get-Message $r.Out) -eq '') "out=$($r.Out)"

    $r = Invoke-Receipt (Join-Path $fixtureDir 'absent.log')
    Add-Result 'C2_no_log_is_silent_not_an_error' ($r.Exit -eq 0 -and (Get-Message $r.Out) -eq '') "out=$($r.Out)"

    # First turn of a session: no earlier Stop, so the whole session so far counts.
    $first = @()
    $first += Hook 'SubagentStop' 'implementer-stop.ps1' $SID -30 $notRun
    $firstLog = Join-Path $fixtureDir 'first.log'
    [IO.File]::WriteAllLines($firstLog, $first)
    $r = Invoke-Receipt $firstLog
    Add-Result 'C3_the_first_turn_counts_from_the_session_start' ((Get-Message $r.Out) -match 'implementer-stop NOT RUN') "out=$($r.Out)"

    $script:bash = $null
    foreach ($candidate in @('C:\Program Files\Git\bin\bash.exe', 'bash')) {
        if (Get-Command $candidate -ErrorAction SilentlyContinue) { $script:bash = $candidate; break }
    }
    if ($script:bash) {
        $rs = Invoke-Receipt $log 'sh'
        $rp = Invoke-Receipt $log
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
