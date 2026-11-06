# Regression suite: gate-health.py reads what each hook decided (#475).
#
# The defect class: a gate that stops gating while every verdict reads PASS.
# Live, 15 of 15 producer stop verdicts on 2026-10-22..28 said "pytest not
# found" and nobody saw it (#473). The fixtures below use the real Hooks.log
# line shapes, including the exact wordings those verdicts carried.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$subject = Join-Path $scriptDir 'gate-health.py'
. (Join-Path $scriptDir '_suite_env.ps1')
$python = Get-AfSuitePython $scriptDir
if (-not $python) { Write-Output 'SKIP: no Python 3 interpreter found; cannot run gate-health tests.'; exit 0 }

$results = [ordered]@{}
$details = [ordered]@{}
function Add-Result([string]$Name, [bool]$Ok, [string]$Detail) {
    $script:results[$Name] = $Ok
    $script:details[$Name] = $Detail
}

$fixtureDir = Join-Path ([IO.Path]::GetTempPath()) ("af475-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $fixtureDir -Force | Out-Null

$cwd = '"cwd":{"$mid":1,"fsPath":"c:\\\\Users\\\\x\\\\repo","_sep":1}'
$ps = 'powershell -ExecutionPolicy Bypass -File '
$script:seq = 0
function New-Run([string]$Event, [string]$Script, [string]$Output, [string]$Day = '2026-10-27') {
    $script:seq++
    $ts = "$Day 23:10:08.337 [info] [#$($script:seq)] [$Event]"
    $out = @("$ts Executing 1 hook(s)", "$ts Running: {`"command`":`"$($ps + '.github/hooks/scripts/' + $Script)`",$cwd}", "$ts Input: {`"hook_event_name`":`"$Event`"}")
    if ($Output) {
        $out += "$ts Completed (Success) in 120ms"
        $out += "$ts Output: $Output"
    } else {
        $out += "$ts Completed (Success) in 120ms, no output"
    }
    return $out
}

$lines = @()
# The live #473 wordings, verbatim.
1..3 | ForEach-Object { $lines += New-Run 'SubagentStop' 'implementer-stop.ps1' '{"systemMessage":"implementer:Stop -- Green gate PASS: tests gate skipped (pytest not found), provenance + python quality verified, linting: no python changes"}' }
1..3 | ForEach-Object { $lines += New-Run 'SubagentStop' 'test-writer-stop.ps1' '{"systemMessage":"test-writer:Stop -- pytest not found, Red gate skipped"}' }
# A gate that ran and passed, then blocked once.
1..3 | ForEach-Object { $lines += New-Run 'SubagentStop' 'refactorer-stop.ps1' '{"systemMessage":"refactorer:Stop -- all gates PASS: tests green"}' }
$lines += New-Run 'SubagentStop' 'refactorer-stop.ps1' '{"hookSpecificOutput":{"hookEventName":"Stop","decision":"block","reason":"Refactor phase violation"}}'
# The loop guard skips on purpose; not an inert gate.
1..3 | ForEach-Object { $lines += New-Run 'SubagentStop' 'documenter-stop.ps1' '{"systemMessage":"documenter:Stop -- gates NOT run: the input carries stop_hook_active true"}' }
# PreToolUse decisions, silence, and an escaped Output line as the log sometimes writes it.
$lines += New-Run 'PreToolUse' 'block-dangerous.ps1' '{"hookSpecificOutput":{"permissionDecision":"deny","hookEventName":"PreToolUse"}}'
$lines += New-Run 'PreToolUse' 'block-dangerous.ps1' '{"hookSpecificOutput":{"permissionDecision":"ask","hookEventName":"PreToolUse"}}'
$lines += New-Run 'PreToolUse' 'block-dangerous.ps1' ''
$lines += New-Run 'SubagentStop' 'implementer-stop.ps1' '{\"systemMessage\":\"implementer:Stop -- Green gate NOT RUN (no pytest in the code root .venv or on PATH)\"}'
# A tool response quoting an old Running line must not count as a run.
$lines += "2026-10-27 23:11:00.000 [info] [#900] [PostToolUse] Input: {`"tool_response`":`"... Running: {\`"command\`":\`"powershell -File .github/hooks/scripts/ghost-stop.ps1\`"} ...`"}"
# A timeout.
$lines += "2026-10-27 23:12:00.000 [info] [HookExecutor] Hook command timed out after 5s: powershell -ExecutionPolicy Bypass -File .github\hooks\scripts\block-dangerous.ps1"
# Before --since: ignored.
$lines += New-Run 'SubagentStop' 'test-writer-stop.ps1' '{"systemMessage":"test-writer:Stop -- Red gate PASS: tests are failing as expected."}' '2026-10-01'
$log = Join-Path $fixtureDir 'hooks.log'
[IO.File]::WriteAllLines($log, $lines)

# Declarations: one global hook (both dialects) that ran, one agent hook that never did.
$gh = Join-Path $fixtureDir '.github'
New-Item -ItemType Directory -Path (Join-Path $gh 'hooks'), (Join-Path $gh 'agents') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $gh 'hooks/agent-hooks.json'), '{"hooks":{"PreToolUse":[{"type":"command","command":"bash .github/hooks/scripts/block-dangerous.sh","windows":"powershell -ExecutionPolicy Bypass -File .github\\hooks\\scripts\\block-dangerous.ps1"}],"SessionStart":[{"type":"command","command":"bash .github/hooks/scripts/session-context.sh","windows":"powershell -File .github\\hooks\\scripts\\session-context.ps1"}]}}')
[IO.File]::WriteAllText((Join-Path $gh 'agents/researcher.agent.md'), "---`nname: researcher`nhooks:`n  PreToolUse:`n    - type: command`n      command: 'bash .github/hooks/scripts/researcher-pretooluse.sh'`n      windows: 'powershell -File .github/hooks/scripts/researcher-pretooluse.ps1'`n---`nbody mentions .github/hooks/scripts/not-a-declaration.ps1`n")

function Invoke-Subject([string[]]$Extra) {
    $ErrorActionPreference = 'Continue'
    $out = & $python $subject --log $log --since 2026-10-20 @Extra 2>&1 | Out-String
    return [pscustomobject]@{ Exit = $LASTEXITCODE; Out = $out }
}

try {
    $r = Invoke-Subject @('--json', '--github-dir', $gh)
    $j = $null
    try { $j = $r.Out | ConvertFrom-Json } catch {}
    Add-Result 'R1_a_json_report_is_produced' ($r.Exit -eq 0 -and $null -ne $j) "exit=$($r.Exit) out=$($r.Out.Substring(0, [Math]::Min(300, $r.Out.Length)))"
    if ($j) {
        $g = $j.gates
        Add-Result 'C1_skipped_and_not_run_wordings_count_as_not_run' `
            ($g.'implementer-stop.ps1'.not_run -eq 4 -and $g.'test-writer-stop.ps1'.not_run -eq 3) `
            "implementer=$($g.'implementer-stop.ps1' | ConvertTo-Json -Compress) test-writer=$($g.'test-writer-stop.ps1' | ConvertTo-Json -Compress)"
        Add-Result 'C2_pass_and_block_are_told_apart' ($g.'refactorer-stop.ps1'.pass -eq 3 -and $g.'refactorer-stop.ps1'.block -eq 1) "$($g.'refactorer-stop.ps1' | ConvertTo-Json -Compress)"
        Add-Result 'C3_the_loop_guard_is_not_a_skip' ($g.'documenter-stop.ps1'.guard -eq 3 -and -not ($g.'documenter-stop.ps1'.PSObject.Properties.Name -contains 'not_run')) "$($g.'documenter-stop.ps1' | ConvertTo-Json -Compress)"
        Add-Result 'C4_permission_decisions_silence_and_timeouts_are_counted' `
            ($g.'block-dangerous.ps1'.deny -eq 1 -and $g.'block-dangerous.ps1'.ask -eq 1 -and $g.'block-dangerous.ps1'.silent -eq 1 -and $g.'block-dangerous.ps1'.timeout -eq 1) `
            "$($g.'block-dangerous.ps1' | ConvertTo-Json -Compress)"
        Add-Result 'C5_a_quoted_running_line_is_not_a_run' (-not ($g.PSObject.Properties.Name -contains 'ghost-stop.ps1')) 'ghost-stop.ps1 counted'
        Add-Result 'C6_lines_before_since_are_ignored' ($g.'test-writer-stop.ps1'.runs -eq 3) "runs=$($g.'test-writer-stop.ps1'.runs)"

        $kinds = @($j.findings | ForEach-Object { "$($_.kind):$($_.script)" })
        Add-Result 'F1_the_473_gates_are_flagged_not_run' `
            ($kinds -contains 'not-run:implementer-stop.ps1' -and $kinds -contains 'not-run:test-writer-stop.ps1') ($kinds -join ', ')
        Add-Result 'F2_a_gate_that_ran_is_not_flagged' (-not ($kinds | Where-Object { $_ -like '*:refactorer-stop*' -or $_ -like 'not-run:documenter-stop*' })) ($kinds -join ', ')
        Add-Result 'F3_a_declared_hook_that_never_ran_is_named_once_per_twin' `
            (@($kinds | Where-Object { $_ -eq 'never-ran:researcher-pretooluse' }).Count -eq 1) ($kinds -join ', ')
        Add-Result 'F4_a_twin_that_ran_in_one_dialect_and_sessionstart_are_not_flagged' `
            (-not ($kinds | Where-Object { $_ -like 'never-ran:block-dangerous*' -or $_ -like 'never-ran:session-context*' -or $_ -like '*not-a-declaration*' })) ($kinds -join ', ')
        # #477: every top-level field declares its kind, and an inferred finding names its rule.
        $top = @($j.PSObject.Properties.Name)
        $declaredKinds = if ($j.PSObject.Properties['kinds']) { $j.kinds } else { [pscustomobject]@{} }
        $kindOf = @{}
        $declaredKinds.PSObject.Properties | ForEach-Object { $kindOf[$_.Name] = $_.Value }
        $missing = @($top | Where-Object { -not $kindOf.ContainsKey($_) })
        $bad = @($kindOf.Values | Where-Object { @('measured', 'inferred', 'lower_bound', 'meta') -notcontains $_ })
        Add-Result 'F5_every_top_level_field_declares_a_kind' `
            ($missing.Count -eq 0 -and $bad.Count -eq 0 -and $kindOf['gates'] -eq 'measured' -and $kindOf['findings'] -eq 'inferred') `
            "missing=$($missing -join ',') kinds=$($declaredKinds | ConvertTo-Json -Compress)"
        Add-Result 'F6_every_finding_is_inferred_and_names_its_rule' `
            (@($j.findings).Count -ge 3 -and @($j.findings | Where-Object { $_.basis -ne 'inferred' -or -not $_.PSObject.Properties['rule'] -or -not $_.rule }).Count -eq 0) `
            "$($j.findings | ConvertTo-Json -Compress)"
    }

    $r = Invoke-Subject @()
    Add-Result 'T1_the_text_report_names_the_finding' ($r.Out -match 'NOT-RUN\s+test-writer-stop\.ps1: reported NOT RUN/skipped in 3 of 3 runs') "out=$($r.Out)"

    $ErrorActionPreference = 'Continue'
    & $python $subject --log (Join-Path $fixtureDir 'absent.log') 2>&1 | Out-Null
    Add-Result 'E1_no_log_is_exit_2_not_a_clean_report' ($LASTEXITCODE -eq 2) "exit=$LASTEXITCODE"
} finally {
    Remove-Item $fixtureDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output '===== gate health tests (issue #475) ====='
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
