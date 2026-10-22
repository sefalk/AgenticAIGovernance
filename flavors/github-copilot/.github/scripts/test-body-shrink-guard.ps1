# Regression suite: an agent cannot silently shrink a GitHub issue/PR body or comment (#376).
#
# `issue_write update`, `update_pull_request` and `update_issue_comment` replace
# the text; none of them patches. #197 measured that failure on ADO (35 % of a
# description lost) and its guard covers ADO only. This suite holds the GitHub
# twin to the decisions recorded on #376 (comment 6011491704):
#
#   - PostToolUse caches what a read returned: issue/PR bodies from issue_read,
#     pull_request_read and search results, comments from get_comments. A
#     successful write refreshes the cache from what it stored (K1).
#   - PreToolUse: an unread target -> deny; a read older than
#     WI_FIELD_READ_MAX_AGE_MIN -> deny (K2); `body` + `state` in one update ->
#     deny; a shrink or a lost heading -> WI_FIELD_SHRINK_POLICY.
#   - A shrink is declared in a preceding comment (A2), verified against the diff,
#     and ignored once a verdict has named the loss for that body.
#   - Text from the last `## Working state` heading on is not guarded.
#
# Reads are taken as verbatim: github-mcp-server >= 1.12.0, measured on #376.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ghDir = Split-Path -Parent $scriptDir
$hookScripts = Join-Path $ghDir 'hooks/scripts'
$preHook = Join-Path $hookScripts 'block-dangerous.ps1'
$postHook = Join-Path $hookScripts 'scan-secrets.ps1'
$preSh = Join-Path $hookScripts 'block-dangerous.sh'
$postSh = Join-Path $hookScripts 'scan-secrets.sh'
$shippedConf = Join-Path $ghDir 'af-env.conf'
$agentFiles = @((Join-Path $ghDir 'agents/gh-issue-manager.agent.md'), (Join-Path $ghDir 'agents/gh-pr-manager.agent.md'))

. (Join-Path $scriptDir '_suite_env.ps1')
$python = Get-AfSuitePython $scriptDir
if (-not $python) {
    Write-Host 'SKIP: no Python 3 interpreter found; the body guard is a Python core.'
    exit 0
}

$results = [ordered]@{}
$details = [ordered]@{}
function Add-Result([string]$Name, [bool]$Ok, [string]$Detail) {
    $script:results[$Name] = $Ok
    $script:details[$Name] = $Detail
}

$fixture = Join-Path ([IO.Path]::GetTempPath()) ("af376-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
$cacheDir = Join-Path $fixture 'cache'

function New-Conf([string]$Policy, [string]$MaxAge = '10') {
    $path = Join-Path $fixture ("conf-" + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.conf')
    [IO.File]::WriteAllText($path, "WI_FIELD_SHRINK_POLICY=$Policy`nWI_FIELD_SHRINK_PCT=10`nWI_FIELD_SHRINK_CHARS=200`nWI_FIELD_GUARD_MIN_CHARS=500`nWI_FIELD_READ_MAX_AGE_MIN=$MaxAge`n")
    return $path
}

function New-Section([string]$Title, [int]$Bullets) {
    $lines = @("### $Title", '')
    for ($i = 1; $i -le $Bullets; $i++) { $lines += "- $Title item $i carries enough words to make the section realistic." }
    return ($lines -join "`n")
}
$sections = @(
    (New-Section 'Scope' 4),
    (New-Section 'Key Modules Touched' 6),
    (New-Section 'Key Tests' 4),
    (New-Section 'Open Questions' 3)
)
$fullDesc = ($sections -join "`n`n")
$withoutTests = (@($sections[0], $sections[1], $sections[3]) -join "`n`n")
$withoutTestsAndQuestions = (@($sections[0], $sections[1]) -join "`n`n")
$editedInPlace = $fullDesc.Replace('item 1 carries', 'item 1 now carries')

# A working-state block long enough that rewriting it would trip the guard if it were guarded.
$wsLines = @('## Working state', '', '- **Updated:** 2026-10-06 by coordinator', '- **Open:** AC2, AC3', '', '### Decision log', '')
for ($i = 1; $i -le 8; $i++) { $wsLines += "- comment $i settled a question about the scope of part $i of the work." }
$wsLong = ($wsLines -join "`n")
$wsShort = "## Working state`n`n- **Updated:** 2026-10-07 by coordinator`n- **Open:** none"

function Body([string]$Desc, [string]$Ws = $wsLong) { return "$Desc`n`n$Ws" }
$issueBody = Body $fullDesc

function ConvertTo-JsonText([object]$Value) { return ($Value | ConvertTo-Json -Depth 10 -Compress) }

function Invoke-Hook([string]$Hook, [hashtable]$Payload, [string]$Conf, [string]$Dialect = 'ps', [int]$Skew = 0) {
    $json = $Payload | ConvertTo-Json -Depth 10 -Compress
    $prevConf = $env:AF_CONF_PATH; $prevCache = $env:AF_FIELD_CACHE_DIR; $prevSkew = $env:AF_FIELD_CLOCK_SKEW_SECONDS
    $env:AF_CONF_PATH = $Conf; $env:AF_FIELD_CACHE_DIR = $cacheDir; $env:AF_FIELD_CLOCK_SKEW_SECONDS = "$Skew"
    try {
        if ($Dialect -eq 'sh') {
            $out = $json | & $script:bashExe ($Hook -replace '\\', '/') 2>$null | Out-String
        } else {
            $out = $json | & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Hook 2>$null | Out-String
        }
    } finally {
        $env:AF_CONF_PATH = $prevConf; $env:AF_FIELD_CACHE_DIR = $prevCache; $env:AF_FIELD_CLOCK_SKEW_SECONDS = $prevSkew
    }
    $decision = ''; $reason = ''
    try {
        $o = $out | ConvertFrom-Json
        if ($o.PSObject.Properties['hookSpecificOutput'] -and $o.hookSpecificOutput.PSObject.Properties['permissionDecision']) {
            $decision = [string]$o.hookSpecificOutput.permissionDecision
            $reason = [string]$o.hookSpecificOutput.permissionDecisionReason
        }
    } catch { }
    return [pscustomobject]@{ Out = $out.Trim(); Decision = $decision; Reason = $reason }
}

$ask = New-Conf 'ask'

function Post([string]$Session, [string]$Tool, [hashtable]$ToolInput, [string]$Response, [string]$Dialect = 'ps') {
    $payload = @{ session_id = $Session; hook_event_name = 'PostToolUse'; tool_name = $Tool; tool_input = $ToolInput; tool_response = $Response; tool_use_id = 'p1' }
    $hook = if ($Dialect -eq 'sh') { $postSh } else { $postHook }
    $null = Invoke-Hook $hook $payload $ask $Dialect
}

function Pre([string]$Session, [string]$Tool, [hashtable]$ToolInput, [string]$Conf, [string]$Dialect = 'ps', [int]$Skew = 0) {
    $payload = @{ session_id = $Session; hook_event_name = 'PreToolUse'; tool_name = $Tool; tool_input = $ToolInput; tool_use_id = 'w1' }
    $hook = if ($Dialect -eq 'sh') { $preSh } else { $preHook }
    return Invoke-Hook $hook $payload $Conf $Dialect $Skew
}

$issueUrl = 'https://github.com/o/r/issues/5'
function Read-Issue([string]$Session, [string]$Body, [int]$Number = 5, [string]$Dialect = 'ps') {
    $resp = ConvertTo-JsonText ([ordered]@{ number = $Number; title = 't'; body = $Body; state = 'open'; html_url = "https://github.com/o/r/issues/$Number" })
    Post $Session 'mcp_github_mcp_se_issue_read' @{ method = 'get'; owner = 'o'; repo = 'r'; issue_number = $Number } $resp $Dialect
}
function Read-PR([string]$Session, [string]$Body) {
    $resp = ConvertTo-JsonText ([ordered]@{ number = 9; title = 't'; body = $Body; state = 'open'; html_url = 'https://github.com/o/r/pull/9' })
    Post $Session 'mcp_github_mcp_se_pull_request_read' @{ method = 'get'; owner = 'o'; repo = 'r'; pullNumber = 9 } $resp
}
function Read-Comments([string]$Session, [string]$Body) {
    $resp = ConvertTo-JsonText @([ordered]@{ id = 111; body = $Body; html_url = "$issueUrl#issuecomment-111" })
    Post $Session 'mcp_github_mcp_se_issue_read' @{ method = 'get_comments'; owner = 'o'; repo = 'r'; issue_number = 5 } $resp
}
function Declare([string]$Session, [string]$Text, [int]$Number = 5) {
    $resp = ConvertTo-JsonText ([ordered]@{ id = '900'; url = "https://github.com/o/r/issues/$Number#issuecomment-900" })
    Post $Session 'mcp_github_mcp_se_add_issue_comment' @{ owner = 'o'; repo = 'r'; issue_number = $Number; body = $Text } $resp
}
function Write-Issue([string]$Session, [string]$Body, [string]$Conf, [hashtable]$Extra = @{}, [string]$Dialect = 'ps', [int]$Skew = 0) {
    $ti = @{ method = 'update'; owner = 'o'; repo = 'r'; issue_number = 5; body = $Body }
    foreach ($k in $Extra.Keys) { $ti[$k] = $Extra[$k] }
    return Pre $Session 'mcp_github_mcp_se_issue_write' $ti $Conf $Dialect $Skew
}
function Wrote-Issue([string]$Session, [string]$Body, [string]$Response) {
    Post $Session 'mcp_github_mcp_se_issue_write' @{ method = 'update'; owner = 'o'; repo = 'r'; issue_number = 5; body = $Body } $Response
}
$okResponse = ConvertTo-JsonText ([ordered]@{ id = '42'; url = $issueUrl })

function New-Session { return 'sess-' + [guid]::NewGuid().ToString('N').Substring(0, 8) }
function Fresh { $n = New-Session; Read-Issue $n $issueBody; return $n }
function Decl([string]$Removed, [string]$Body) { return "af-shrink: body; remove: $Removed; expect: $($Body.Length)" }

$script:bashExe = @('C:\Program Files\Git\bin\bash.exe', '/bin/bash', '/usr/bin/bash') | Where-Object { Test-Path $_ } | Select-Object -First 1

try {
    # -- read before write --------------------------------------------------
    $r = Write-Issue (New-Session) (Body $withoutTests) $ask
    Add-Result 'B1_an_unread_body_write_is_denied' ($r.Decision -eq 'deny' -and $r.Reason -match '(?i)read') "decision='$($r.Decision)' reason='$($r.Reason)'"

    $r = Write-Issue (Fresh) (Body $editedInPlace) $ask
    Add-Result 'B2_an_in_place_edit_passes' ($r.Decision -eq '') "decision='$($r.Decision)' out=$($r.Out)"

    $r = Write-Issue (Fresh) (Body $withoutTestsAndQuestions) $ask
    Add-Result 'B3_the_197_replay_on_github_asks_and_names_the_loss' ($r.Decision -eq 'ask' -and $r.Reason -match 'Key Tests' -and $r.Reason -match 'Open Questions') "decision='$($r.Decision)' reason='$($r.Reason)'"

    # -- the working-state block is the sanctioned exception -------------------
    $r = Write-Issue (Fresh) (Body $fullDesc $wsShort) $ask
    Add-Result 'B4_rewriting_the_working_state_block_is_not_judged' ($r.Decision -eq '') "decision='$($r.Decision)' old=$($issueBody.Length) new=$((Body $fullDesc $wsShort).Length) reason='$($r.Reason)'"

    $r = Write-Issue (Fresh) (Body $withoutTests ($wsLong + "`n- comment 9 added.")) $ask
    Add-Result 'B5_loss_above_the_working_state_block_is_still_judged' ($r.Decision -eq 'ask' -and $r.Reason -match 'Key Tests') "decision='$($r.Decision)' reason='$($r.Reason)'"

    # -- body + state in one call --------------------------------------------
    $r = Write-Issue (Fresh) (Body $editedInPlace) $ask @{ state = 'closed'; state_reason = 'completed' }
    Add-Result 'B6_body_and_state_in_one_update_is_denied' ($r.Decision -eq 'deny' -and $r.Reason -match '(?i)comment') "decision='$($r.Decision)' reason='$($r.Reason)'"

    $r = Pre (New-Session) 'mcp_github_mcp_se_issue_write' @{ method = 'update'; owner = 'o'; repo = 'r'; issue_number = 5; state = 'closed'; state_reason = 'completed' } $ask
    Add-Result 'B7_a_state_only_close_is_not_judged' ($r.Decision -eq '') "decision='$($r.Decision)' out=$($r.Out)"

    # -- pull requests ----------------------------------------------------------
    $prWrite = @{ owner = 'o'; repo = 'r'; pullNumber = 9; body = (Body $withoutTestsAndQuestions) }
    $unreadPr = Pre (New-Session) 'mcp_github_mcp_se_update_pull_request' $prWrite $ask
    $sPr = New-Session
    Read-PR $sPr $issueBody
    $shrinkPr = Pre $sPr 'mcp_github_mcp_se_update_pull_request' $prWrite $ask
    $prClose = Pre $sPr 'mcp_github_mcp_se_update_pull_request' @{ owner = 'o'; repo = 'r'; pullNumber = 9; body = $issueBody; state = 'closed' } $ask
    Add-Result 'B8_update_pull_request_is_judged_like_an_issue' ($unreadPr.Decision -eq 'deny' -and $shrinkPr.Decision -eq 'ask' -and $prClose.Decision -eq 'deny') "unread='$($unreadPr.Decision)' shrink='$($shrinkPr.Decision)' body+state='$($prClose.Decision)'"

    # -- comments ---------------------------------------------------------------
    $cWrite = @{ owner = 'o'; repo = 'r'; comment_id = 111; body = $withoutTestsAndQuestions }
    $unreadC = Pre (New-Session) 'mcp_github_mcp_se_update_issue_comment' $cWrite $ask
    $sC = New-Session
    Read-Comments $sC $fullDesc
    $shrinkC = Pre $sC 'mcp_github_mcp_se_update_issue_comment' $cWrite $ask
    Add-Result 'B9_update_issue_comment_is_judged_against_get_comments' ($unreadC.Decision -eq 'deny' -and $shrinkC.Decision -eq 'ask' -and $shrinkC.Reason -match 'Key Tests') "unread='$($unreadC.Decision)' shrink='$($shrinkC.Decision)' reason='$($shrinkC.Reason)'"

    # -- freshness (K2) -----------------------------------------------------------
    $sOld = Fresh
    $stale = Write-Issue $sOld (Body $editedInPlace) $ask @{} 'ps' 660
    $longer = Write-Issue $sOld (Body $editedInPlace) (New-Conf 'ask' '30') @{} 'ps' 660
    Add-Result 'B10_a_read_older_than_the_max_age_is_denied' ($stale.Decision -eq 'deny' -and $stale.Reason -match '(?i)re-?read' -and $longer.Decision -eq '') "11min/10='$($stale.Decision)' 11min/30='$($longer.Decision)' reason='$($stale.Reason)'"

    # -- the session's own write refreshes the cache (K1) -------------------------
    $grown = Body ($fullDesc + "`n`n" + (New-Section 'Extra' 3))
    $sOwn = Fresh
    $first = Write-Issue $sOwn $grown $ask
    Wrote-Issue $sOwn $grown $okResponse
    $staleCopy = Write-Issue $sOwn $issueBody $ask
    Add-Result 'B11_a_write_from_a_copy_older_than_the_own_last_write_is_judged' ($first.Decision -eq '' -and $staleCopy.Decision -eq 'ask' -and $staleCopy.Reason -match 'Extra') "grow='$($first.Decision)' stale='$($staleCopy.Decision)' reason='$($staleCopy.Reason)'"

    $sFail = Fresh
    Wrote-Issue $sFail $grown 'failed to update issue: 422 Validation Failed'
    $after = Write-Issue $sFail $issueBody $ask
    Add-Result 'B12_a_failed_write_does_not_refresh_the_cache' ($after.Decision -eq '') "decision='$($after.Decision)' reason='$($after.Reason)'"

    # -- declarations in a preceding comment (A2) ---------------------------------
    $declared = New-Conf 'declared'
    $target = Body $withoutTests
    $none = Write-Issue (Fresh) $target $declared
    $sD = Fresh
    Declare $sD (Decl 'Key Tests' $target)
    $with = Write-Issue $sD $target $declared
    Add-Result 'B13_declared_policy_allows_a_matching_comment_declaration' ($none.Decision -eq 'ask' -and $with.Decision -eq '') "undeclared='$($none.Decision)' declared='$($with.Decision)' reason='$($with.Reason)'"

    $sW = Fresh
    Declare $sW (Decl 'Key Tests' $target)
    $r = Write-Issue $sW (Body $withoutTestsAndQuestions) $declared
    Add-Result 'B14_a_declaration_the_diff_contradicts_counts_as_none' ($r.Decision -eq 'ask') "decision='$($r.Decision)' reason='$($r.Reason)'"

    $strict = New-Conf 'declared-strict'
    $u = Write-Issue (Fresh) $target $strict
    $sS = Fresh
    Declare $sS (Decl 'Key Tests' $target)
    $d = Write-Issue $sS $target $strict
    Add-Result 'B15_declared_strict_denies_undeclared_and_allows_declared' ($u.Decision -eq 'deny' -and $d.Decision -eq '') "undeclared='$($u.Decision)' declared='$($d.Decision)'"

    $sX = Fresh
    Declare $sX (Decl 'Key Tests' $target)
    $r = Write-Issue $sX $target (New-Conf 'deny')
    Add-Result 'B16_deny_policy_denies_even_a_declared_shrink' ($r.Decision -eq 'deny') "decision='$($r.Decision)'"

    $sO = Fresh
    Declare $sO (Decl 'Key Tests' $target) 6
    $r = Write-Issue $sO $target $declared
    Add-Result 'B17_a_declaration_on_another_issue_does_not_count' ($r.Decision -eq 'ask') "decision='$($r.Decision)'"

    # The verdict names the loss; a declaration posted after it must not pass the copy.
    $sM = Fresh
    $v1 = Write-Issue $sM $target $declared
    Declare $sM (Decl 'Key Tests' $target)
    $v2 = Write-Issue $sM $target $declared
    Read-Issue $sM (Body $editedInPlace)
    $edited = @($sections | ForEach-Object { $_.Replace('item 1 carries', 'item 1 now carries') })
    $target2 = Body (@($edited[0], $edited[1], $edited[3]) -join "`n`n")
    Declare $sM (Decl 'Key Tests' $target2)
    $v3 = Write-Issue $sM $target2 $declared
    Add-Result 'B18_a_declaration_after_a_verdict_is_ignored_until_the_body_changed' `
        ($v1.Decision -eq 'ask' -and $v2.Decision -eq 'ask' -and $v3.Decision -eq '') "first='$($v1.Decision)' copied='$($v2.Decision)' after-change='$($v3.Decision)' reason='$($v3.Reason)'"

    # -- other read sources and creates ---------------------------------------------
    $sSearch = New-Session
    $resp = ConvertTo-JsonText ([ordered]@{ total_count = 1; items = @([ordered]@{ number = 5; title = 't'; body = $issueBody; html_url = $issueUrl }) })
    Post $sSearch 'mcp_github_mcp_se_search_issues' @{ query = 'repo:o/r x' } $resp
    $r = Write-Issue $sSearch (Body $editedInPlace) $ask
    Add-Result 'B19_a_search_result_counts_as_a_read' ($r.Decision -eq '') "decision='$($r.Decision)' reason='$($r.Reason)'"

    $sNew = New-Session
    Post $sNew 'mcp_github_mcp_se_issue_write' @{ method = 'create'; owner = 'o'; repo = 'r'; title = 't'; body = $issueBody } $okResponse
    $r = Write-Issue $sNew (Body $editedInPlace) $ask
    Add-Result 'B20_an_issue_created_in_this_session_counts_as_read' ($r.Decision -eq '') "decision='$($r.Decision)' reason='$($r.Reason)'"

    $short = 'A short body that stays under the guard threshold.'
    $sShort = New-Session
    Read-Issue $sShort (Body ($short * 6))
    $r = Write-Issue $sShort (Body $short) $ask
    Add-Result 'B21_a_body_under_the_guard_size_may_shrink' ($r.Decision -eq '') "decision='$($r.Decision)' guarded=$(($short * 6).Length)"

    $r = Pre (New-Session) 'mcp_github_mcp_se_sub_issue_write' @{ method = 'add'; owner = 'o'; repo = 'r'; issue_number = 5; sub_issue_id = 1 } $ask
    Add-Result 'B22_sub_issue_write_is_not_mistaken_for_issue_write' ($r.Decision -eq '') "decision='$($r.Decision)' out=$($r.Out)"

    # -- the other dialect gives the same verdicts --------------------------------
    if ($script:bashExe) {
        $sB = New-Session
        Read-Issue $sB $issueBody 5 'sh'
        $a = Write-Issue $sB (Body $withoutTestsAndQuestions) $ask @{} 'sh'
        $b = Write-Issue (New-Session) (Body $withoutTests) $ask @{} 'sh'
        $c = Write-Issue $sB (Body $editedInPlace) $ask @{ state = 'closed' } 'sh'
        Add-Result 'B23_the_bash_twins_give_the_same_verdicts' ($a.Decision -eq 'ask' -and $b.Decision -eq 'deny' -and $c.Decision -eq 'deny') "shrink='$($a.Decision)' unread='$($b.Decision)' body+state='$($c.Decision)'"
    } else {
        Add-Result 'B23_the_bash_twins_give_the_same_verdicts' $false 'no bash found -- this case would prove nothing'
    }

    # -- the shipped config and the worker contracts ---------------------------------
    $conf = Get-Content $shippedConf -Raw
    Add-Result 'B24_the_shipped_config_declares_the_read_max_age' ($conf -match '(?m)^WI_FIELD_READ_MAX_AGE_MIN=10\s*$') 'af-env.conf'

    $missing = @($agentFiles | Where-Object { (Get-Content $_ -Raw) -notmatch '(?m)^\|[^|\n]*(shrink|[Bb]ody)[^|\n]*\|\s*HARD\s*\|[^\n]*PreToolUse' } | ForEach-Object { Split-Path $_ -Leaf })
    Add-Result 'B25_both_github_workers_carry_a_hard_hook_row' ($missing.Count -eq 0) "missing in: $($missing -join ', ')"
} finally {
    Remove-Item $fixture -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output '===== GitHub body shrink guard tests (issue #376) ====='
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
