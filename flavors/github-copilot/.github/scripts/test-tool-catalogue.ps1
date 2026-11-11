# Regression tests for the tool-catalogue corpus report (tool-catalogue-report.py, #221).
#
# Synthetic debug-log fixtures only: hand-built tools_N.json dumps and tool_call
# spans in throwaway temp dirs. A real session log is never copied.
# Run from anywhere:
#   pwsh .github/scripts/test-tool-catalogue.ps1
# Exits non-zero if any scenario fails (CI-friendly).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$subject = Join-Path $scriptDir 'tool-catalogue-report.py'
. (Join-Path $scriptDir '_suite_env.ps1')
$python = Get-AfSuitePython $scriptDir
if (-not $python) { Write-Output 'SKIP: no Python 3 interpreter found; cannot run tool-catalogue tests.'; exit 0 }

$results = [ordered]@{}
$details = [ordered]@{}
function Add-Result([string]$Name, [bool]$Ok, [string]$Detail) {
    $script:results[$Name] = $Ok
    $script:details[$Name] = $Detail
}

$fixtureDir = Join-Path ([IO.Path]::GetTempPath()) ("af221-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$CANARY = 'SUPERSECRET-ghp_catalogue221'

function J($h) { $h | ConvertTo-Json -Compress -Depth 6 }

# One session: a tools dump dated $Date, and a main.jsonl with one tool_call per name in $Calls.
function New-Session([string]$Root, [string]$Sid, [datetime]$Date, [string[]]$Tools, [string[]]$Calls = @()) {
    $dir = Join-Path $Root $Sid
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $defs = @($Tools | ForEach-Object { [ordered]@{ name = $_; description = ('D' * 402) } })
    $dump = Join-Path $dir 'tools_0.json'
    # -InputObject: piping a one-element array would unroll it into a bare object.
    [IO.File]::WriteAllText($dump, (J ([ordered]@{ content = (ConvertTo-Json -InputObject $defs -Compress -Depth 6) })))
    (Get-Item $dump).LastWriteTime = $Date
    $lines = @(J ([ordered]@{ v = 1; ts = 1785760263230; sid = $Sid; type = 'session_start'; name = 'session_start'; spanId = 's0'; status = 'ok'; attrs = @{} }))
    foreach ($c in $Calls) {
        $lines += J ([ordered]@{ ts = 1785760264230; sid = $Sid; type = 'tool_call'; name = $c; spanId = 't1'; parentSpanId = 's0'; status = 'ok'; attrs = [ordered]@{ args = $CANARY; result = $CANARY } })
    }
    [IO.File]::WriteAllText((Join-Path $dir 'main.jsonl'), (($lines -join "`n") + "`n"))
}

function Invoke-Report([string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
    $out = & $python $subject @Arguments 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    return @{ Out = $out; Code = $code }
}

function Get-Row([string]$Text, [string]$Group) {
    $line = ($Text -split "`r?`n") | Where-Object { $_ -match ('^\|\s*' + [regex]::Escape($Group) + '\s*\|') } | Select-Object -First 1
    if ($line) { return [string]$line }
    return ''
}

try {
    # --- main corpus: four sessions inside the window, one older one ---------
    $main = Join-Path $fixtureDir 'main'
    $inWindow = @('read_file', 'mcp_github_issue_read', 'mcp_idle_probe')
    New-Session $main 'a1' ([datetime]'2026-11-01 10:00') $inWindow @('read_file', 'mcp_github_issue_read')
    New-Session $main 'a2' ([datetime]'2026-11-02 10:00') $inWindow @('mcp_github_issue_read')
    New-Session $main 'a3' ([datetime]'2026-11-03 10:00') $inWindow @('read_file')
    New-Session $main 'a4' ([datetime]'2026-11-04 10:00') $inWindow
    New-Session $main 'old' ([datetime]'2026-08-01 10:00') @('read_file', 'mcp_gone_tool', 'mcp_idle_probe') @('mcp_idle_probe', 'mcp_idle_probe')
    # a4 also kept an earlier dump from before a server was switched off: the server's date is that dump's, not the session's.
    $early = Join-Path $main 'a4\tools_1.json'
    $earlyDefs = @([ordered]@{ name = 'mcp_switched_off'; description = ('D' * 402) })
    [IO.File]::WriteAllText($early, (J ([ordered]@{ content = (ConvertTo-Json -InputObject $earlyDefs -Compress -Depth 6) })))
    (Get-Item $early).LastWriteTime = [datetime]'2026-09-01 10:00'
    $before = @(Get-ChildItem $main -Recurse -File | ForEach-Object { "$($_.FullName)|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)" })

    $r = Invoke-Report @($main, '--window-days', '30', '--min-sessions', '3')
    $out = $r.Out
    $idle = Get-Row $out 'mcp:idle'
    $github = Get-Row $out 'mcp:github'
    $gone = Get-Row $out 'mcp:gone'
    $builtin = Get-Row $out 'built-in'
    # Compact schema {"name":"..","description":".."} at 4 chars per token, as collect-session-cost estimates it.
    $idleTok = [math]::Round((28 + 'mcp_idle_probe'.Length + 402) / 4)
    $githubTok = [math]::Round((28 + 'mcp_github_issue_read'.Length + 402) / 4)

    Add-Result 'R1_a_sufficient_corpus_reports_with_exit_0' ($r.Code -eq 0) "exit=$($r.Code) out=$out"
    Add-Result 'R2_corpus_size_and_date_range_are_stated' ($out -match '4 sessions' -and $out -match '2026-11-01' -and $out -match '2026-11-04' -and $out -match '5 sessions') $out
    Add-Result 'R3_unused_server_in_window_is_a_candidate' ($idle -match 'candidate' -and $idle -match "\|\s*$idleTok\s*\|" -and $idle -match '\|\s*0\s*\|') "row='$idle'"
    Add-Result 'R4_cost_and_calls_share_one_row' ($github -match "\|\s*$githubTok\s*\|" -and $github -match '\|\s*2\s*\|' -and $github -match 'in use' -and $github -notmatch 'candidate') "row='$github'"
    Add-Result 'R5_calls_outside_the_window_do_not_rescue_a_server' ($idle -ne '' -and $idle -notmatch '\|\s*2\s*\|') "row='$idle'"
    Add-Result 'R6_server_absent_from_the_window_is_reported_as_off_not_candidate' ($gone -match '2026-08-01' -and $gone -notmatch 'candidate') "row='$gone'"
    Add-Result 'R7_built_in_tools_are_never_candidates' ($builtin -ne '' -and $builtin -notmatch 'candidate') "row='$builtin'"
    $switched = Get-Row $out 'mcp:switched'
    Add-Result 'R11_last_seen_is_the_date_of_the_dump_that_carried_the_server' ($switched -match '2026-09-01' -and $switched -match 'not delivered in window') "row='$switched'"
    Add-Result 'R8_report_says_nothing_is_disabled' ($out -match 'nothing is disabled') $out
    Add-Result 'R9_no_call_arguments_or_results_are_copied' ($github -ne '' -and $out -notmatch [regex]::Escape($CANARY)) 'canary leaked'
    $after = @(Get-ChildItem $main -Recurse -File | ForEach-Object { "$($_.FullName)|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)" })
    Add-Result 'R10_the_corpus_is_left_untouched' ((Compare-Object $before $after) -eq $null) 'files changed under the corpus root'

    # --- too small a corpus: BLOCKED, not a conclusion ------------------------
    $r = Invoke-Report @($main, '--window-days', '30')
    Add-Result 'B1_too_small_a_corpus_is_blocked_exit_2' ($r.Code -eq 2 -and $r.Out -match 'BLOCKED' -and $r.Out -match '\b4\b' -and $r.Out -match '\b10\b' -and $r.Out -notmatch 'candidate') "exit=$($r.Code) out=$($r.Out)"

    # --- no session data: BLOCKED with a reason, never a silent pass ---------
    $empty = Join-Path $fixtureDir 'empty'
    New-Item -ItemType Directory -Path $empty -Force | Out-Null
    $r = Invoke-Report @($empty, '--min-sessions', '1')
    Add-Result 'B2_no_session_data_is_blocked_exit_2' ($r.Code -eq 2 -and $r.Out -match 'BLOCKED' -and $r.Out -match 'no session') "exit=$($r.Code) out=$($r.Out)"
    $r = Invoke-Report @((Join-Path $fixtureDir 'absent'), '--min-sessions', '1')
    Add-Result 'B3_a_missing_root_is_blocked_exit_2' ($r.Code -eq 2 -and $r.Out -match 'BLOCKED') "exit=$($r.Code) out=$($r.Out)"

    # --- an unreadable dump is skipped, not fatal -----------------------------
    $bad = Join-Path $fixtureDir 'bad'
    New-Session $bad 'b1' ([datetime]'2026-11-01 10:00') @('mcp_idle_probe')
    New-Item -ItemType Directory -Path (Join-Path $bad 'b2') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $bad 'b2\tools_0.json'), 'not json')
    $r = Invoke-Report @($bad, '--min-sessions', '1')
    Add-Result 'U1_an_unreadable_dump_is_skipped_and_counted' ($r.Code -eq 0 -and $r.Out -match '1 session' -and $r.Out -match 'unreadable') "exit=$($r.Code) out=$($r.Out)"

    # --- agent mode: the catalogue an agent's tools: list delivers vs the unrestricted one ---
    $modes = Join-Path $fixtureDir 'modes'
    $plain = @('read_file', 'mcp_github_issue_read', 'mcp_idle_probe')
    New-Session $modes 'm1' ([datetime]'2026-11-04 10:00') $plain
    $m1 = Join-Path $modes 'm1'
    $agentDefs = @([ordered]@{ name = 'read_file'; description = ('D' * 402) }, [ordered]@{ name = 'mcp_agentonly_x'; description = ('D' * 402) })
    $agentDump = Join-Path $m1 'tools_1.json'
    [IO.File]::WriteAllText($agentDump, (J ([ordered]@{ content = (ConvertTo-Json -InputObject $agentDefs -Compress -Depth 6) })))
    (Get-Item $agentDump).LastWriteTime = [datetime]'2026-11-04 10:00'
    [IO.File]::WriteAllText((Join-Path $m1 'system_prompt_0.json'), (J ([ordered]@{ content = "You are an assistant. $CANARY" })))
    # Real shape (measured 2026-11-11): content is itself JSON, so the quotes around the mode name arrive escaped.
    $agentPrompt = ConvertTo-Json -InputObject @([ordered]@{ type = 'text'; content = "<modeInstructions>`nYou are currently running in `"coordinator`" mode. $CANARY" }) -Compress -Depth 6
    [IO.File]::WriteAllText((Join-Path $m1 'system_prompt_1.json'), (J ([ordered]@{ content = $agentPrompt })))
    $requests = @()
    foreach ($i in 1..3) { $requests += J ([ordered]@{ ts = 1785760265000 + $i; sid = 'm1'; type = 'llm_request'; name = 'chat:x'; spanId = "r$i"; status = 'ok'; attrs = [ordered]@{ debugName = 'panel/editAgent'; systemPromptFile = 'system_prompt_0.json'; toolsFile = 'tools_0.json'; userRequest = $CANARY } }) }
    $requests += J ([ordered]@{ ts = 1785760266000; sid = 'm1'; type = 'llm_request'; name = 'chat:x'; spanId = 'r4'; status = 'ok'; attrs = [ordered]@{ debugName = 'panel/editAgent'; systemPromptFile = 'system_prompt_1.json'; toolsFile = 'tools_1.json' } })
    [IO.File]::AppendAllText((Join-Path $m1 'main.jsonl'), (($requests -join "`n") + "`n"))

    $r = Invoke-Report @($modes, '--min-sessions', '1')
    $mout = $r.Out
    $plainTok = [math]::Round((($plain | ForEach-Object { 28 + $_.Length + 402 }) | Measure-Object -Sum).Sum / 4)
    $agentTok = [math]::Round(((28 + 9 + 402) + (28 + 15 + 402)) / 4)
    $defaultRow = Get-Row $mout 'default (no agent)'
    $coordRow = Get-Row $mout 'coordinator'
    Add-Result 'M1_requests_are_split_by_agent_mode_with_share_and_catalogue_cost' ($r.Code -eq 0 -and $defaultRow -match '\|\s*3\s*\|\s*75 %\s*\|' -and $defaultRow -match "\|\s*$plainTok\s*\|" -and $coordRow -match '\|\s*1\s*\|\s*25 %\s*\|' -and $coordRow -match "\|\s*$agentTok\s*\|") "exit=$($r.Code) out=$mout"
    $agentOnly = Get-Row $mout 'mcp:agentonly'
    Add-Result 'M2_a_server_only_in_an_agent_tools_list_is_not_a_candidate' ($agentOnly -match 'agent tools only' -and $agentOnly -notmatch 'candidate') "row='$agentOnly'"
    $idleM = Get-Row $mout 'mcp:idle'
    Add-Result 'M3_unrestricted_servers_are_still_judged' ($idleM -match 'candidate') "row='$idleM'"
    Add-Result 'M4_only_the_mode_name_leaves_the_system_prompt' ($mout -notmatch [regex]::Escape($CANARY) -and $mout -match 'coordinator') 'canary leaked or mode missing'
} finally {
    Remove-Item $fixtureDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output '===== tool-catalogue report tests (issue #221) ====='
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
