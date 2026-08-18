# Regression tests for the retry economy analyser (analyze-retry-economy.py).
#
# Portable + deterministic: builds synthetic workflow logs in throwaway
# directories (no git, no real corpus) and asserts the exit-code contract
# (0 clean, 1 drift reported, 2 cannot measure) plus the numbers the report
# claims. The case that matters most is the one where there is nothing to
# measure: it must exit 2, never print a confident zero.
# Run from anywhere:
#   pwsh .github/scripts/test-retry-economy.ps1
$ErrorActionPreference = 'Continue'

$scriptDir  = Split-Path -Parent $PSCommandPath
$repoRootAF = (Resolve-Path (Join-Path $scriptDir '..' | Join-Path -ChildPath '..')).Path
$analyser   = (Resolve-Path (Join-Path $scriptDir 'analyze-retry-economy.py')).Path

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
    Write-Host 'SKIP: no Python 3 interpreter found; cannot run retry economy tests.'
    exit 0
}
& $python -c "import yaml" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host 'SKIP: PyYAML not installed; the analyser cannot read workflow logs.'
    exit 0
}

# A workflow with no rework: every agent runs once, every verdict canonical.
$clean = @'
workflow_id: "clean"
status: "COMPLETED"
summary:
  retries: 0
  escalations: 0
steps:
  - step: 1
    agent: "planner"
    verdict: "APPROVED"
  - step: 2
    agent: "test-writer"
    verdict: "null"
  - step: 3
    agent: "test-critic"
    verdict: "APPROVED"
'@

# The test-writer is sent back once by the test-critic.
$rejected = @'
workflow_id: "rejected"
status: "COMPLETED"
summary:
  retries: 1
  escalations: 0
steps:
  - step: 1
    agent: "test-writer"
    verdict: "null"
  - step: 2
    agent: "test-critic"
    verdict: "REJECTED"
  - step: 3
    agent: "test-writer"
    verdict: "null"
  - step: 4
    agent: "test-critic"
    verdict: "APPROVED"
'@

function New-LogDir {
    $dir = Join-Path ([IO.Path]::GetTempPath()) ("rte-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $script:dirs += $dir
    return $dir
}

function Add-Log([string]$dir, [string]$name, [string]$text) {
    [IO.File]::WriteAllText((Join-Path $dir "$name.yaml"), $text)
}

function Invoke-Analyser([string]$dir, [string[]]$extra = @()) {
    $out = & $python $analyser --logs-dir $dir @extra 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Output = $out }
}

$results = [ordered]@{}
$dirs = @()
try {
    # A: a corpus with nothing wrong exits clean and says so.
    $d = New-LogDir; Add-Log $d 'clean' $clean
    $r = Invoke-Analyser $d
    $results['A_clean_corpus_exit0'] = $r.Code -eq 0
    $results['A_clean_says_no_drift'] = $r.Output -match 'No drift'

    # B: the heuristic is stated in the output, not buried in the source.
    $results['B_heuristic_is_printed'] = $r.Output -match 'Heuristic -- read this before the numbers'
    $results['B_missing_cause_declared'] = $r.Output -match 'missing, not zero'

    # C: a retry is attributed to the agent that repeated, with its cause.
    $d = New-LogDir; Add-Log $d 'rejected' $rejected
    $r = Invoke-Analyser $d
    $results['C_retry_counted']  = $r.Output -match 'test-writer\s+2\s+1\s'
    $results['C_cause_named']    = $r.Output -match 'critic-rejected=1'
    $results['C_rejection_issued'] = $r.Output -match 'test-critic\s+1 REJECTED'

    # D: an empty directory is not a framework with zero retries.
    $results['D_empty_dir_exit2'] = (Invoke-Analyser (New-LogDir)).Code -eq 2

    # E: a directory that does not exist is a usage error, not a zero.
    $results['E_missing_dir_exit2'] =
        (Invoke-Analyser (Join-Path ([IO.Path]::GetTempPath()) 'rte-nonexistent-xyz')).Code -eq 2

    # F: an unreadable log is named and excluded -- never counted as no retries.
    $d = New-LogDir; Add-Log $d 'clean' $clean; Add-Log $d 'broken' "steps:`n  - [unclosed`n"
    $r = Invoke-Analyser $d
    $results['F_broken_log_exit1']  = $r.Code -eq 1
    $results['F_broken_log_named']  = $r.Output -match 'broken\.yaml'
    $results['F_readable_still_counted'] = $r.Output -match '1 workflow log\(s\) read, 1 excluded'

    # G: if nothing at all parses, that is a failure to measure, not a result.
    $d = New-LogDir; Add-Log $d 'broken' "steps:`n  - [unclosed`n"
    $results['G_all_broken_exit2'] = (Invoke-Analyser $d).Code -eq 2

    # H: a summary that contradicts its own steps is reported, not trusted.
    $d = New-LogDir; Add-Log $d 'lying' ($rejected -replace 'retries: 1', 'retries: 0')
    $r = Invoke-Analyser $d
    $results['H_summary_mismatch_exit1'] = $r.Code -eq 1
    $results['H_mismatch_shows_both']    = $r.Output -match 'contradicts its own steps'

    # I: a verdict outside the MANIFEST closed set is drift, not vocabulary.
    $d = New-LogDir; Add-Log $d 'odd' ($clean -replace 'verdict: "APPROVED"', 'verdict: "PASSED"')
    $r = Invoke-Analyser $d
    $results['I_unknown_verdict_exit1'] = $r.Code -eq 1
    $results['I_unknown_verdict_named'] = $r.Output -match "'PASSED'"

    # J: `null` is an absent verdict, not an unknown one.
    $d = New-LogDir; Add-Log $d 'clean' $clean
    $results['J_null_verdict_not_drift'] = (Invoke-Analyser $d).Output -notmatch "'null'"

    # K: an escalation records which retry number it happened at.
    $escalated = $rejected -replace '(?m)^    verdict: "APPROVED"\r?$', '    verdict: "ESCALATE"'
    $d = New-LogDir; Add-Log $d 'escalated' $escalated
    $r = Invoke-Analyser $d
    $results['K_escalation_counted'] = $r.Output -match 'after retry number'

    # L: the JSON form is machine-readable and carries the same drift signal.
    $d = New-LogDir; Add-Log $d 'rejected' $rejected
    $r = Invoke-Analyser $d @('--json')
    $ok = $false
    try { $ok = ($r.Output | ConvertFrom-Json).retries.'test-writer' -eq 1 } catch { $ok = $false }
    $results['L_json_parses_and_counts'] = $ok
}
finally {
    foreach ($d in $dirs) { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host '===== retry economy analyser tests ====='
$allPass = $true
foreach ($k in $results.Keys) {
    if (-not $results[$k]) { $allPass = $false }
    Write-Host ("  {0,-32} {1}" -f $k, $(if ($results[$k]) { 'PASS' } else { 'FAIL' }))
}
Write-Host '========================================'
if ($allPass) { Write-Host 'RESULT: ALL GREEN'; exit 0 }
else { Write-Host 'RESULT: FAILURES PRESENT'; exit 1 }
