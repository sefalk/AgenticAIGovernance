# Regression tests for the workflow cost collector (collect-session-cost.py).
#
# Portable + deterministic: drives the collector against synthetic debug-log
# fixtures in throwaway temp dirs. Fixtures are hand-built JSONL -- a real
# session log is never copied, not even as test data, because it contains the
# verbatim user request.
# Run from anywhere:
#   pwsh .github/scripts/test-session-cost.ps1
# Exits non-zero if any scenario fails (CI-friendly).
$ErrorActionPreference = 'Continue'

$scriptDir  = Split-Path -Parent $PSCommandPath
$repoRootAF = (Resolve-Path (Join-Path $scriptDir '..' | Join-Path -ChildPath '..')).Path
$collector  = Join-Path $scriptDir 'collect-session-cost.py'

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
    Write-Host 'SKIP: no Python 3 interpreter found; cannot run session cost tests.'
    exit 0
}

# --- fixture builders -------------------------------------------------------
# Field names and shapes mirror the real log (verified 2026-08-03, copilot-chat
# 0.59.0): epoch-millisecond `ts`, cost in `copilotUsageNanoAiu`, and
# `inputTokens` already includes `cachedTokens`.

$T0          = 1785760263230
$NANO_CREDIT = 1000000000
$SID         = '053fc66d-c44e-4fa8-94c4-ca2f2feddede'

function New-SessionStart([long]$Ts = $T0) {
    [ordered]@{
        v = 1; ts = $Ts; dur = 0; sid = $SID
        type = 'session_start'; name = 'session_start'; spanId = 's0'; status = 'ok'
        attrs = [ordered]@{ copilotVersion = '0.59.0'; vscodeVersion = '1.131.0' }
    } | ConvertTo-Json -Compress -Depth 6
}

function New-LlmRequest {
    param(
        [string]$Model = 'claude-opus-5',
        [long]$InputTokens = 1000,      # includes CachedTokens, as in the real log
        [long]$CachedTokens = 400,
        [long]$OutputTokens = 50,
        [object]$NanoAiu = 1500000000,  # $null => unbilled request
        [string]$DebugName = 'panel/editAgent',
        [long]$Ts = 0,
        [switch]$OmitTokenFields,
        [string]$SecretText = ''
    )
    if ($Ts -eq 0) { $Ts = $T0 + 1000 }
    $attrs = [ordered]@{ model = $Model; debugName = $DebugName }
    if (-not $OmitTokenFields) {
        $attrs.inputTokens  = $InputTokens
        $attrs.outputTokens = $OutputTokens
        $attrs.cachedTokens = $CachedTokens
    }
    if ($null -ne $NanoAiu) { $attrs.copilotUsageNanoAiu = $NanoAiu }
    if ($SecretText) { $attrs.userRequest = $SecretText; $attrs.inputMessages = $SecretText }
    [ordered]@{
        ts = $Ts; dur = 100; sid = $SID
        type = 'llm_request'; name = "chat:$Model"; spanId = 'r1'; parentSpanId = 's0'; status = 'ok'
        attrs = $attrs
    } | ConvertTo-Json -Compress -Depth 6
}

# Creates a session directory. $Main / $Child are arrays of JSONL lines.
function New-SessionFixture {
    param(
        [string[]]$Main = @(),
        [string[]]$Child = @(),
        [string]$ChildName = 'runSubagent-implementer-toolu_test.jsonl',
        [string[]]$Child2 = @(),
        [string]$ChildName2 = 'runSubagent-implementer-toolu_second.jsonl',
        [switch]$NoMainFile
    )
    $base = Join-Path ([IO.Path]::GetTempPath()) ("sesscost-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $dir  = Join-Path $base $SID
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    if (-not $NoMainFile) {
        [IO.File]::WriteAllText((Join-Path $dir 'main.jsonl'), (($Main -join "`n") + "`n"))
    }
    if ($Child.Count -gt 0) {
        [IO.File]::WriteAllText((Join-Path $dir $ChildName), (($Child -join "`n") + "`n"))
    }
    if ($Child2.Count -gt 0) {
        [IO.File]::WriteAllText((Join-Path $dir $ChildName2), (($Child2 -join "`n") + "`n"))
    }
    return $dir
}

function Invoke-Collector([string[]]$CollectorArgs) {
    $out = & $python $collector @CollectorArgs 2>&1 | Out-String
    return @{ Code = $LASTEXITCODE; Output = $out }
}

$results  = [ordered]@{}
$fixtures = @()

try {
    # --- A: happy path, parent file only ------------------------------------
    # 1500 + 2500 nano-AIU = 4.0 credits; input_uncached = (1000-400)+(2000-900)
    $dir = New-SessionFixture -Main @(
        (New-SessionStart),
        (New-LlmRequest -InputTokens 1000 -CachedTokens 400 -OutputTokens 50  -NanoAiu 1500000000),
        (New-LlmRequest -InputTokens 2000 -CachedTokens 900 -OutputTokens 60  -NanoAiu 2500000000)
    )
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['A_exit_zero']        = ($r.Code -eq 0)
    $results['A_available_true']   = ($r.Output -match '(?m)^\s*available:\s*true\s*$')
    $results['A_coverage_full']    = ($r.Output -match '(?m)^\s*coverage:\s*full\s*$')
    $results['A_requests_counted'] = ($r.Output -match '(?m)^\s*requests:\s*2\s*$')
    $results['A_credits_summed']   = ($r.Output -match '(?m)^\s*credits:\s*4(\.0+)?\s*$')
    # inputTokens includes cachedTokens -- adding them would double-count
    $results['A_input_uncached']   = ($r.Output -match 'input_uncached:\s*1700\b')
    $results['A_cached_summed']    = ($r.Output -match 'cached:\s*1300\b')
    $results['A_output_summed']    = ($r.Output -match 'output:\s*110\b')
    $results['A_session_reported'] = ($r.Output -match [regex]::Escape($SID))
    $results['A_environment']      = ($r.Output -match 'vscode:\s*"?1\.131\.0' -and
                                      $r.Output -match 'copilot_chat:\s*"?0\.59\.0')
    $results['A_schema_version']   = ($r.Output -match '(?m)^\s*schema_version:\s*2\s*$')
    $results['A_collector_named']  = ($r.Output -match 'collector:\s*"?collect-session-cost\.py@')

    # --- B: subagent child file is summed, per model ------------------------
    $dir = New-SessionFixture -Main @(
        (New-SessionStart),
        (New-LlmRequest -Model 'claude-opus-5' -NanoAiu 3000000000)
    ) -Child @(
        (New-LlmRequest -Model 'claude-haiku-4.5' -NanoAiu 1000000000 -DebugName 'tool/runSubagent-implementer')
    )
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['B_child_file_summed']  = ($r.Output -match '(?m)^\s*credits:\s*4(\.0+)?\s*$')
    $results['B_child_requests']     = ($r.Output -match '(?m)^\s*requests:\s*2\s*$')
    $results['B_by_model_parent']    = ($r.Output -match 'claude-opus-5:\s*\{[^}]*credits:\s*3(\.0+)?')
    $results['B_by_model_child']     = ($r.Output -match 'claude-haiku-4\.5:\s*\{[^}]*credits:\s*1(\.0+)?')

    # --- N: cost is attributed to the log it came from (issue #212) ---------
    # Same fixture as B: the total is identical, the split is what is new.
    $results['N_parent_bucket']   = ($r.Output -match 'main:\s+totals:\s*\{[^}]*credits:\s*3(\.0+)?[^}]*\}')
    $results['N_child_bucket']    = ($r.Output -match 'implementer:\s+totals:\s*\{[^}]*credits:\s*1(\.0+)?[^}]*\}')
    # A split that does not add up lets a reader pick the number that suits them.
    # Anchored on `invocations`: a greedy `[^}]*` lands on `unbilled_requests`
    # and silently sums the wrong column.
    $perAgent = [regex]::Matches($r.Output, 'totals:\s*\{\s*invocations:\s*\d+,\s*requests:\s*(\d+)')
    $sumReq   = ($perAgent | ForEach-Object { [int]$_.Groups[1].Value } | Measure-Object -Sum).Sum
    $results['N_reconciles_total'] = ($perAgent.Count -eq 2 -and $sumReq -eq 2 -and
                                      $r.Output -match '(?m)^\s*requests:\s*2\s*$')

    # Agent and model must resolve on a joint key: "the implementer is
    # expensive" and "opus is expensive" are different findings, and only the
    # crossing says which agent to move off which model.
    $results['N_agent_model_crossed'] = (
        $r.Output -match 'main:\s+totals:\s*\{[^}]*\}\s+by_model:\s+claude-opus-5:\s*\{[^}]*credits:\s*3(\.0+)?' -and
        $r.Output -match 'implementer:\s+totals:\s*\{[^}]*\}\s+by_model:\s+claude-haiku-4\.5:\s*\{[^}]*credits:\s*1(\.0+)?')

    # Eleven implementer calls in one session is the case that motivated this:
    # repeated invocations must collapse into one bucket, counted.
    $dir = New-SessionFixture -Main @(
        (New-SessionStart)
    ) -Child @(
        (New-LlmRequest -NanoAiu 1000000000)
    ) -Child2 @(
        (New-LlmRequest -NanoAiu 2000000000)
    )
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['N_invocations_counted'] = ($r.Output -match 'implementer:\s+totals:\s*\{\s*invocations:\s*2\b')
    $results['N_invocations_summed']  = ($r.Output -match 'implementer:\s+totals:\s*\{[^}]*credits:\s*3(\.0+)?[^}]*\}')
    # The parent ran but billed nothing; dropping it would hide that it ran.
    $results['N_idle_parent_kept']    = ($r.Output -match 'main:\s+totals:\s*\{[^}]*requests:\s*0\b')
    # An agent that billed nothing has no model rows -- it must still say so
    # rather than inherit the session's models and imply spend it never had.
    $results['N_idle_parent_no_models'] = ($r.Output -match 'main:\s+totals:\s*\{[^}]*\}\s+by_model:\s*\{\}')

    # An id format without a trailing hyphen must become an odd bucket, never
    # a silent zero -- the filename is the only record that the agent ran.
    $dir = New-SessionFixture -Main @(
        (New-SessionStart)
    ) -Child @(
        (New-LlmRequest -NanoAiu 1000000000)
    ) -ChildName 'runSubagent-unparseable.jsonl'
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['N_unparsed_name_visible'] = ($r.Output -match 'runSubagent-unparseable:\s+totals:\s*\{[^}]*credits:\s*1(\.0+)?')

    # --- C/D/E: the log is a pointer, not evidence --------------------------
    $missing = Join-Path ([IO.Path]::GetTempPath()) ("sesscost-absent-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $r = Invoke-Collector @('--session-dir', $missing)
    $results['C_absent_dir_exit_zero']   = ($r.Code -eq 0)
    $results['C_absent_dir_unavailable'] = ($r.Output -match '(?m)^\s*available:\s*false\s*$' -and
                                            $r.Output -match '(?m)^\s*reason:\s*\S+')

    $dir = New-SessionFixture -NoMainFile
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['D_no_main_file_unavailable'] = ($r.Code -eq 0 -and $r.Output -match '(?m)^\s*available:\s*false\s*$')

    $dir = New-SessionFixture -Main @('', 'not json at all', '{"broken":')
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['E_unparseable_unavailable'] = ($r.Code -eq 0 -and $r.Output -match '(?m)^\s*available:\s*false\s*$')

    # --- F: truncation biases downward while looking complete ---------------
    # The size cap drops the OLDEST entries, i.e. plan and Red phases.
    $dir = New-SessionFixture -Main @(
        (New-LlmRequest -NanoAiu 1500000000),
        (New-LlmRequest -NanoAiu 2500000000)
    )
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['F_truncated_flagged']   = ($r.Output -match '(?m)^\s*coverage:\s*truncated\s*$')
    $results['F_no_total_emitted']    = ($r.Output -match '(?m)^\s*credits:\s*null\s*$')
    # paired with a positive assertion so it cannot pass on empty output
    $results['F_no_numeric_credits']  = ($r.Output -match '(?m)^cost:' -and
                                         $r.Output -notmatch '(?m)^\s*credits:\s*[0-9]')
    # `{}` would read as "no agent consumed anything"; the split is withheld,
    # biased downward by the same size cap that dropped the oldest entries.
    $results['F_by_agent_withheld']   = ($r.Output -match '(?m)^\s*by_agent:\s*null\s*$')

    # --- G: workflow started before this session ----------------------------
    $dir = New-SessionFixture -Main @(
        (New-SessionStart),
        (New-LlmRequest -NanoAiu 1500000000)
    )
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir, '--workflow-start', ($T0 - 60000))
    $results['G_partial_coverage'] = ($r.Output -match '(?m)^\s*coverage:\s*partial\s*$')

    # --- H: absent billing attribute means NOT BILLED, not zero -------------
    $dir = New-SessionFixture -Main @(
        (New-SessionStart),
        (New-LlmRequest -NanoAiu 1500000000),
        (New-LlmRequest -Model 'gpt-4o-mini-2024-07-18' -NanoAiu $null -DebugName 'backgroundTodoAgent')
    )
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['H_unbilled_counted']      = ($r.Output -match '(?m)^\s*unbilled_requests:\s*1\s*$')
    $results['H_unbilled_not_in_total'] = ($r.Output -match '(?m)^\s*requests:\s*1\s*$' -and
                                           $r.Output -match '(?m)^\s*credits:\s*1\.5\s*$')

    # --- I: no text from the log ever reaches the output --------------------
    $secret = 'SUPERSECRET-TOKEN-ghp_abcdef123456'
    $dir = New-SessionFixture -Main @(
        (New-SessionStart),
        (New-LlmRequest -NanoAiu 1500000000 -SecretText $secret)
    )
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['I_no_secret_leak'] = ($r.Output -match '(?m)^\s*available:\s*true\s*$' -and
                                    $r.Output -notmatch 'SUPERSECRET')

    # --- J: emitted keys are an explicit allowlist --------------------------
    $allowed = @(
        'cost', 'schema_version', 'collector', 'available', 'reason', 'coverage',
        'sessions', 'requests', 'unbilled_requests', 'tokens', 'input_uncached',
        'cached', 'output', 'credits', 'by_model', 'by_agent', 'invocations', 'totals',
        'main', 'environment', 'vscode', 'copilot_chat', 'claude-opus-5',
        'claude-haiku-4.5'
    )
    $keys = [regex]::Matches($r.Output, '(?m)(?:^\s*|[{,]\s*)([A-Za-z][\w.\-]*)\s*:') |
            ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    $unexpected = $keys | Where-Object { $allowed -notcontains $_ }
    $results['J_key_allowlist'] = ($unexpected.Count -eq 0)
    if ($unexpected.Count -gt 0) { Write-Host "  (unexpected keys: $($unexpected -join ', '))" }

    # --- K: usage error is the only non-zero exit ---------------------------
    $r = Invoke-Collector @()
    $results['K_missing_arg_exit_two'] = ($r.Code -eq 2 -and $r.Output -match 'usage')

    # --- L: schema drift degrades instead of emitting wrong numbers ---------
    $dir = New-SessionFixture -Main @(
        (New-SessionStart),
        (New-LlmRequest -OmitTokenFields -NanoAiu 1500000000)
    )
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['L_drift_unavailable'] = ($r.Code -eq 0 -and
                                       $r.Output -match '(?m)^\s*available:\s*false\s*$' -and
                                       $r.Output -match 'reason:\s*schema_drift')

    # --- M: the watched attribute set is pinned -----------------------------
    # These field names carry no compatibility promise. Pinning the set here
    # means silently narrowing what the collector depends on -- and therefore
    # silently losing drift detection -- breaks a test instead of a total.
    $probe = @'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("c", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print(",".join(sorted(set(mod.REQUIRED_REQUEST_ATTRS) | {mod.BILLING_ATTR})))
print(mod.NANO_AIU_PER_CREDIT)
'@
    $probeFile = Join-Path ([IO.Path]::GetTempPath()) ("cost-probe-" + [Guid]::NewGuid().ToString('N') + '.py')
    Set-Content -LiteralPath $probeFile -Value $probe -Encoding UTF8
    $probeOut = (& $python $probeFile $collector 2>&1) -join "`n"
    Remove-Item $probeFile -Force -ErrorAction SilentlyContinue
    $results['M_watched_attrs_pinned'] = ($probeOut -match 'cachedTokens,copilotUsageNanoAiu,inputTokens,model,outputTokens')
    $results['M_credit_unit_pinned']   = ($probeOut -match '(?m)^1000000000\s*$')
}
finally {
    foreach ($f in $fixtures) {
        $parent = Split-Path -Parent $f
        if ($parent -and (Test-Path $parent)) { Remove-Item $parent -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Write-Host ''
Write-Host '=== Workflow Cost Collector ==='
$failed = 0
foreach ($name in $results.Keys) {
    if ($results[$name]) { Write-Host "  PASS: $name" }
    else { Write-Host "  FAIL: $name"; $failed++ }
}
Write-Host ''
Write-Host "  Checks passed: $($results.Count - $failed)"
Write-Host "  Checks failed: $failed"
if ($failed -gt 0) { Write-Host '  RESULT: COST COLLECTOR IS BROKEN'; exit 1 }
Write-Host '  RESULT: COST COLLECTOR IS WORKING'
exit 0
