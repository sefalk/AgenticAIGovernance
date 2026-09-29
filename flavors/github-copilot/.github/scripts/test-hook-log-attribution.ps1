# Regression suite: every hook the log says ran is attributed to its script (#326).
#
# test-hooks-integration.ps1 matched `Running:` lines with one pattern for
# backslash .ps1 paths and one for forward-slash .sh paths. An agent-scoped hook
# is declared in .agent.md frontmatter with forward slashes and a .ps1 -- it fell
# through both, was never counted, and was then listed as an orphan candidate
# however often it fired. A stop-hook change could be attested by a run that
# reported the stop hooks never ran.
#
# The fixture logs below carry all three spellings the real log contains:
# `.github/hooks/scripts/x.ps1`, `.github\\hooks\\...` and `.github\\\\hooks\\\\...`.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$subject = Join-Path $scriptDir 'test-hooks-integration.ps1'

$results = [ordered]@{}
$details = [ordered]@{}
function Add-Result([string]$Name, [bool]$Ok, [string]$Detail) {
    $script:results[$Name] = $Ok
    $script:details[$Name] = $Detail
}

$fixtureDir = Join-Path ([IO.Path]::GetTempPath()) ("af326-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $fixtureDir -Force | Out-Null

$cwd = '"cwd":{"$mid":1,"fsPath":"c:\\\\Users\\\\x\\\\repo","_sep":1}'
function New-Invocation([int]$Seq, [string]$Event, [string[]]$Commands) {
    $ts = '2026-09-25 14:47:51.443 [info]'
    $out = @("$ts [#$Seq] [$Event] Executing $($Commands.Count) hook(s)")
    foreach ($c in $Commands) {
        $out += "$ts [#$Seq] [$Event] Running: {`"command`":`"$c`",$cwd}"
        $out += "$ts [#$Seq] [$Event] Input: {`"tool_name`":`"read_file`"}"
        $out += "$ts [#$Seq] [$Event] Completed (Success) in 10ms, no output"
    }
    return $out
}

$ps = 'powershell -ExecutionPolicy Bypass -File '
$good = @()
$good += New-Invocation 1 'PreToolUse' @(($ps + '.github\\hooks\\scripts\\block-dangerous.ps1'))
$good += New-Invocation 2 'PostToolUse' @(($ps + '.github\\\\hooks\\\\scripts\\\\scan-secrets.ps1'))
$good += New-Invocation 3 'SubagentStop' @(($ps + '.github/hooks/scripts/implementer-stop.ps1'))
$good += New-Invocation 4 'PreToolUse' @(($ps + '.github/hooks/scripts/test-writer-pretooluse.ps1'), 'bash .github/hooks/scripts/block-dangerous.sh')
$good += New-Invocation 5 'Stop' @(($ps + '.github\\hooks\\scripts\\stop-tests.ps1'))
$goodLog = Join-Path $fixtureDir 'good.log'
[IO.File]::WriteAllLines($goodLog, $good)

$bad = $good + (New-Invocation 6 'PreToolUse' @('node ./tools/custom-gate.js'))
$badLog = Join-Path $fixtureDir 'bad.log'
[IO.File]::WriteAllLines($badLog, $bad)

# Multi-root window: the consumer's deployed hook and the framework repo's dev hook, one call (#345).
$dup = $good + (New-Invocation 7 'PreToolUse' @(($ps + '.github\\hooks\\scripts\\block-dangerous.ps1'), ($ps + 'flavors/github-copilot/.github/hooks/scripts/block-dangerous.ps1')))
$dupLog = Join-Path $fixtureDir 'dup.log'
[IO.File]::WriteAllLines($dupLog, $dup)

function Invoke-Subject([string]$Log) {
    $ErrorActionPreference = 'Continue'
    $out = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $subject -LogPath $Log 2>&1 | Out-String
    return [pscustomobject]@{ Exit = $LASTEXITCODE; Out = $out }
}

function Get-Count([string]$Out, [string]$Name) {
    $m = [regex]::Match($Out, '(?m)^\s+' + [regex]::Escape($Name) + ' : (\d+) times')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return 0
}

try {
    $r = Invoke-Subject $goodLog
    Add-Result 'A1_the_suite_reads_a_log_it_is_pointed_at' ($r.Out -match 'Total hook invocations: 5\b') "exit=$($r.Exit) $($r.Out.Substring(0, [Math]::Min(300, $r.Out.Length)))"
    Add-Result 'A2_a_forward_slash_ps1_hook_is_attributed' ((Get-Count $r.Out 'implementer-stop.ps1') -eq 1 -and (Get-Count $r.Out 'test-writer-pretooluse.ps1') -eq 1) 'implementer-stop / test-writer-pretooluse'
    Add-Result 'A3_single_and_double_backslash_ps1_hooks_are_attributed' ((Get-Count $r.Out 'block-dangerous.ps1') -eq 1 -and (Get-Count $r.Out 'scan-secrets.ps1') -eq 1 -and (Get-Count $r.Out 'stop-tests.ps1') -eq 1) 'block-dangerous / scan-secrets / stop-tests'
    Add-Result 'A4_a_bash_hook_is_still_attributed' ((Get-Count $r.Out 'block-dangerous.sh') -eq 1) 'block-dangerous.sh'
    Add-Result 'A5_the_cwd_path_is_not_mistaken_for_a_script' ($r.Out -notmatch '(?m)^\s+repo : ') 'cwd must be ignored'
    Add-Result 'A6_a_fully_attributed_log_reports_no_unattributed_runs' ($r.Out -match 'PASS\s+Every hook run is attributed') 'expected the attribution check to pass'
    Add-Result 'D1_a_log_without_duplicates_reports_none' ($r.Out -match 'PASS\s+No hook script runs twice') 'expected the duplicate check to pass'

    $r = Invoke-Subject $dupLog
    Add-Result 'D2_the_same_script_twice_in_one_call_is_warned_and_named' `
        ($r.Out -match 'WARN\s+1 invocation\(s\) ran the same hook script twice' -and $r.Out -match 'block-dangerous\.ps1 x2') `
        "out=$($r.Out.Substring([Math]::Max(0, $r.Out.IndexOf('## Integration Checks'))))"
    Add-Result 'D3_a_duplicate_warns_but_does_not_fail_the_run' ($r.Exit -eq 0) "exit=$($r.Exit)"

    $r = Invoke-Subject $badLog
    Add-Result 'W1_an_unattributable_run_fails_loudly_and_is_quoted' `
        ($r.Exit -eq 1 -and $r.Out -match 'FAIL\s+.*not attributed' -and $r.Out.Contains('custom-gate.js')) `
        "exit=$($r.Exit)"
} finally {
    Remove-Item $fixtureDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output '===== hook log attribution tests (issue #326) ====='
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
