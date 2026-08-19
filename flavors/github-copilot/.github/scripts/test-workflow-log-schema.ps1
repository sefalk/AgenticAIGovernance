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
