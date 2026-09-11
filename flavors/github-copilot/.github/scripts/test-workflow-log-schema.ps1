# Regression tests for the workflow log schema checker (check-workflow-log.py).
#
# Each case is a synthetic log built to break exactly one rule, plus the cases
# that matter more: the conforming log that must stay silent, and the derived
# counters, which must agree with analyze-retry-economy.py or the framework
# would hold two contradictory definitions of a retry.
# Run from anywhere:
#   pwsh .github/scripts/test-workflow-log-schema.ps1
$ErrorActionPreference = 'Continue'

$scriptDir  = Split-Path -Parent $PSCommandPath
$repoRootAF = (Resolve-Path (Join-Path $scriptDir '..' | Join-Path -ChildPath '..')).Path
$checker    = (Resolve-Path (Join-Path $scriptDir '..' | Join-Path -ChildPath 'hooks/scripts/check-workflow-log.py')).Path

function Resolve-Python {
    $candidates = @(
        (Join-Path $repoRootAF '.venv/Scripts/python.exe'),
        (Join-Path $repoRootAF '.venv/bin/python')
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return @($c) } }
    foreach ($name in @('python3', 'python')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) {
            $v = & $cmd.Source --version 2>&1
            if ($LASTEXITCODE -eq 0 -and $v -match 'Python 3') { return @($cmd.Source) }
        }
    }
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) { return @($py.Source, '-3') }
    return $null
}

$python = Resolve-Python
if (-not $python) {
    Write-Host 'SKIP: no Python 3 interpreter found; cannot run workflow log schema tests.'
    exit 0
}

# A log that satisfies every rule. Every negative case below is this text with
# exactly one thing changed.
$conforming = @'
workflow_id: "clean"
trigger: "do the thing"
status: "COMPLETED"
git_branch: "agent/clean"

steps:
  - step: 1
    agent: "planner"
    action: "planned"
    verdict: "APPROVED"
  - step: 2
    agent: "test-writer"
    action: "wrote tests"
    verdict: "null"
  - step: 3
    agent: "test-critic"
    action: "reviewed"
    verdict: "APPROVED"

summary:
  total_steps: 3
  retries: 0
  escalations: 0
'@

$files = @()
function New-Log([string]$text) {
    $path = Join-Path ([IO.Path]::GetTempPath()) ("wls-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".yaml")
    [IO.File]::WriteAllText($path, $text)
    $script:files += $path
    return $path
}

function Invoke-Checker([string]$text, [string[]]$extra = @()) {
    $path = New-Log $text
    $out = & $python $checker --log $path @extra 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Output = $out; Path = $path }
}

$results = [ordered]@{}
try {
    # A: the conforming log is silent and clean. Everything else is measured
    #    against this, so if it ever fails the suite proves nothing.
    $r = Invoke-Checker $conforming
    $results['A_conforming_exit0']   = $r.Code -eq 0
    $results['A_conforming_silent']  = $r.Output.Trim() -eq ''

    # B: status outside the schema's set is named with its line.
    $r = Invoke-Checker ($conforming -replace 'status: "COMPLETED"', 'status: "IN_PROGRESS"')
    $results['B_status_exit1']  = $r.Code -eq 1
    $results['B_status_named']  = $r.Output -match "line 3: status 'IN_PROGRESS'"

    # C: a whole sentence where a status belongs. This is real -- one log in the
    #    corpus writes a paragraph into `status:`.
    $r = Invoke-Checker ($conforming -replace 'status: "COMPLETED"', 'status: "IN_PROGRESS (phase 1 done, phase 2 pending)"')
    $results['C_status_prose_exit1'] = $r.Code -eq 1

    # D: a verdict outside the MANIFEST closed set.
    $r = Invoke-Checker ($conforming -replace 'verdict: "APPROVED"\r?\n  - step: 2', "verdict: `"PASS`"`r`n  - step: 2")
    $results['D_verdict_exit1'] = $r.Code -eq 1
    $results['D_verdict_named'] = $r.Output -match "verdict 'PASS'"

    # E: `null` is an absent verdict, not an invented one.
    $results['E_null_verdict_ok'] = (Invoke-Checker $conforming).Code -eq 0

    # F: a verdict with a note attached is the verdict, not a new word.
    $r = Invoke-Checker ($conforming -replace 'verdict: "APPROVED"', 'verdict: "APPROVED (Attempt 2)"')
    $results['F_verdict_with_note_ok'] = $r.Code -eq 0

    # G: but a hyphenated variant IS a new word, and the analyser calls it drift.
    $r = Invoke-Checker ($conforming -replace 'verdict: "APPROVED"', 'verdict: "APPROVED-WITH-ISSUES"')
    $results['G_verdict_variant_exit1'] = $r.Code -eq 1

    # H: a log with no steps records nothing.
    $r = Invoke-Checker ($conforming -replace '(?ms)^steps:.*?^summary:', "summary:")
    $results['H_no_steps_exit1'] = $r.Code -eq 1

    # I: a missing file cannot be checked -- that is not a pass.
    $out = & $python $checker --log (Join-Path ([IO.Path]::GetTempPath()) 'wls-nonexistent.yaml') 2>&1 | Out-String
    $results['I_missing_file_exit2'] = $LASTEXITCODE -eq 2

    # J: a block scalar body is not scanned. Without this the checker invents
    #    violations out of prose that merely mentions a verdict.
    $trap = $conforming -replace '(?m)^    action: "reviewed"\r?$', @"
    action: |
      the critic wrote:
      verdict: "PROCEEDED"
      status: "WHATEVER"
"@
    # This case passes trivially if the substitution silently missed, so prove
    # the fixture was actually built before trusting the result.
    $results['J_trap_actually_built'] = ($trap -ne $conforming) -and ($trap -match 'PROCEEDED')
    $results['J_block_scalar_ignored'] = (Invoke-Checker $trap).Code -eq 0

    # J2: and the same word outside a block scalar IS a violation -- otherwise
    #     J would only prove the checker ignores everything.
    $bare = $conforming -replace 'verdict: "APPROVED"\r?\n  - step: 2', "verdict: `"PROCEEDED`"`r`n  - step: 2"
    $results['J2_bare_verdict_exit1'] = (Invoke-Checker $bare).Code -eq 1

    # K: counters are derived, and derivation alone is not a violation.
    $lying = $conforming -replace 'retries: 0', 'retries: 7'
    $r = Invoke-Checker $lying @('--fix-counters')
    $results['K_counter_fixed_exit0'] = $r.Code -eq 0
    $results['K_counter_reported']    = $r.Output -match 'summary.retries: 7 -> 0'
    $results['K_counter_written']     = ([IO.File]::ReadAllText($r.Path)) -match '(?m)^  retries: 0\s*$'

    # L: a retry is the same agent twice -- the definition analyze-retry-economy.py
    #    uses. If these two ever disagree the framework has two truths.
    $twice = $conforming -replace '(?m)^summary:', @"
  - step: 4
    agent: "test-writer"
    action: "rewrote tests"
    verdict: "APPROVED"

summary:
"@
    $r = Invoke-Checker $twice @('--fix-counters')
    $results['L_retry_counted'] = $r.Output -match 'summary.retries: 0 -> 1'

    # M: an ESCALATE verdict is an escalation.
    $esc = $twice -replace 'verdict: "APPROVED"\r?\n\r?\nsummary:', "verdict: `"ESCALATE`"`r`n`r`nsummary:"
    $r = Invoke-Checker $esc @('--fix-counters')
    $results['M_escalation_counted'] = $r.Output -match 'summary.escalations: 0 -> 1'

    # N: so is a recorded escalation block with no ESCALATE verdict anywhere --
    #    a deferral to a human reads as prose. The analyser counts it too.
    $block = $conforming + @"

escalation:
  trigger: "needs a Databricks run"
  resolution: "documented in the plan"
"@
    $r = Invoke-Checker $block @('--fix-counters')
    $results['N_escalation_block_counted'] = $r.Output -match 'summary.escalations: 0 -> 1'

    # O: without --fix-counters nothing is written. A checker that edits when
    #    only asked to look is not a checker.
    $r = Invoke-Checker $lying
    $results['O_readonly_by_default'] = ([IO.File]::ReadAllText($r.Path)) -match '(?m)^  retries: 7\s*$'

    # P: a correct counter is not rewritten and not reported.
    $r = Invoke-Checker $conforming @('--fix-counters')
    $results['P_correct_counter_silent'] = $r.Output.Trim() -eq ''

    # Q: the human override stands the gate down without hiding what it found.
    $env:ALLOW_WORKFLOW_LOG_SCHEMA = '1'
    $r = Invoke-Checker ($conforming -replace 'status: "COMPLETED"', 'status: "DRAFT"')
    Remove-Item Env:\ALLOW_WORKFLOW_LOG_SCHEMA -ErrorAction SilentlyContinue
    $results['Q_override_exit0']       = $r.Code -eq 0
    $results['Q_override_still_names'] = $r.Output -match "status 'DRAFT'"

    # R: the override is off by default -- otherwise Q would prove nothing.
    $r = Invoke-Checker ($conforming -replace 'status: "COMPLETED"', 'status: "DRAFT"')
    $results['R_override_off_by_default'] = $r.Code -eq 1

    # S: `escalation: null` is how a log states that nothing was escalated. It
    #    must not be counted as one. Seven of the eight escalation sections in
    #    the corpus are exactly this, and all seven were being counted.
    #    The trailing blank line is not decoration -- it is what made the
    #    section two lines long, and the old rule counted lines.
    $denied = $conforming + "`r`n`r`nescalation: null`r`n`r`n"
    $r = Invoke-Checker $denied @('--fix-counters')
    $results['S_null_block_not_counted'] = $r.Output -notmatch 'summary.escalations'
    $results['S_null_block_stays_zero']  = ([IO.File]::ReadAllText($r.Path)) -match '(?m)^  escalations: 0\s*$'

    # T: a header with nothing under it is the same denial in another spelling.
    $empty = $conforming + "`r`n`r`nescalation:`r`n`r`n"
    $r = Invoke-Checker $empty @('--fix-counters')
    $results['T_empty_block_not_counted'] = $r.Output -notmatch 'summary.escalations'

    # U: a Stop hook appends comments below the section. A comment is not an
    #    escalation -- one corpus log is misread on this alone.
    $commented = $conforming + "`r`n`r`nescalation: null`r`n`r`n# Agent invocation counts appended by Stop hook`r`n"
    $r = Invoke-Checker $commented @('--fix-counters')
    $results['U_comment_not_content'] = $r.Output -notmatch 'summary.escalations'

    # V: the watchdog. A stated escalation with no ESCALATE verdict and no
    #    populated block rests on nothing in the file, which is the shape a
    #    fabricated counter takes. Audit mode, so nothing repairs it first.
    $bare = ($conforming -replace 'escalations: 0', 'escalations: 1') + "`r`n`r`nescalation: null`r`n`r`n"
    $r = Invoke-Checker $bare
    $results['V_watchdog_exit1'] = $r.Code -eq 1
    $results['V_watchdog_names_line'] = $r.Output -match 'summary\.escalations is 1'

    # W: it stays silent when a verdict backs the number -- otherwise V would
    #    only prove the rule fires on everything.
    $withVerdict = ($conforming -replace 'escalations: 0', 'escalations: 1') `
        -replace 'verdict: "APPROVED"\r?\n  - step: 2', "verdict: `"ESCALATE`"`r`n  - step: 2"
    $results['W_watchdog_silent_on_verdict'] = (Invoke-Checker $withVerdict).Code -eq 0

    # X: and silent when a populated block backs it.
    $withBlock = ($conforming -replace 'escalations: 0', 'escalations: 1') + @"

escalation:
  trigger: "needs a Databricks run"
  resolution: "documented in the plan"
"@
    $results['X_watchdog_silent_on_block'] = (Invoke-Checker $withBlock).Code -eq 0

    # Y: repair runs before judgement. The same log the watchdog rejects in
    #    audit mode is repaired and passes when the fix is asked for -- a gate
    #    must not block on a contradiction its own run has removed.
    $r = Invoke-Checker $bare @('--fix-counters')
    $results['Y_repair_before_check'] = ($r.Code -eq 0) -and ($r.Output -match 'summary.escalations: 1 -> 0')

    # Z: the fixtures above must actually reproduce the corpus shape. A section
    #    that is one line long never triggered the old rule either, so a case
    #    built without the blank line would pass against the bug it targets.
    $results['Z_fixture_has_blank_line'] = $denied -match "escalation: null`r`n`r`n"

    # AA-AF: `started:` and `completed:` are written by two producers, so they
    #    can drift into different representations while each stays valid ISO
    #    8601 -- the #240 shape, where subtracting them gives -66 minutes. The
    #    rule compares the two rather than demanding `Z`, so a consistently
    #    stamped historical log keeps passing.
    function New-Stamped([string]$started, [string]$completed) {
        $stamps = "started: `"$started`""
        if ($completed) { $stamps += "`r`ncompleted: `"$completed`"" }
        return ($conforming -replace 'git_branch: "agent/clean"', ('git_branch: "agent/clean"' + "`r`n" + $stamps))
    }

    $mixed = New-Stamped '2026-08-27T09:57:10+02:00' '2026-08-27T08:51:31Z'
    $r = Invoke-Checker $mixed
    $results['AA_mixed_rejected']    = $r.Code -eq 1
    $results['AA_names_both_stamps'] = ($r.Output -match '\+02:00') -and ($r.Output -match 'completed')

    $r = Invoke-Checker (New-Stamped '2026-08-27T07:57:10Z' '2026-08-27T08:51:31Z')
    $results['AB_both_utc_ok'] = $r.Code -eq 0

    # A historical log stamped consistently in one offset is wrong by today's
    # convention but not broken for its readers. It is not rewritten, so it
    # must not be rejected either.
    $r = Invoke-Checker (New-Stamped '2026-08-27T09:57:10+02:00' '2026-08-27T10:51:31+02:00')
    $results['AC_same_offset_ok'] = $r.Code -eq 0

    # `null` is absence, not a representation. Four corpus logs end this way.
    $r = Invoke-Checker (New-Stamped '2026-08-27T07:57:10Z' 'null')
    $results['AD_absent_completed_ok'] = $r.Code -eq 0

    $r = Invoke-Checker (New-Stamped '2026-08-27T09:57:10+02:00' '')
    $results['AE_started_alone_ok'] = $r.Code -eq 0

    # Same class, different reference: a workflow spanning a DST change reads
    # as consistent to a rule that only looks for `Z`.
    $r = Invoke-Checker (New-Stamped '2026-08-27T09:57:10+02:00' '2026-08-27T09:51:31+01:00')
    $results['AF_differing_offsets_rejected'] = $r.Code -eq 1

    # The fixture must carry what the cases claim, or AB-AE pass vacuously.
    $results['AG_fixture_carries_stamps'] = ($mixed -match '(?m)^started: ') -and ($mixed -match '(?m)^completed: ')
}
finally {
    foreach ($f in $files) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    Remove-Item Env:\ALLOW_WORKFLOW_LOG_SCHEMA -ErrorAction SilentlyContinue
}

Write-Host '===== workflow log schema tests ====='
$allPass = $true
foreach ($k in $results.Keys) {
    if (-not $results[$k]) { $allPass = $false }
    Write-Host ("  {0,-30} {1}" -f $k, $(if ($results[$k]) { 'PASS' } else { 'FAIL' }))
}
Write-Host '====================================='
if ($allPass) { Write-Host 'RESULT: ALL GREEN'; exit 0 }
else { Write-Host 'RESULT: FAILURES PRESENT'; exit 1 }
