# Regression suite: flight-report.py renders one offline HTML per session (#476).
#
# The report joins three records AF already keeps -- the session's debug logs,
# the hook log and the cost collector -- on one time axis. The fixture pins what
# a reader relies on: lane order and overlap, which gate verdicts belong to the
# session, cost by agent x model, that no prompt or argument text leaks, that
# the page loads nothing from the network, and that every panel declares its
# kind (#477).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$subject = Join-Path $scriptDir 'flight-report.py'
. (Join-Path $scriptDir '_suite_env.ps1')
$python = Get-AfSuitePython $scriptDir
if (-not $python) { Write-Output 'SKIP: no Python 3 interpreter found; cannot run flight-report tests.'; exit 0 }

$results = [ordered]@{}
$details = [ordered]@{}
function Add-Result([string]$Name, [bool]$Ok, [string]$Detail) {
    $script:results[$Name] = $Ok
    $script:details[$Name] = $Detail
}

$fixtureDir = Join-Path ([IO.Path]::GetTempPath()) ("af476-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$SID = 'f1f1f1f1-0000-4000-8000-000000000476'
$OTHER = 'e2e2e2e2-0000-4000-8000-000000000476'
$T0 = 1785760263230
$CANARY = 'SUPERSECRET-ghp_flight476'
$sessionDir = Join-Path $fixtureDir $SID
New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null

function J([hashtable]$h) { $h | ConvertTo-Json -Compress -Depth 6 }
function Start-Span([long]$Ts) {
    J ([ordered]@{ v = 1; ts = $Ts; dur = 0; sid = $SID; type = 'session_start'; name = 'session_start'; spanId = 's0'; status = 'ok'; attrs = [ordered]@{ copilotVersion = '0.59.0'; vscodeVersion = '1.131.0' } })
}
function Request([long]$Ts, [string]$Model, [long]$Nano) {
    J ([ordered]@{ ts = $Ts; dur = 100; sid = $SID; type = 'llm_request'; name = "chat:$Model"; spanId = "r$Ts"; parentSpanId = 's0'; status = 'ok'
        attrs = [ordered]@{ model = $Model; debugName = 'panel/editAgent'; inputTokens = 1000; outputTokens = 50; cachedTokens = 400; copilotUsageNanoAiu = $Nano; userRequest = $CANARY } })
}
function Edit([long]$Ts, [string]$Tool, [string]$Path) {
    $argJson = (J ([ordered]@{ filePath = $Path; content = $CANARY }))
    J ([ordered]@{ ts = $Ts; dur = 5; sid = $SID; type = 'tool_call'; name = $Tool; spanId = "t$Ts"; parentSpanId = 's0'; status = 'ok'; attrs = [ordered]@{ args = $argJson; result = $CANARY } })
}

[IO.File]::WriteAllLines((Join-Path $sessionDir 'main.jsonl'), @(
    (Start-Span $T0),
    (Request ($T0 + 1000) 'claude-opus-5' 2000000000),
    (Edit ($T0 + 1500) 'create_file' 'src/a.py'),
    (Request ($T0 + 5000) 'claude-opus-5' 1000000000)
))
# Two subagents that overlap: implementer 2000..4000, test-writer 3000..3500.
[IO.File]::WriteAllLines((Join-Path $sessionDir 'runSubagent-implementer-toolu_A1.jsonl'), @(
    (Request ($T0 + 2000) 'claude-sonnet-5' 1000000000),
    (Edit ($T0 + 2500) 'replace_string_in_file' 'src/b.py'),
    (Request ($T0 + 4000) 'claude-sonnet-5' 500000000)
))
[IO.File]::WriteAllLines((Join-Path $sessionDir 'runSubagent-test-writer-toolu_B2.jsonl'), @(
    (Request ($T0 + 3000) 'claude-haiku-4.5' 250000000),
    (Edit ($T0 + 3500) 'create_file' 'tests/test_b.py')
))

function Iso([long]$Ms) { [DateTimeOffset]::FromUnixTimeMilliseconds($Ms).UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') }
$script:seq = 0
function Hook([string]$Event, [string]$Script, [string]$Sid, [long]$Ms, [string]$Output) {
    $script:seq++
    $p = "2026-10-31 20:00:00.000 [info] [#$($script:seq)] [$Event]"
    $lines = @(
        "$p Running: {`"command`":`"powershell -File .github/hooks/scripts/$Script`"}",
        "$p Input: {`"timestamp`":`"$(Iso $Ms)`",`"hook_event_name`":`"$Event`",`"session_id`":`"$Sid`",`"tool_input`":`"$CANARY`"}"
    )
    if ($Output) { $lines += "$p Completed (Success) in 90ms"; $lines += "$p Output: $Output" }
    else { $lines += "$p Completed (Success) in 90ms, no output" }
    return $lines
}
$hook = @()
$hook += Hook 'PreToolUse' 'block-dangerous.ps1' $SID ($T0 + 1400) '{"hookSpecificOutput":{"permissionDecision":"deny","hookEventName":"PreToolUse"}}'
$hook += Hook 'PreToolUse' 'block-dangerous.ps1' $SID ($T0 + 2400) ''
$hook += Hook 'SubagentStop' 'implementer-stop.ps1' $SID ($T0 + 4100) '{"systemMessage":"implementer:Stop -- Green gate NOT RUN (no pytest in the code root .venv or on PATH)"}'
# Another session in the same window: never part of this report.
$hook += Hook 'PreToolUse' 'block-dangerous.ps1' $OTHER ($T0 + 1600) '{"hookSpecificOutput":{"permissionDecision":"deny","hookEventName":"PreToolUse"}}'
$hookLog = Join-Path $fixtureDir 'hooks.log'
[IO.File]::WriteAllLines($hookLog, $hook)

try {
    $out = Join-Path $fixtureDir 'flight.html'
    $ErrorActionPreference = 'Continue'
    $run = & $python $subject --session-dir $sessionDir --log $hookLog --out $out 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    $html = if (Test-Path $out) { [IO.File]::ReadAllText($out) } else { '' }
    Add-Result 'R1_one_html_file_is_written' ($code -eq 0 -and $html -match '(?i)<!doctype html>') "exit=$code out=$run"

    $lanes = @([regex]::Matches($html, '<div class="lane" data-lane="([^"]+)"[^>]*data-start="(\d+)" data-end="(\d+)"[^>]*data-requests="(\d+)"[^>]*data-edits="(\d+)"') |
        ForEach-Object { [pscustomobject]@{ Agent = $_.Groups[1].Value; Start = [long]$_.Groups[2].Value; End = [long]$_.Groups[3].Value; Requests = [int]$_.Groups[4].Value; Edits = [int]$_.Groups[5].Value } })
    $laneOrder = @($lanes | ForEach-Object { $_.Agent }) -join ','
    Add-Result 'L1_lanes_are_ordered_by_start' ($laneOrder -eq 'main,implementer,test-writer') "lanes=$laneOrder"
    $impl = $lanes | Where-Object { $_.Agent -eq 'implementer' }
    $tw = $lanes | Where-Object { $_.Agent -eq 'test-writer' }
    Add-Result 'L2_overlapping_lanes_keep_their_own_span' `
        ($impl -and $tw -and $impl.Start -eq ($T0 + 2000) -and $impl.End -eq ($T0 + 4000) -and $tw.Start -eq ($T0 + 3000) -and $tw.End -eq ($T0 + 3500)) `
        "implementer=$($impl | ConvertTo-Json -Compress) test-writer=$($tw | ConvertTo-Json -Compress)"
    Add-Result 'L3_lanes_count_requests_and_edits' ($impl -and $impl.Requests -eq 2 -and $impl.Edits -eq 1 -and $tw.Requests -eq 1 -and $tw.Edits -eq 1) "$($lanes | ConvertTo-Json -Compress)"

    $cells = @([regex]::Matches($html, '<span class="cell ([a-z_]+)" data-script="([^"]+)"') | ForEach-Object { "$($_.Groups[1].Value):$($_.Groups[2].Value)" })
    Add-Result 'G1_only_this_sessions_verdicts_are_cells' `
        ($cells.Count -eq 3 -and ($cells -contains 'deny:block-dangerous.ps1') -and ($cells -contains 'silent:block-dangerous.ps1') -and ($cells -contains 'not_run:implementer-stop.ps1')) `
        "cells=$($cells -join ', ')"

    $rows = @([regex]::Matches($html, '<tr data-agent="([^"]+)" data-model="([^"]+)" data-requests="(\d+)" data-credits="([0-9.]+)"') |
        ForEach-Object { "$($_.Groups[1].Value)|$($_.Groups[2].Value)|$($_.Groups[3].Value)|$([double]$_.Groups[4].Value)" })
    Add-Result 'C1_cost_by_agent_and_model' `
        (($rows -contains 'main|claude-opus-5|2|3') -and ($rows -contains 'implementer|claude-sonnet-5|2|1.5') -and ($rows -contains 'test-writer|claude-haiku-4.5|1|0.25')) `
        "rows=$($rows -join '; ')"
    Add-Result 'C2_coverage_is_shown_with_its_kind' ($html -match 'data-coverage="full"' -and $html -match 'data-panel="cost" data-kind="measured"') 'cost panel coverage/kind'

    $logItems = @([regex]::Matches($html, '<li data-ts="(\d+)" data-what="([a-z_-]+)"') | ForEach-Object { [long]$_.Groups[1].Value })
    $sorted = @($logItems | Sort-Object)
    Add-Result 'V1_the_log_is_chronological_and_has_the_deny' `
        ($logItems.Count -ge 5 -and (($logItems -join ',') -eq ($sorted -join ',')) -and $html -match '<li data-ts="\d+" data-what="deny"') "items=$($logItems -join ',')"

    Add-Result 'P1_no_prompt_argument_or_tool_text_leaks' ($html.Length -gt 0 -and $html -notmatch 'SUPERSECRET') 'canary found in the report'
    Add-Result 'O1_the_page_loads_nothing_from_the_network' `
        ($html.Length -gt 0 -and $html -notmatch '(?i)<script[^>]+src=|<link[^>]+href=|@import|url\(\s*["'']?https?:|src=["'']https?:') 'external reference found'
    $panels = @([regex]::Matches($html, '<section class="panel" data-panel="([a-z]+)" data-kind="(measured|inferred|lower_bound)"') | ForEach-Object { $_.Groups[1].Value })
    Add-Result 'K1_every_panel_declares_its_kind' ((($panels | Sort-Object) -join ',') -eq 'context,cost,gates,lanes,log') "panels=$($panels -join ',')"

    # #479: one context series per lane; the fixture's requests all read 1000 tokens.
    $ctx = @([regex]::Matches($html, '<polyline class="ctx" data-lane="([^"]+)" data-floor="([0-9a-z]+)" data-median="(\d+)" data-max="(\d+)" data-drops="(\d+)"') |
        ForEach-Object { "$($_.Groups[1].Value)|$($_.Groups[2].Value)|$($_.Groups[4].Value)|$($_.Groups[5].Value)" })
    Add-Result 'X1_context_series_per_lane' (($ctx -contains 'main|1000|1000|0') -and ($ctx -contains 'implementer|1000|1000|0') -and $ctx.Count -eq 3) "ctx=$($ctx -join '; ')"

    # A truncated session: the cost panel is a lower bound, never a total.
    $truncDir = Join-Path $fixtureDir 'aaaaaaaa-0000-4000-8000-000000000476'
    New-Item -ItemType Directory -Path $truncDir -Force | Out-Null
    [IO.File]::WriteAllLines((Join-Path $truncDir 'main.jsonl'), @((Request ($T0 + 1000) 'claude-opus-5' 2000000000)))
    $tout = Join-Path $fixtureDir 'trunc.html'
    $ErrorActionPreference = 'Continue'
    & $python $subject --session-dir $truncDir --log $hookLog --out $tout 2>&1 | Out-Null
    $ErrorActionPreference = 'Stop'
    $thtml = if (Test-Path $tout) { [IO.File]::ReadAllText($tout) } else { '' }
    Add-Result 'C3_a_truncated_session_is_a_lower_bound' ($thtml -match 'data-panel="cost" data-kind="lower_bound"' -and $thtml -match 'data-coverage="truncated"') 'truncated cost panel'
    Add-Result 'X2_a_truncated_main_log_has_no_floor' ($thtml -match '<polyline class="ctx" data-lane="main" data-floor="missing"') 'truncated context floor'

    $ErrorActionPreference = 'Continue'
    & $python $subject --session-dir (Join-Path $fixtureDir 'absent') --log $hookLog --out (Join-Path $fixtureDir 'x.html') 2>&1 | Out-Null
    $absentCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    Add-Result 'E1_a_missing_session_is_exit_2' ($absentCode -eq 2 -and -not (Test-Path (Join-Path $fixtureDir 'x.html'))) "exit=$absentCode"
} finally {
    Remove-Item $fixtureDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output '===== flight report tests (issue #476) ====='
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
