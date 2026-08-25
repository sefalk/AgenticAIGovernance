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
        [switch]$NoMainFile,
        [switch]$RateCard
    )
    $base = Join-Path ([IO.Path]::GetTempPath()) ("sesscost-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $dir  = Join-Path $base $SID
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    if ($RateCard) {
        # Shape mirrors the real models.json dump: prices per `batch_size`
        # tokens. Two entries, because ConvertTo-Json in PS 5.1 unwraps a
        # one-element array into a bare object and the real dump is a list.
        $card = @(
            [ordered]@{
                id = 'claude-opus-5'
                billing = [ordered]@{
                    auto_discount = 0
                    token_prices = [ordered]@{
                        batch_size = 1000000
                        default = [ordered]@{
                            input_price = 500; cache_read_price = 50
                            cache_write_price = 0; output_price = 2500
                        }
                    }
                }
            },
            [ordered]@{
                id = 'claude-haiku-4.5'
                billing = [ordered]@{
                    auto_discount = 0
                    token_prices = [ordered]@{
                        batch_size = 1000000
                        default = [ordered]@{
                            input_price = 100; cache_read_price = 10
                            cache_write_price = 125; output_price = 500
                        }
                    }
                }
            }
        )
        [IO.File]::WriteAllText((Join-Path $dir 'models.json'), ($card | ConvertTo-Json -Depth 8))
    }
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
    $results['A_schema_version']   = ($r.Output -match '(?m)^\s*schema_version:\s*3\s*$')
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

    # --- P: credits split by token kind (issue #217) ------------------------
    # A cached token costs a tenth of an uncached one and an output token ten
    # times it, so three token counts and one credit scalar cannot be crossed
    # after the fact. 600 uncached * 500 + 400 cached * 50 + 50 out * 2500,
    # per 1e6 tokens = 0.3 + 0.02 + 0.125 = 0.445, and the identity closes.
    $dir = New-SessionFixture -RateCard -Main @(
        (New-SessionStart),
        (New-LlmRequest -NanoAiu 445000000)
    )
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['P_rate_card_named'] = ($r.Output -match '(?m)^\s*rate_card:\s*"models\.json"\s*$')
    $results['P_kind_split_exact'] = ($r.Output -match
        'credits_by_kind:\s*\{\s*input_uncached:\s*0\.3,\s*cache_read:\s*0\.02,\s*output:\s*0\.125,\s*unexplained:\s*0(\.0+)?\s*\}')

    # Cache-write tokens are billed and never logged. The remainder must be
    # named, not spread across the kinds that are known.
    $dir = New-SessionFixture -RateCard -Main @(
        (New-SessionStart),
        (New-LlmRequest -NanoAiu 1500000000)
    )
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['P_residual_named'] = ($r.Output -match 'unexplained:\s*1\.055\s*\}')
    # The parts must never appear to sum to more or less than the invoice.
    $m = [regex]::Match($r.Output, 'credits_by_kind:\s*\{\s*input_uncached:\s*([\d.]+),\s*cache_read:\s*([\d.]+),\s*output:\s*([\d.]+),\s*unexplained:\s*([\d.]+)')
    $sum = 0.0
    if ($m.Success) { 1..4 | ForEach-Object { $sum += [double]$m.Groups[$_].Value } }
    $results['P_kinds_close_on_total'] = ($m.Success -and [math]::Abs($sum - 1.5) -lt 0.0005)

    # No rate card is not zero cost: everything becomes unexplained.
    $dir = New-SessionFixture -Main @(
        (New-SessionStart),
        (New-LlmRequest -NanoAiu 1500000000)
    )
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['P_no_rate_card_null'] = ($r.Output -match '(?m)^\s*rate_card:\s*null\s*$')
    $results['P_no_rate_card_unexplained'] = ($r.Output -match
        'credits_by_kind:\s*\{\s*input_uncached:\s*0(\.0+)?,\s*cache_read:\s*0(\.0+)?,\s*output:\s*0(\.0+)?,\s*unexplained:\s*1\.5\s*\}')

    # --- Q: the facts artifact outlives the log (issue #217) ----------------
    $secret = 'SUPERSECRET-FACTS-ghp_zzz999'
    $dir = New-SessionFixture -RateCard -Main @(
        (New-SessionStart),
        (New-LlmRequest -NanoAiu 1500000000 -SecretText $secret),
        (New-LlmRequest -NanoAiu 500000000 -DebugName 'summarizeConversationHistory')
    )
    $fixtures += $dir
    $factsPath = Join-Path $dir 'facts.ndjson'
    $r = Invoke-Collector @('--session-dir', $dir, '--facts-out', $factsPath)
    $results['Q_facts_written'] = (Test-Path $factsPath)
    $results['Q_facts_path_in_block'] = ($r.Output -match '(?m)^\s*facts:\s*".*facts\.ndjson"\s*$')
    # A Windows path in a double-quoted YAML scalar must be escaped: raw
    # `C:\Users` is an invalid `\U` escape that would break the whole log.
    $pm = [regex]::Match($r.Output, '(?m)^\s*facts:\s*("[^\r\n]*facts\.ndjson")\s*$')
    # An unescaped path throws here rather than mismatching, so catch it: a
    # check that aborts the run reports nothing, which is worse than a FAIL.
    $decoded = $null
    if ($pm.Success) {
        try { $decoded = ('{"p":' + $pm.Groups[1].Value + '}' | ConvertFrom-Json).p } catch { $decoded = $null }
    }
    $results['Q_facts_path_escaped'] = ($decoded -eq $factsPath)
    if (Test-Path $factsPath) {
        $factLines = @([IO.File]::ReadAllLines($factsPath) | Where-Object { $_.Trim() })
        $raw = [IO.File]::ReadAllText($factsPath)
        # One header plus one row per request. An aggregate cannot be
        # un-aggregated, so a missing row is a question never askable again.
        $results['Q_facts_row_per_request'] = ($factLines.Count -eq 3)
        $results['Q_facts_header_versioned'] = ($factLines[0] -match '"facts_schema_version":\s*1' -and
                                                $factLines[0] -match '"record":\s*"header"')
        # The facts file is meant to be keepable; a prompt in it would make it
        # exactly as unshareable as the debug log it replaces.
        $results['Q_facts_no_prompt_leak'] = ($raw -notmatch 'SUPERSECRET')
        # Dimensions the block does not render today must still be captured.
        $results['Q_facts_carry_purpose'] = ($raw -match '"purpose":\s*"compaction"' -and
                                             $raw -match '"purpose":\s*"agent_work"')
        $results['Q_facts_carry_trace'] = ($raw -match '"parent_kind":\s*"session_start"')
        # The block must be an aggregation of these rows, not a second opinion.
        $nano = 0
        foreach ($l in ($factLines | Select-Object -Skip 1)) {
            $mm = [regex]::Match($l, '"nano_aiu":\s*(\d+)')
            if ($mm.Success) { $nano += [long]$mm.Groups[1].Value }
        }
        $results['Q_facts_reconcile_block'] = (($nano / 1e9) -eq 2.0 -and
                                               $r.Output -match '(?m)^\s*credits:\s*2(\.0+)?\s*$')
    }

    # Writing the artifact is opt-in: the collector is not the log's writer.
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['Q_facts_opt_in'] = ($r.Output -match '(?m)^\s*facts:\s*null\s*$')

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
    $results['F_kinds_withheld']      = ($r.Output -match '(?m)^\s*credits_by_kind:\s*null\s*$')
    # The rows survive the withholding: each is individually accurate, only the
    # set is incomplete, and the header says so.
    $tf = Join-Path $dir 'trunc.ndjson'
    $r = Invoke-Collector @('--session-dir', $dir, '--facts-out', $tf)
    $results['F_facts_still_written'] = (Test-Path $tf)
    if (Test-Path $tf) {
        $tl = @([IO.File]::ReadAllLines($tf) | Where-Object { $_.Trim() })
        $results['F_facts_rows_kept']     = ($tl.Count -eq 3)
        $results['F_facts_header_coverage'] = ($tl[0] -match '"coverage":\s*"truncated"')
    }

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
        'claude-haiku-4.5', 'rate_card', 'credits_by_kind', 'cache_read',
        'unexplained', 'facts'
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
