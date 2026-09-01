# Regression tests for the subagent invocation recorder
# (.github/hooks/scripts/collect-agent-invocations.py, issue #173).
#
# Portable + deterministic: drives the tool against synthetic session
# directories in throwaway temp dirs. Only filenames matter to the tool, so the
# fixture files are empty -- a real subagent log is never copied, not even as
# test data, because it contains the verbatim user request.
# Run from anywhere:
#   pwsh .github/scripts/test-agent-invocations.ps1
# Exits non-zero if any scenario fails (CI-friendly).
$ErrorActionPreference = 'Continue'

$scriptDir  = Split-Path -Parent $PSCommandPath
$repoRootAF = (Resolve-Path (Join-Path $scriptDir '..' | Join-Path -ChildPath '..')).Path
$tool       = Join-Path $repoRootAF '.github/hooks/scripts/collect-agent-invocations.py'

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
    Write-Host 'SKIP: no Python 3 interpreter found; cannot run agent invocation tests.'
    exit 0
}

# --- fixture builders -------------------------------------------------------
# Naming verified against a real workspace on 2026-08-21:
#   runSubagent-implementer-toolu_012fNUwUXMkQMZAeRxMrp3mv.jsonl
#   runSubagent-ado-pr-manager-toolu_011DEuS1yqmhJkPQa1qmtY3U.jsonl

$SID = '053fc66d-c44e-4fa8-94c4-ca2f2feddede'
$fixtures = @()

function New-SessionDir([string[]]$SubagentFiles, [switch]$NoMain) {
    $base = Join-Path ([IO.Path]::GetTempPath()) ("agentinv-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $dir  = Join-Path $base $SID
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    if (-not $NoMain) { [IO.File]::WriteAllText((Join-Path $dir 'main.jsonl'), "{}`n") }
    foreach ($f in $SubagentFiles) { [IO.File]::WriteAllText((Join-Path $dir $f), "{}`n") }
    $script:fixtures += $dir
    return $dir
}

function New-LogFile([string]$Body) {
    $path = Join-Path ([IO.Path]::GetTempPath()) ("agentinv-log-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.yaml')
    [IO.File]::WriteAllText($path, $Body)
    $script:fixtures += $path
    return $path
}

function Invoke-Tool([string[]]$ToolArgs) {
    $out = & $python $tool @ToolArgs 2>&1 | Out-String
    return @{ Code = $LASTEXITCODE; Output = $out }
}

$results = [ordered]@{}

try {
    # --- A: invocations are counted per agent -------------------------------
    $dir = New-SessionDir @(
        'runSubagent-implementer-toolu_012fNUwUXMkQMZAeRxMrp3mv.jsonl',
        'runSubagent-implementer-toolu_01AEqsY1KNTxjNvb3mzuKyfu.jsonl',
        'runSubagent-test-writer-toolu_015zsJhRuussYrVhJoTQrJBt.jsonl'
    )
    $r = Invoke-Tool @('--session-dir', $dir)
    $results['A_exit_zero']            = ($r.Code -eq 0)
    $results['A_block_key']            = ($r.Output -match '(?m)^agent_invocations:\s*$')
    $results['A_repeated_agent_summed'] = ($r.Output -match '(?m)^\s*implementer:\s*2\s*$')
    $results['A_single_agent_counted'] = ($r.Output -match '(?m)^\s*test-writer:\s*1\s*$')
    # The count covers one chat session; a block that did not say so would be
    # read as a complete record of the workflow.
    $results['A_states_lower_bound']   = ($r.Output -match 'lower bound')

    # --- B: a hyphenated agent name survives the split ----------------------
    # The name itself contains hyphens, so only the LAST one separates the
    # tool-call id. Splitting on the first would report an agent named 'ado'.
    $dir = New-SessionDir @('runSubagent-ado-pr-manager-toolu_011DEuS1yqmhJkPQa1qmtY3U.jsonl')
    $r = Invoke-Tool @('--session-dir', $dir)
    $results['B_hyphenated_name_intact'] = ($r.Output -match '(?m)^\s*ado-pr-manager:\s*1\s*$')
    $results['B_no_truncated_name']      = ($r.Output -notmatch '(?m)^\s*ado:\s')

    # --- C: the #173 case -- a step claiming an agent that never ran --------
    $dir = New-SessionDir @(
        'runSubagent-implementer-toolu_aaa.jsonl',
        'runSubagent-code-critic-toolu_bbb.jsonl'
    )
    $log = New-LogFile @"
workflow_id: "demo"
steps:
  - step: 1
    agent: implementer
    action: "wrote the thing"
  - step: 2
    agent: code-critic
    verdict: "APPROVED"
  - step: 3
    agent: arbiter
    action: "resolved the disagreement"
    verdict: "RESOLVED"
summary:
  total_steps: 3
"@
    $r = Invoke-Tool @('--session-dir', $dir, '--log', $log)
    $results['C_fabricated_agent_named'] = ($r.Output -match '(?m)^\s*-\s*arbiter\s*$')
    $results['C_section_present']        = ($r.Output -match 'claimed_without_invocation:')
    # A step whose agent DID run must not be listed -- otherwise the section is
    # noise and gets ignored, which is worse than not having it.
    $results['C_real_agent_not_listed']  = ($r.Output -notmatch '(?m)^\s*-\s*implementer\s*$')
    $results['C_critic_not_listed']      = ($r.Output -notmatch '(?m)^\s*-\s*code-critic\s*$')

    # --- D: no contradiction, no section ------------------------------------
    $log = New-LogFile @"
workflow_id: "demo"
steps:
  - step: 1
    agent: implementer
    action: "wrote the thing"
summary:
  total_steps: 1
"@
    $r = Invoke-Tool @('--session-dir', $dir, '--log', $log)
    $results['D_no_false_accusation'] = ($r.Output -notmatch 'claimed_without_invocation')
    $results['D_still_reports']       = ($r.Output -match '(?m)^\s*implementer:\s*1\s*$')

    # --- E: prose inside a block scalar is not a step -----------------------
    # `description: |` may legitimately contain a line reading `agent: arbiter`.
    # Scanning it would invent a finding, which is the same failure in reverse.
    $log = New-LogFile @"
workflow_id: "demo"
steps:
  - step: 1
    agent: implementer
    action: |
      Considered escalating.
      agent: arbiter
summary:
  total_steps: 1
"@
    $r = Invoke-Tool @('--session-dir', $dir, '--log', $log)
    $results['E_block_scalar_ignored'] = ($r.Output -notmatch 'claimed_without_invocation')

    # --- F: an indented `agent:` outside steps is not a step ----------------
    # The escalation block legitimately names the agent that resolved things.
    # Without the steps boundary it reads as a step claiming an arbiter that
    # never ran -- the false accusation is the same defect in reverse.
    #
    # A top-level `agent:` is NOT tested here. Mutation runs showed it staying
    # green under every plausible break, because the top-level branch assigns
    # `in_steps = (key == "steps")` and so switches itself off. A case no
    # mutation can turn red measures nothing.
    $log = New-LogFile @"
workflow_id: "demo"
steps:
  - step: 1
    agent: implementer
escalation:
  agent: arbiter
  resolution: "human decided"
"@
    $r = Invoke-Tool @('--session-dir', $dir, '--log', $log)
    $results['F_other_section_ignored'] = ($r.Output -notmatch 'claimed_without_invocation')

    # --- G: nothing measurable writes nothing -------------------------------
    # An absent session dir and a session with no subagent look identical from
    # here, and neither is worth a block asserting zero (issue #59).
    $dir = New-SessionDir @()
    $r = Invoke-Tool @('--session-dir', $dir)
    $results['G_no_subagent_exit_one'] = ($r.Code -eq 1)
    $results['G_no_subagent_silent']   = ($r.Output.Trim() -eq '')

    $r = Invoke-Tool @('--session-dir', (Join-Path ([IO.Path]::GetTempPath()) 'agentinv-does-not-exist'))
    $results['G_missing_dir_exit_one'] = ($r.Code -eq 1)
    $results['G_missing_dir_silent']   = ($r.Output.Trim() -eq '')

    # --- H: an unreadable log costs the measurement nothing -----------------
    # The invocation counts are the measured part; a log that cannot be parsed
    # must not suppress them.
    $dir = New-SessionDir @('runSubagent-implementer-toolu_aaa.jsonl')
    $r = Invoke-Tool @('--session-dir', $dir, '--log', (Join-Path ([IO.Path]::GetTempPath()) 'agentinv-no-such-log.yaml'))
    $results['H_missing_log_exit_zero'] = ($r.Code -eq 0)
    $results['H_missing_log_reports']   = ($r.Output -match '(?m)^\s*implementer:\s*1\s*$')

    # --- I: the block is a single YAML top-level key ------------------------
    # It is appended to a workflow log; a second top-level key would silently
    # change that file's shape for every reader downstream.
    $topLevel = @($r.Output -split "`r?`n" | Where-Object { $_ -match '^[A-Za-z_]' })
    $results['I_single_top_level_key'] = ($topLevel.Count -eq 1 -and $topLevel[0] -match '^agent_invocations:')
}
finally {
    foreach ($f in $fixtures) {
        if (Test-Path $f -PathType Leaf) { Remove-Item $f -Force -ErrorAction SilentlyContinue; continue }
        $parent = Split-Path -Parent $f
        if ($parent -and (Test-Path $parent)) { Remove-Item $parent -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Write-Host ''
Write-Host '=== Subagent Invocation Recorder ==='
$failed = 0
foreach ($name in $results.Keys) {
    if ($results[$name]) { Write-Host "  PASS: $name" }
    else { Write-Host "  FAIL: $name"; $failed++ }
}
Write-Host ''
Write-Host "  Checks passed: $($results.Count - $failed)"
Write-Host "  Checks failed: $failed"
if ($failed -gt 0) { Write-Host '  RESULT: INVOCATION RECORDER IS BROKEN'; exit 1 }
Write-Host '  RESULT: INVOCATION RECORDER IS WORKING'
exit 0
