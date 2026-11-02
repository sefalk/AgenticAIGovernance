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

. (Join-Path $scriptDir '_suite_env.ps1')
function Resolve-Python { Get-AfSuitePython $scriptDir }

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

# A SessionStart hook's span. The editor writes one per hook BEFORE session_start
# (measured 2026-10-27, #467): an intact log of a deployment with two SessionStart
# hooks begins hook, hook, session_start.
function New-HookSpan([long]$Ts = ($T0 - 500), [string]$Name = 'SessionStart') {
    [ordered]@{
        ts = $Ts; dur = 3000; sid = $SID
        type = 'hook'; name = $Name; spanId = 'h0'; status = 'ok'
        attrs = [ordered]@{ command = 'powershell -File .github\hooks\scripts\session-context.ps1' }
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
        [string]$SecretText = '',
        [switch]$Payloads,
        [string]$Status = 'ok'
    )
    if ($Ts -eq 0) { $Ts = $T0 + 1000 }
    $attrs = [ordered]@{ model = $Model; debugName = $DebugName }
    if ($Payloads) {
        # The collector must take the payload KIND from which attribute named
        # the file, never from the filename -- so the fixture names them the
        # wrong way round on purpose.
        $attrs.systemPromptFile = 'dump_a.json'
        $attrs.toolsFile        = 'dump_b.json'
    }
    if (-not $OmitTokenFields) {
        $attrs.inputTokens  = $InputTokens
        $attrs.outputTokens = $OutputTokens
        $attrs.cachedTokens = $CachedTokens
    }
    if ($null -ne $NanoAiu) { $attrs.copilotUsageNanoAiu = $NanoAiu }
    if ($SecretText) { $attrs.userRequest = $SecretText; $attrs.inputMessages = $SecretText }
    [ordered]@{
        ts = $Ts; dur = 100; sid = $SID
        type = 'llm_request'; name = "chat:$Model"; spanId = 'r1'; parentSpanId = 's0'; status = $Status
        attrs = $attrs
    } | ConvertTo-Json -Compress -Depth 6
}

# Creates a session directory. $Main / $Child are arrays of JSONL lines.
function New-ToolCall([string]$Name, [long]$Ts = 0) {
    if ($Ts -eq 0) { $Ts = $T0 + 1200 }
    [ordered]@{
        ts = $Ts; dur = 5; sid = $SID
        type = 'tool_call'; name = $Name; spanId = 't1'; parentSpanId = 's0'; status = 'ok'
        # args/result are the call's payload and carry user text; the collector
        # must count the name and read neither.
        attrs = [ordered]@{ args = 'SUPERSECRET-ARGS'; result = 'SUPERSECRET-RESULT' }
    } | ConvertTo-Json -Compress -Depth 6
}

function New-Customization([string]$Details, [long]$Ts = 0) {
    if ($Ts -eq 0) { $Ts = $T0 + 1300 }
    [ordered]@{
        ts = $Ts; dur = 1; sid = $SID
        type = 'generic'; name = 'Resolve Customizations'; spanId = 'g1'; parentSpanId = 's0'; status = 'ok'
        attrs = [ordered]@{ category = 'customization'; details = $Details }
    } | ConvertTo-Json -Compress -Depth 6
}

# The two payload dumps a request can name. Both are `{"content": "<json>"}`,
# a JSON string holding more JSON -- the shape the real dumps use.
function Write-Dumps([string]$Dir, [switch]$Unparseable, [switch]$Mixed) {
    if ($Unparseable) {
        [IO.File]::WriteAllText((Join-Path $Dir 'dump_a.json'), '{"content": "not json at all"}')
        [IO.File]::WriteAllText((Join-Path $Dir 'dump_b.json'), 'not even a json object')
        return
    }
    $tools = @(
        [ordered]@{ name = 'read_file';               description = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' },
        [ordered]@{ name = 'mcp_pylance_mcp_s_alpha'; description = 'BBBBBBBBBBBBBBBBBBBB' },
        [ordered]@{ name = 'mcp_pylance_mcp_s_beta';  description = 'CCCCCCCCCCCCCCCCCCCC' }
    )
    $toolsJson = '[' + (($tools | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 4 }) -join ',') + ']'
    # The file NAMED by `toolsFile` is dump_b; see New-LlmRequest.
    [IO.File]::WriteAllText((Join-Path $Dir 'dump_b.json'),
        ([ordered]@{ content = $toolsJson } | ConvertTo-Json -Compress -Depth 4))

    $prompt = @(
        '<skill><name>alpha</name><file>x/alpha/SKILL.md</file></skill>',
        '<skill><name>beta</name><file>x/beta/SKILL.md</file></skill>',
        '<agent><name>gamma</name><description>d</description></agent>',
        '<instruction><file>x/y/delta.instructions.md</file><description>d</description></instruction>',
        '<attachment filePath="a\b\epsilon.instructions.md">BODYBODYBODYBODYBODYBODYBODY</attachment>'
    ) -join "`n"
    $blockJson = '[' + (([ordered]@{ type = 'text'; content = $prompt } | ConvertTo-Json -Compress -Depth 4)) + ']'
    if ($Mixed) {
        # One payload readable, one not: degradation is per payload.
        [IO.File]::WriteAllText((Join-Path $Dir 'dump_a.json'), '{"content": "not json at all"}')
        return
    }
    [IO.File]::WriteAllText((Join-Path $Dir 'dump_a.json'),
        ([ordered]@{ content = $blockJson } | ConvertTo-Json -Compress -Depth 4))
}

function New-SessionFixture {
    param(
        [string[]]$Main = @(),
        [string[]]$Child = @(),
        [string]$ChildName = 'runSubagent-implementer-toolu_test.jsonl',
        [string[]]$Child2 = @(),
        [string]$ChildName2 = 'runSubagent-implementer-toolu_second.jsonl',
        [switch]$NoMainFile,
        [switch]$RateCard,
        [switch]$Dumps,
        [switch]$BadDumps,
        [switch]$MixedDumps,
        # The collector takes the session identity from the directory name, so
        # this is how a fixture stands for a different chat session.
        [string]$SessionId = $SID
    )
    $base = Join-Path ([IO.Path]::GetTempPath()) ("sesscost-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $dir  = Join-Path $base $SessionId
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
    if ($Dumps)    { Write-Dumps -Dir $dir }
    if ($BadDumps) { Write-Dumps -Dir $dir -Unparseable }
    if ($MixedDumps) { Write-Dumps -Dir $dir -Mixed }
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
    $results['A_schema_version']   = ($r.Output -match '(?m)^\s*schema_version:\s*9\s*$')
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
    $canary = 'SUPERSECRET-FACTS-ghp_zzz999'
    $dir = New-SessionFixture -RateCard -Main @(
        (New-SessionStart),
        (New-LlmRequest -NanoAiu 1500000000 -SecretText $canary),
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
        $results['Q_facts_header_versioned'] = ($factLines[0] -match '"facts_schema_version":\s*3' -and
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

    # --- V: a later call adds to the artifact, it never replaces it (#253) --
    #
    # A workflow that spans two chat sessions runs the collector twice, and by
    # the second call the debug log the first session's rows came from is gone.
    # An overwrite would therefore delete the only surviving copy of them.
    $accPath = Join-Path $dir 'accumulate.ndjson'
    $second = New-SessionFixture -RateCard -SessionId 'a1b2c3d4-0000-4000-8000-000000000002' -Main @(
        (New-SessionStart),
        (New-LlmRequest -NanoAiu 2500000000)
    )
    $fixtures += $second

    $null = Invoke-Collector @('--session-dir', $dir, '--facts-out', $accPath)
    $firstPass = @([IO.File]::ReadAllLines($accPath) | Where-Object { $_.Trim() })
    $null = Invoke-Collector @('--session-dir', $second, '--facts-out', $accPath)
    $secondPass = @([IO.File]::ReadAllLines($accPath) | Where-Object { $_.Trim() })
    $results['V_later_session_appends'] = ($secondPass.Count -eq ($firstPass.Count + 2))
    # One header per session: a reader has to know which coverage and which
    # rate card the rows following it were priced under.
    $results['V_header_per_session'] =
        (@($secondPass | Where-Object { $_ -match '"record":\s*"header"' }).Count -eq 2)

    # The hook fires on every finalising call, so re-reading a session already
    # in the file must add nothing at all.
    $null = Invoke-Collector @('--session-dir', $second, '--facts-out', $accPath)
    $thirdPass = @([IO.File]::ReadAllLines($accPath) | Where-Object { $_.Trim() })
    $results['V_repeat_call_adds_nothing'] = ($thirdPass.Count -eq $secondPass.Count)

    # --- R: the purpose axis (issue #215) -----------------------------------
    # Compaction is the price of the session having grown too long. Folded into
    # the bucket of whichever agent's turn triggered it, it reads as that
    # agent's spend and points at the wrong lever.
    $dir = New-SessionFixture -Main @(
        (New-SessionStart),
        (New-LlmRequest -NanoAiu 1000000000),
        (New-LlmRequest -NanoAiu 4000000000 -DebugName 'summarizeConversationHistory'),
        (New-LlmRequest -NanoAiu $null -DebugName 'backgroundTodoAgent'),
        (New-LlmRequest -NanoAiu 500000000 -DebugName 'somethingNewFromTheVendor')
    ) -Child @(
        (New-LlmRequest -NanoAiu 2000000000 -DebugName 'tool/runSubagent-implementer')
    )
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['R_compaction_split']  = ($r.Output -match
        '(?m)^  by_purpose:\s*$[\s\S]*?^\s*compaction:\s*\{\s*requests:\s*1,\s*unbilled:\s*0,\s*credits:\s*4(\.0+)?\s*\}')
    # Unbilled and therefore invisible to every credit-weighted view; listed
    # anyway, because "it happened and cost nothing" is a different statement
    # from "it did not happen".
    $results['R_background_listed'] = ($r.Output -match
        'background:\s*\{\s*requests:\s*0,\s*unbilled:\s*1,\s*credits:\s*0(\.0+)?\s*\}')
    # An unrecognised debugName must not be sorted into a known bucket.
    $results['R_other_not_guessed'] = ($r.Output -match
        'other:\s*\{\s*requests:\s*1,\s*unbilled:\s*0,\s*credits:\s*0\.5\s*\}' -and
        $r.Output -notmatch 'somethingNewFromTheVendor')
    $results['R_agent_work_summed'] = ($r.Output -match
        'agent_work:\s*\{\s*requests:\s*2,\s*unbilled:\s*0,\s*credits:\s*3(\.0+)?\s*\}')

    # The axis must reconcile like the others, or it is a fifth opinion.
    $pm = [regex]::Matches($r.Output, '(?m)^    (agent_work|compaction|background|other):\s*\{\s*requests:\s*(\d+),\s*unbilled:\s*(\d+),\s*credits:\s*([\d.]+)')
    $pReq = 0; $pUnb = 0; $pCr = 0.0
    foreach ($x in $pm) { $pReq += [int]$x.Groups[2].Value; $pUnb += [int]$x.Groups[3].Value; $pCr += [double]$x.Groups[4].Value }
    $results['R_purpose_reconciles'] = ($pm.Count -eq 4 -and $pReq -eq 4 -and $pUnb -eq 1 -and
                                        [math]::Abs($pCr - 7.5) -lt 0.0005 -and
                                        $r.Output -match '(?m)^\s*credits:\s*7\.5\s*$')

    # Inside the bucket too: `main` must not read as 5 credits of coordinator work.
    # Sliced per bucket rather than matched across the whole block, so a lazy
    # `[\s\S]*?` cannot borrow a line from the next agent and pass.
    function Get-Bucket([string]$text, [string]$name) {
        # Single-quoted and concatenated: in a double-quoted string `$(` opens a
        # PowerShell subexpression and the pattern never reaches the regex engine.
        $pattern = '(?m)^    ' + [regex]::Escape($name) + ':\s*$([\s\S]*?)(?=^    \S|^  \S|\z)'
        $m = [regex]::Match($text, $pattern)
        if ($m.Success) { return $m.Groups[1].Value } else { return '' }
    }
    $mainB  = Get-Bucket $r.Output 'main'
    $implB  = Get-Bucket $r.Output 'implementer'
    $results['R_bucket_labelled'] = ($mainB -match 'compaction:\s*\{\s*requests:\s*1,\s*unbilled:\s*0,\s*credits:\s*4(\.0+)?\s*\}' -and
                                     $mainB -match 'agent_work:\s*\{\s*requests:\s*1,')
    # Rendered even where it is uniform, so absence never has two meanings --
    # and the implementer must carry no compaction it did not cause.
    $results['R_uniform_bucket_rendered'] = ($implB -match '(?m)^\s*by_purpose:\s*$' -and
                                             $implB -match 'agent_work:\s*\{\s*requests:\s*1,\s*unbilled:\s*0,\s*credits:\s*2(\.0+)?\s*\}' -and
                                             $implB -notmatch 'compaction')

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

    # --- F2: truncation is judged on main.jsonl alone (#450) -----------------
    # Every subagent log carries its own session_start, and a window reload
    # writes another into main.jsonl. Neither is the start of the session.
    $dir = New-SessionFixture -Main @(
        (New-LlmRequest -NanoAiu 1500000000)
    ) -Child @(
        (New-SessionStart),
        (New-LlmRequest -Model 'claude-haiku-4.5' -NanoAiu 1000000000)
    )
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['F2_subagent_start_does_not_vouch_for_main'] = ($r.Output -match '(?m)^\s*coverage:\s*truncated\s*$')

    # The size cap cuts mid-line: the first line is a fragment, and a reload
    # session_start further down must not certify what was cut.
    $dir = New-SessionFixture -Main @(
        '"attrs":{"model":"claude-opus-5","inputTokens":9}},"cut-off fragment',
        (New-SessionStart -Ts ($T0 + 500)),
        (New-LlmRequest -NanoAiu 1500000000)
    )
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['F2_fragment_head_is_truncated'] = ($r.Output -match '(?m)^\s*coverage:\s*truncated\s*$')
    # A withheld total can still be dated by the first event that survived.
    $results['F2_earliest_surviving_event_dated'] = ($r.Output -match "(?m)^\s*earliest_ts:\s*$($T0 + 500)\s*$")

    # Control: a genuine start followed by a reload start is a complete log.
    $dir = New-SessionFixture -Main @(
        (New-SessionStart),
        (New-LlmRequest -NanoAiu 1500000000),
        (New-SessionStart -Ts ($T0 + 5000)),
        (New-LlmRequest -NanoAiu 2500000000 -Ts ($T0 + 6000))
    )
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['F2_reload_start_keeps_full'] = ($r.Output -match '(?m)^\s*coverage:\s*full\s*$' -and
                                              $r.Output -match '(?m)^\s*credits:\s*4(\.0+)?\s*$' -and
                                              $r.Output -notmatch 'earliest_ts')

    # --- F3: SessionStart hook spans precede session_start (#467) ------------
    # Every intact log of a deployment with SessionStart hooks begins with their
    # spans. Reading that as a lost head withheld the total of every session.
    $dir = New-SessionFixture -Main @(
        (New-HookSpan -Ts ($T0 - 600)),
        (New-HookSpan -Ts ($T0 - 300)),
        (New-SessionStart),
        (New-LlmRequest -NanoAiu 1500000000)
    )
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['F3_hook_spans_then_start_is_full'] = ($r.Output -match '(?m)^\s*coverage:\s*full\s*$' -and
                                                    $r.Output -match '(?m)^\s*credits:\s*1\.5\s*$')

    # A hook span vouches for nothing on its own: what follows must be the start.
    $dir = New-SessionFixture -Main @(
        (New-HookSpan),
        (New-LlmRequest -NanoAiu 1500000000)
    )
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['F3_hook_span_without_start_is_truncated'] = ($r.Output -match '(?m)^\s*coverage:\s*truncated\s*$')

    # Only SessionStart hooks run before the session starts; any other hook first is a cut.
    $dir = New-SessionFixture -Main @(
        (New-HookSpan -Name 'PreToolUse'),
        (New-SessionStart),
        (New-LlmRequest -NanoAiu 1500000000)
    )
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['F3_other_hook_first_is_truncated'] = ($r.Output -match '(?m)^\s*coverage:\s*truncated\s*$')

    # --- W: the long_context price tier (#451) --------------------------------
    # A prompt above default.max_prompt_tokens is billed at long_context. 200k
    # uncached * 50 + 1000 out * 250 per 1e6 = 10.25 credits; 50k * 10 + 100 *
    # 50 per 1e6 = 0.505 credits at default. Exact bills leave no residual.
    $dir = New-SessionFixture -Main @(
        (New-SessionStart),
        (New-LlmRequest -Model 'claude-haiku-x' -InputTokens 200000 -CachedTokens 0 -OutputTokens 1000 -NanoAiu 10250000000),
        (New-LlmRequest -Model 'claude-haiku-x' -InputTokens 50000 -CachedTokens 0 -OutputTokens 100 -NanoAiu 505000000)
    )
    $fixtures += $dir
    $tiered = @(
        [ordered]@{ id = 'claude-haiku-x'; billing = [ordered]@{ auto_discount = 0; token_prices = [ordered]@{
            batch_size = 1000000
            default      = [ordered]@{ input_price = 10; cache_read_price = 1; cache_write_price = 0; output_price = 50; max_prompt_tokens = 100000 }
            long_context = [ordered]@{ input_price = 50; cache_read_price = 5; cache_write_price = 0; output_price = 250; max_prompt_tokens = 936000 } } } },
        [ordered]@{ id = 'unused'; billing = [ordered]@{ token_prices = [ordered]@{ default = [ordered]@{ input_price = 1; cache_read_price = 1; output_price = 1 } } } }
    )
    [IO.File]::WriteAllText((Join-Path $dir 'models.json'), ($tiered | ConvertTo-Json -Depth 8))
    $wf = Join-Path $dir 'tier-facts.ndjson'
    $r = Invoke-Collector @('--session-dir', $dir, '--facts-out', $wf)
    $results['W_long_context_priced'] = ($r.Output -match
        'credits_by_kind:\s*\{\s*input_uncached:\s*10\.5,\s*cache_read:\s*0(\.0+)?,\s*output:\s*0\.255,\s*unexplained:\s*0(\.0+)?\s*\}')
    $wraw = if (Test-Path $wf) { [IO.File]::ReadAllText($wf) } else { '' }
    # The applied tier is on the row, so the choice stays auditable.
    $results['W_tier_recorded'] = ($wraw -match '"price_tier":\s*"long_context"' -and $wraw -match '"price_tier":\s*"default"')

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
    $canary = 'SUPERSECRET-TOKEN-ghp_abcdef123456'
    $dir = New-SessionFixture -Main @(
        (New-SessionStart),
        (New-LlmRequest -NanoAiu 1500000000 -SecretText $canary)
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
        'unexplained', 'facts', 'by_purpose', 'agent_work', 'compaction',
        'background', 'other', 'unbilled', 'by_entity', 'no_usage_requests',
        'kinds', 'inferred', 'lower_bound'
    )
    $keys = [regex]::Matches($r.Output, '(?m)(?:^\s*|[{,]\s*)([A-Za-z][\w.\-]*)\s*:') |
            ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    $unexpected = $keys | Where-Object { $allowed -notcontains $_ }
    $results['J_key_allowlist'] = ($unexpected.Count -eq 0)
    if ($unexpected.Count -gt 0) { Write-Host "  (unexpected keys: $($unexpected -join ', '))" }

    # --- Z: every field says whether it is measured or inferred (#477) -------
    # A new field must not present an estimate as a fact: each top-level field
    # is declared in FIELD_KINDS, and the block itself names its inferred and
    # lower-bound fields so a reader of one workflow log needs no source.
    $kindProbe = @'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("c", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print(json.dumps({"kinds": getattr(mod, "FIELD_KINDS", {}), "rules": getattr(mod, "INFERRED_RULES", {})}))
'@
    $kindFile = Join-Path ([IO.Path]::GetTempPath()) ("cost-kinds-" + [Guid]::NewGuid().ToString('N') + '.py')
    Set-Content -LiteralPath $kindFile -Value $kindProbe -Encoding UTF8
    $declared = $null
    try { $declared = ((& $python $kindFile $collector 2>&1) -join '') | ConvertFrom-Json } catch {}
    Remove-Item $kindFile -Force -ErrorAction SilentlyContinue
    $kindNames = @($(if ($declared -and $declared.kinds) { $declared.kinds.PSObject.Properties.Name }) | Where-Object { $_ })
    $ruleNames = @($(if ($declared -and $declared.rules) { $declared.rules.PSObject.Properties.Name }) | Where-Object { $_ })
    $validKinds = @('measured', 'inferred', 'lower_bound', 'meta')

    $zFull = New-SessionFixture -Main @(
        (New-SessionStart),
        (New-LlmRequest -NanoAiu 1500000000)
    )
    $zTrunc = New-SessionFixture -Main @(
        (New-LlmRequest -NanoAiu 1500000000)
    )
    $fixtures += $zFull, $zTrunc
    $zOutFull  = (Invoke-Collector @('--session-dir', $zFull)).Output
    $zOutTrunc = (Invoke-Collector @('--session-dir', $zTrunc)).Output
    $zFields = @(foreach ($o in $zOutFull, $zOutTrunc) {
        [regex]::Matches($o, '(?m)^  ([a-z_]+):') | ForEach-Object { $_.Groups[1].Value }
    }) | Sort-Object -Unique
    $undeclared = @($zFields | Where-Object { $kindNames -notcontains $_ })
    $badKind = @($kindNames | Where-Object { $validKinds -notcontains $declared.kinds.$_ })
    $results['Z_every_field_declares_a_kind'] = ($zFields.Count -ge 15 -and $undeclared.Count -eq 0 -and $badKind.Count -eq 0)
    if ($undeclared.Count -gt 0) { Write-Host "  (fields without a kind: $($undeclared -join ', '))" }
    if ($badKind.Count -gt 0) { Write-Host "  (not a kind: $($badKind -join ', '))" }

    $inferred = @($kindNames | Where-Object { $declared.kinds.$_ -eq 'inferred' })
    $ruleless = @($inferred | Where-Object { $ruleNames -notcontains $_ })
    $results['Z_every_inferred_field_names_its_rule'] = ($inferred.Count -ge 1 -and $ruleless.Count -eq 0)

    # The block carries the declaration for the fields it actually emitted.
    $results['Z_block_names_inferred_fields'] = ($zOutFull -match '(?m)^  kinds: \{ inferred: \{ coverage: [a-z0-9-]+,')
    $results['Z_block_names_the_lower_bound'] = ($zOutTrunc -match '(?m)^  kinds: .*lower_bound: \[surviving\]' -and
                                                 $zOutFull -notmatch 'lower_bound')

    # Each rule id is defined once, in the README section the block points to.
    $readmeKinds = [IO.File]::ReadAllText((Join-Path $repoRootAF '.github/logs/README.md'))
    $undocumented = @($ruleNames | Where-Object { $readmeKinds -notmatch ('`' + [regex]::Escape([string]$declared.rules.$_) + '`') })
    $results['Z_rule_ids_documented'] = ($ruleNames.Count -ge 1 -and $undocumented.Count -eq 0 -and
                                         $readmeKinds -match '(?m)^## Measured, inferred, lower bound')

    # --- Y: context per log, floor and inferred compactions (#479) ----------
    # Input = uncached + cached: what the model read, not what it cost. Only
    # agent_work requests form the series; a compaction call is another
    # conversation. A fall of more than half between two requests is a drop.
    $ctxProbe = @'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("c", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
def f(log, agent, ts, size, purpose="agent_work"):
    return {"log": log, "agent": agent, "ts": ts, "input_uncached": size - 100, "cached": 100,
            "model": "m", "purpose": purpose}
facts = [f("main.jsonl", "main", t, s) for t, s in [(1, 10000), (2, 12000), (3, 30000), (4, 9000), (5, 12000), (6, 7300)]]
facts.append(f("main.jsonl", "main", 3.5, 50000, "compaction"))
facts += [f("runSubagent-implementer-t1.jsonl", "implementer", t, s) for t, s in [(2, 5000), (3, 6000)]]
out = {"full": mod.context_series(facts), "cut": mod.context_series(facts, head_lost=True), "ratio": mod.CONTEXT_DROP}
print(json.dumps(out))
'@
    $ctxFile = Join-Path ([IO.Path]::GetTempPath()) ("cost-ctx-" + [Guid]::NewGuid().ToString('N') + '.py')
    Set-Content -LiteralPath $ctxFile -Value $ctxProbe -Encoding UTF8
    $ctx = $null
    try { $ctx = ((& $python $ctxFile $collector 2>&1) -join '') | ConvertFrom-Json } catch {}
    Remove-Item $ctxFile -Force -ErrorAction SilentlyContinue
    $m = if ($ctx) { $ctx.full.'main.jsonl' } else { $null }
    $i = if ($ctx) { $ctx.full.'runSubagent-implementer-t1.jsonl' } else { $null }
    $results['Y_series_per_log_without_compaction'] = ($m -and @($m.points).Count -eq 6 -and $m.agent -eq 'main' -and $i -and @($i.points).Count -eq 2)
    $results['Y_floor_median_max'] = ($m -and $m.floor -eq 10000 -and $m.median -eq 11000 -and $m.max -eq 30000 -and $i.floor -eq 5000)
    # 30000 -> 9000 is a 70 % fall; 12000 -> 7300 (39 %) is not.
    $results['Y_drop_over_half_is_inferred_compaction'] = ($m -and $ctx.ratio -eq 0.5 -and @($m.drops).Count -eq 1 -and
        $m.drops[0].ts -eq 4 -and $m.drops[0].from -eq 30000 -and $m.drops[0].to -eq 9000)
    # A log that lost its head has no first request to call a floor.
    $results['Y_lost_head_has_no_floor'] = ($ctx -and $null -eq $ctx.cut.'main.jsonl'.floor -and $ctx.cut.'runSubagent-implementer-t1.jsonl'.floor -eq 5000)

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

    # --- N: the documented example cannot fall behind the collector ---------
    # It fell three versions behind unnoticed (issue #227). A hand-kept example
    # is documentation only for as long as something compares it to the code.
    $readme  = Join-Path $repoRootAF '.github/logs/README.md'
    $docVer  = -1
    $codeVer = -1
    $readmeText = ''
    if (Test-Path $readme) {
        $readmeText = [IO.File]::ReadAllText($readme)
        if ($readmeText -match '(?m)^\s*schema_version:\s*(\d+)\s*$') { $docVer = [int]$Matches[1] }
    }
    if ((Get-Content $collector -Raw) -match '(?m)^SCHEMA_VERSION\s*=\s*(\d+)') { $codeVer = [int]$Matches[1] }
    $results['N_readme_version_matches'] = ($codeVer -gt 0 -and $docVer -eq $codeVer)
    $results['N_readme_collector_tag']   = ($codeVer -gt 0 -and
                                            $readmeText -match "collect-session-cost\.py@$codeVer")
    if ($docVer -ne $codeVer) { Write-Host "  (README documents v$docVer, collector emits v$codeVer)" }

    # The version scalar can match while the documented taxonomy is a class
    # short: the example block shows whichever classes one session happened to
    # carry, so it cannot be the register. Derived from the collector rather
    # than listed here, or this check becomes the third copy to fall behind.
    $classProbe = @'
import importlib.util, re, sys
spec = importlib.util.spec_from_file_location("c", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
with open(sys.argv[1], encoding="utf-8") as handle:
    literal = set(re.findall(r'"class": "(\w+)"', handle.read()))
print(",".join(sorted(set(mod.PROMPT_ENTITY) | literal)))
'@
    $classFile = Join-Path ([IO.Path]::GetTempPath()) ("cost-classes-" + [Guid]::NewGuid().ToString('N') + '.py')
    Set-Content -LiteralPath $classFile -Value $classProbe -Encoding UTF8
    $codeClasses = @(((& $python $classFile $collector 2>&1) -join '').Trim() -split ',' | Where-Object { $_ })
    Remove-Item $classFile -Force -ErrorAction SilentlyContinue
    $docSentence = [regex]::Match($readmeText, 'classes` is a closed set:\*\*([\s\S]*?)\.').Groups[1].Value
    $docClasses  = @([regex]::Matches($docSentence, '`([a-z_]+)`') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    # Guards the extraction: a reworded bullet would otherwise compare two
    # empty sets and pass.
    $results['N_class_set_found'] = ($codeClasses.Count -ge 5 -and $docClasses.Count -ge 5)
    $results['N_class_set_documented'] = (($codeClasses -join ',') -eq ($docClasses -join ','))
    if (($codeClasses -join ',') -ne ($docClasses -join ',')) {
        Write-Host "  (README documents [$($docClasses -join ', ')], collector emits [$($codeClasses -join ', ')])"
    }

    # --- T: a request that reported no usage is not drift (issue #238) ------
    # A failed compaction carries no token counts and no billing attribute: it
    # consumed nothing, so there is nothing to account for. Reading that
    # absence as drift discarded the whole session's cost -- and compaction
    # only happens in long sessions, so the data died where it was worth most.
    $dir = New-SessionFixture -Main @(
        (New-SessionStart),
        (New-LlmRequest -InputTokens 1000 -CachedTokens 400 -OutputTokens 50 -NanoAiu 1500000000),
        (New-LlmRequest -OmitTokenFields -NanoAiu $null -Status 'error' -DebugName 'summarizeConversationHistory'),
        (New-LlmRequest -InputTokens 2000 -CachedTokens 900 -OutputTokens 60 -NanoAiu 2500000000)
    )
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['T_available_true'] = ($r.Output -match '(?m)^\s*available:\s*true\s*$')
    $results['T_billed_still_summed'] = ($r.Output -match '(?m)^\s*requests:\s*2\s*$' -and
                                         $r.Output -match '(?m)^\s*credits:\s*4(\.0+)?\s*$')
    # Counted, not swallowed: the request was made, it just cost nothing.
    $results['T_no_usage_counted'] = ($r.Output -match '(?m)^\s*no_usage_requests:\s*1\s*$')
    # And not folded into `unbilled`, which is for requests that DID spend
    # tokens -- merging the two would hide a failure inside a normal category.
    $results['T_not_counted_unbilled'] = ($r.Output -match '(?m)^\s*unbilled_requests:\s*0\s*$')

    # One such record in 51 carried `status: ok`, so the test is "reported no
    # usage", not "said it failed". A status-based check would let that one
    # through and void the session anyway.
    $dir = New-SessionFixture -Main @(
        (New-SessionStart),
        (New-LlmRequest -NanoAiu 1500000000),
        (New-LlmRequest -OmitTokenFields -NanoAiu $null)
    )
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['T_ok_status_no_usage'] = ($r.Output -match '(?m)^\s*available:\s*true\s*$' -and
                                        $r.Output -match '(?m)^\s*no_usage_requests:\s*1\s*$')

    # --- U: real drift degrades per record, not per session -----------------
    # A BILLED request missing its token fields is genuine drift. It must not
    # take the requests that parsed cleanly down with it.
    $dir = New-SessionFixture -Main @(
        (New-SessionStart),
        (New-LlmRequest -InputTokens 1000 -CachedTokens 400 -OutputTokens 50 -NanoAiu 1500000000),
        (New-LlmRequest -OmitTokenFields -NanoAiu 1500000000),
        (New-LlmRequest -InputTokens 2000 -CachedTokens 900 -OutputTokens 60 -NanoAiu 2500000000)
    )
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['U_partial_drift_available'] = ($r.Output -match '(?m)^\s*available:\s*true\s*$' -and
                                             $r.Output -match '(?m)^\s*requests:\s*2\s*$')
    # The loss is stated at the grain that lets a reader judge it: which field
    # moved, and how many records it cost out of how many.
    $results['U_drift_named'] = ($r.Output -match 'drift:\s*\{\s*records:\s*1,\s*of:\s*3,\s*fields:\s*\[inputTokens\],\s*logs:\s*\[main\.jsonl\]\s*\}')

    # A session is many logs. Drift confined to one subagent is a different
    # finding from drift in main.jsonl, and only the log name separates them.
    $dir = New-SessionFixture -Main @(
        (New-SessionStart),
        (New-LlmRequest -InputTokens 1000 -CachedTokens 400 -OutputTokens 50 -NanoAiu 1500000000)
    ) -Child @(
        (New-LlmRequest -OmitTokenFields -NanoAiu 1500000000)
    )
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['U_drift_names_its_log'] = ($r.Output -match 'logs:\s*\[runSubagent-implementer-toolu_test\.jsonl\]' -and
                                         $r.Output -notmatch 'logs:\s*\[[^\]]*main\.jsonl')

    # Silence is the bug the key exists to prevent -- but a clean session must
    # not carry it either, or it stops meaning anything.
    $dir = New-SessionFixture -Main @(
        (New-SessionStart),
        (New-LlmRequest -NanoAiu 1500000000)
    )
    $fixtures += $dir
    $results['U_no_drift_no_key'] = ((Invoke-Collector @('--session-dir', $dir)).Output -notmatch '(?m)^\s*drift:')

    # --- S: the entity axis (issue #214) ------------------------------------
    # Get-Bucket slices a 4-space agent bucket; `by_entity` sits at the top
    # level next to `by_agent`, so it needs its own slicer. Sliced rather than
    # matched across the whole output, so a check cannot pass on a line that
    # belongs to a different block.
    function Get-TopBlock([string]$text, [string]$name) {
        $pattern = '(?m)^  ' + [regex]::Escape($name) + ':\s*$([\s\S]*?)(?=^  \S|^\S|\z)'
        $m = [regex]::Match($text, $pattern)
        if ($m.Success) { return $m.Groups[1].Value } else { return '' }
    }
    # What the payload carried, as opposed to what the request cost. Two calls
    # on one built-in tool; the pylance pair is never called, which is exactly
    # the finding the block exists to make visible.
    $em = [char]0x2014
    $custom = "Resolved 3 customizations in 4ms | [applying] git-workflow.instructions.md $em always applied, " +
              "[skipped] testing.instructions.md $em applyTo '**/test_*.py' did not match any attached files, " +
              '[custom-agent] Explore'
    $dir = New-SessionFixture -Dumps -Main @(
        (New-SessionStart),
        (New-LlmRequest -NanoAiu 1500000000 -Payloads),
        (New-LlmRequest -NanoAiu 2500000000 -Payloads),
        (New-ToolCall -Name 'read_file'),
        (New-ToolCall -Name 'read_file'),
        (New-Customization -Details $custom)
    )
    $fixtures += $dir
    $ef = Join-Path $dir 'entities.ndjson'
    $r  = Invoke-Collector @('--session-dir', $dir, '--entities-out', $ef)
    $blk = Get-TopBlock $r.Output 'by_entity'
    $results['S_block_available']    = ($blk -match '(?m)^\s*available:\s*true\s*$')
    # Stated in the block itself, not only in the README: the reader who would
    # multiply a footprint by a price is reading this file, not the docs.
    $results['S_credits_disclaimed'] = ($blk -match '(?m)^\s*credits_attributable:\s*false\s*$')
    $results['S_payloads_counted']   = ($blk -match 'system_prompt:\s*1,\s*tools:\s*1,\s*unreadable:\s*0')
    # Kind comes from the attribute, not the filename: the fixture names the
    # system prompt `dump_a` and the tools `dump_b`, so a filename-based parse
    # would swap them and this check would fail.
    $results['S_classes_parsed'] = (
        $blk -match '(?m)^\s*tool:\s*\{\s*entities:\s*3,' -and
        $blk -match '(?m)^\s*skill:\s*\{\s*entities:\s*2,' -and
        $blk -match '(?m)^\s*agent:\s*\{\s*entities:\s*1,' -and
        $blk -match '(?m)^\s*instruction:\s*\{\s*entities:\s*1,' -and
        $blk -match '(?m)^\s*instruction_attached:\s*\{\s*entities:\s*1,')
    # A zero next to a token figure reads as "never used". Skills and agents
    # are read, not called, so no count is honest there -- and none is emitted.
    $results['S_invoked_only_where_measurable'] = (
        $blk -notmatch '(?m)^\s*(skill|agent|instruction|instruction_attached|tool):.*invoked')
    $results['S_tool_groups_split'] = (
        $blk -match '(?m)^\s*built-in:\s*\{\s*entities:\s*1,[^}]*invoked:\s*2\s*\}' -and
        $blk -match '(?m)^\s*mcp:pylance:\s*\{\s*entities:\s*2,[^}]*invoked:\s*0\s*\}')
    # Class total must equal the sum of its groups; a dropped or double-counted
    # row shows up here and nowhere else.
    $classTok = -1
    if ($blk -match '(?m)^\s*tool:\s*\{\s*entities:\s*3,\s*tokens_est_per_request:\s*(\d+)') { $classTok = [int]$Matches[1] }
    $grpTok = 0
    foreach ($m in [regex]::Matches($blk, '(?m)^\s*(?:built-in|mcp:pylance):\s*\{[^}]*tokens_est_per_request:\s*(\d+)')) {
        $grpTok += [int]$m.Groups[1].Value
    }
    $results['S_class_equals_groups'] = ($classTok -gt 0 -and $classTok -eq $grpTok)
    $results['S_customizations_split'] = (
        $blk -match 'git-workflow\.instructions\.md:\s*\{\s*applying:\s*1,\s*skipped:\s*0' -and
        $blk -match 'testing\.instructions\.md:\s*\{\s*applying:\s*0,\s*skipped:\s*1')
    # The skip reason is the actionable half: it says whether to narrow the
    # applyTo pattern or delete the file.
    $results['S_skip_reason_kept'] = ($blk -match "applyTo '\*\*/test_\*\.py' did not match any attached files")
    # ...and it must stop at the next bracketed marker instead of swallowing it.
    $results['S_reason_not_overrun'] = ($blk -notmatch 'custom-agent')
    # Never-applied first: paid for on every request, used on none.
    $results['S_never_applied_first'] = (
        $blk.IndexOf('testing.instructions.md') -lt $blk.IndexOf('git-workflow.instructions.md'))
    $results['S_no_prompt_leak'] = ($r.Output -notmatch 'SUPERSECRET' -and $r.Output -notmatch 'BODYBODY' -and
                                    (-not (Test-Path $ef) -or
                                     ([IO.File]::ReadAllText($ef) -notmatch 'SUPERSECRET|BODYBODY|<skill>')))

    # Structural keys inside the block are an allowlist; entity NAMES are data
    # and are excluded, which is why this cannot ride on J_key_allowlist.
    $entAllowed = @(
        'by_entity', 'available', 'credits_attributable', 'payloads', 'system_prompt',
        'tools', 'unreadable', 'classes', 'tools_by_group', 'customizations', 'rows'
    )
    $structural = (($blk -split "`n") | Where-Object { $_ -notmatch '^\s+\S.*:\s*\{' }) -join "`n"
    $entKeys = [regex]::Matches($structural, '(?m)(?:^\s*|[{,]\s*)([A-Za-z][\w.\-]*)\s*:') |
               ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    $entUnexpected = @($entKeys | Where-Object { $entAllowed -notcontains $_ })
    $results['S_entity_key_allowlist'] = ($entUnexpected.Count -eq 0)
    if ($entUnexpected.Count -gt 0) { Write-Host "  (unexpected entity keys: $($entUnexpected -join ', '))" }

    # --- S: the entity artifact, at its own grain ---------------------------
    $results['S_entities_written'] = (Test-Path $ef)
    if (Test-Path $ef) {
        $el = @([IO.File]::ReadAllLines($ef) | Where-Object { $_.Trim() })
        # 8 definitions x 1 payload each, plus the header.
        $results['S_entity_rows'] = ($el.Count -eq 9)
        $results['S_entity_header'] = (
            $el[0] -match '"entity_schema_version":\s*2' -and
            $el[0] -match '"grain":\s*"payload x entity"' -and
            $el[0] -match '"credits_attributable":\s*false')
        # No credit figure exists at this grain, so none may appear here --
        # not even one derived from the facts file. The whole key set is
        # pinned, not just the credit-ish names: the artifact is the shareable
        # thing, so a new field must be a deliberate act, and prompt text
        # smuggled into a row is caught here rather than by a name pattern.
        $rowKeys = @()
        foreach ($line in $el[1..($el.Count - 1)]) {
            $rowKeys += [regex]::Matches($line, '"([^"]+)":') | ForEach-Object { $_.Groups[1].Value }
        }
        $rowKeys = $rowKeys | Sort-Object -Unique
        $results['S_entity_row_keys_pinned'] =
            (($rowKeys -join ',') -eq 'chars,class,group,name,payload,record,requests,session,tokens_est')
        $results['S_entity_no_credit_column'] =
            (($el[1..($el.Count - 1)] -join "`n") -notmatch '"[^"]*(credit|nano|aiu|price|cost)[^"]*":')
        # The fan-out is visible in the file's own shape: `requests` is a
        # multiplier, so summing it exceeds the session's real request count.
        # 8 rows x 2 requests = 16 against 2 requests actually made.
        $reqSum = 0
        foreach ($line in $el[1..($el.Count - 1)]) {
            if ($line -match '"requests":\s*(\d+)') { $reqSum += [int]$Matches[1] }
        }
        $results['S_entities_not_summable'] = ($reqSum -eq 16 -and $r.Output -match '(?m)^\s*requests:\s*2\s*$')
        # Re-aggregating the rows must reproduce the rendered mean, or the
        # summary and the artifact are telling different stories.
        $w = 0; $den = @{}
        foreach ($line in $el[1..($el.Count - 1)]) {
            if ($line -match '"class":\s*"tool"' -and $line -match '"tokens_est":\s*(\d+)') {
                $tok = [int]$Matches[1]
                $rq = 0
                if ($line -match '"requests":\s*(\d+)') { $rq = [int]$Matches[1] }
                if ($line -match '"payload":\s*"([^"]+)"') { $den[$Matches[1]] = $rq }
                $w += $tok * $rq
            }
        }
        $d = 0; foreach ($v in $den.Values) { $d += $v }
        $results['S_entities_reconcile_block'] = ($d -gt 0 -and [math]::Round($w / $d) -eq $classTok)
    }
    # Opt-in, like the facts file: no flag, no file, and the block says so.
    $r2 = Invoke-Collector @('--session-dir', $dir)
    $results['S_entities_opt_in'] = ((Get-TopBlock $r2.Output 'by_entity') -match '(?m)^\s*rows:\s*null\s*$')

    # --- S: degradation, never a silent zero --------------------------------
    # (a) no request ever named a payload -- there is nothing to attribute to.
    $dir = New-SessionFixture -Main @(
        (New-SessionStart),
        (New-LlmRequest -NanoAiu 1500000000)
    )
    $fixtures += $dir
    $blk = Get-TopBlock (Invoke-Collector @('--session-dir', $dir)).Output 'by_entity'
    $results['S_no_payload_named'] = ($blk -match '(?m)^\s*available:\s*false\s*$' -and
                                      $blk -match 'reason:\s*payload_not_named')

    # (b) payloads named but the dumps are gone -- they expire with the log.
    $dir = New-SessionFixture -Main @(
        (New-SessionStart),
        (New-LlmRequest -NanoAiu 1500000000 -Payloads)
    )
    $fixtures += $dir
    $blk = Get-TopBlock (Invoke-Collector @('--session-dir', $dir)).Output 'by_entity'
    $results['S_dumps_missing'] = ($blk -match '(?m)^\s*available:\s*false\s*$' -and
                                   $blk -match 'reason:\s*payload_dumps_unreadable')

    # (c) dumps present but unparseable -- degrade, do not guess.
    $dir = New-SessionFixture -BadDumps -Main @(
        (New-SessionStart),
        (New-LlmRequest -NanoAiu 1500000000 -Payloads)
    )
    $fixtures += $dir
    $blk = Get-TopBlock (Invoke-Collector @('--session-dir', $dir)).Output 'by_entity'
    $results['S_dumps_unparseable'] = ($blk -match '(?m)^\s*available:\s*false\s*$' -and
                                       $blk -match 'reason:\s*payload_dumps_unreadable')

    # (d) one payload readable, one not. Degradation is per payload: the
    # readable half is still attributed and the loss is counted, rather than
    # the whole block going dark or the gap being silently absorbed.
    $dir = New-SessionFixture -MixedDumps -Main @(
        (New-SessionStart),
        (New-LlmRequest -NanoAiu 1500000000 -Payloads)
    )
    $fixtures += $dir
    $blk = Get-TopBlock (Invoke-Collector @('--session-dir', $dir)).Output 'by_entity'
    $results['S_partial_dumps'] = (
        $blk -match '(?m)^\s*available:\s*true\s*$' -and
        $blk -match 'system_prompt:\s*0,\s*tools:\s*1,\s*unreadable:\s*1' -and
        $blk -match '(?m)^\s*tool:\s*\{\s*entities:\s*3,' -and
        $blk -notmatch '(?m)^\s*skill:')

    # (e) truncated: every row is still accurate, but the request weighting
    # behind the mean is not, so the block is withheld and the rows survive.
    $dir = New-SessionFixture -Dumps -Main @(
        (New-LlmRequest -NanoAiu 1500000000 -Payloads),
        (New-LlmRequest -NanoAiu 2500000000 -Payloads)
    )
    $fixtures += $dir
    $tef = Join-Path $dir 'trunc-entities.ndjson'
    $r = Invoke-Collector @('--session-dir', $dir, '--entities-out', $tef)
    $results['S_truncated_withheld'] = ($r.Output -match '(?m)^\s*coverage:\s*truncated\s*$' -and
                                        $r.Output -match '(?m)^\s*by_entity:\s*null\s*$')
    $results['S_truncated_rows_kept'] = (Test-Path $tef)
    if (Test-Path $tef) {
        $tel = @([IO.File]::ReadAllLines($tef) | Where-Object { $_.Trim() })
        $results['S_truncated_header_coverage'] = ($tel.Count -eq 9 -and $tel[0] -match '"coverage":\s*"truncated"')
    }

    # --- X: the session store keeps up with the log (#457) -------------------
    #
    # The debug log loses its head at a moment nobody controls. Extracted once,
    # at the end of a workflow, a long session is gone before it is read. The
    # store is refreshed on every Stop, reads only what was appended since, and
    # judges completeness over the union of its snapshots, not over the log as
    # it looks now.
    $L1 = New-SessionStart
    $L2 = New-LlmRequest -NanoAiu 1000000000 -Ts ($T0 + 1000)
    $L3 = New-LlmRequest -NanoAiu 2000000000 -Ts ($T0 + 2000)
    $L4 = New-LlmRequest -NanoAiu 4000000000 -Ts ($T0 + 3000)

    function Set-MainLog([string]$Dir, [string[]]$Lines) {
        [IO.File]::WriteAllText((Join-Path $Dir 'main.jsonl'), (($Lines -join "`n") + "`n"))
    }
    function Get-StoreRows([string]$Store, [string]$Sid = $SID) {
        $p = Join-Path $Store "$Sid.facts.ndjson"
        if (-not (Test-Path $p)) { return @() }
        return @([IO.File]::ReadAllLines($p) | Where-Object { $_.Trim() -and $_ -notmatch '"record":\s*"header"' })
    }
    function Get-StoreState([string]$Store, [string]$Sid = $SID) {
        $p = Join-Path $Store "$Sid.state.json"
        if (-not (Test-Path $p)) { return $null }
        return ([IO.File]::ReadAllText($p) | ConvertFrom-Json)
    }
    function Invoke-Snapshot([string]$Dir, [string]$Store) {
        Invoke-Collector @('--session-dir', $Dir, '--store', $Store, '--snapshot')
    }

    # (a) Appended lines are read once, and only they are read.
    $dir = New-SessionFixture -Main @($L1, $L2)
    $fixtures += $dir
    $store = Join-Path (Split-Path $dir) 'store'
    $r = Invoke-Snapshot $dir $store
    $results['X_snapshot_exit_zero'] = ($r.Code -eq 0)
    $results['X_first_snapshot_rows'] = ((Get-StoreRows $store).Count -eq 1)
    [IO.File]::AppendAllText((Join-Path $dir 'main.jsonl'), "$L3`n")
    $null = Invoke-Snapshot $dir $store
    $results['X_append_adds_only_new'] = ((Get-StoreRows $store).Count -eq 2)
    # The performance claim, measured deterministically: bytes read, not time.
    $st = Get-StoreState $store
    $results['X_reads_only_the_tail'] = ($null -ne $st -and
        [long]$st.logs.'main.jsonl'.last_read_bytes -eq ([Text.Encoding]::UTF8.GetByteCount($L3) + 1))
    $null = Invoke-Snapshot $dir $store
    $st = Get-StoreState $store
    $results['X_repeat_snapshot_idempotent'] = ((Get-StoreRows $store).Count -eq 2 -and
        $null -ne $st -and [long]$st.logs.'main.jsonl'.last_read_bytes -eq 0)

    # (b) The head is cut after a snapshot, but the last line read survives:
    # nothing was lost, so the union is complete and the total is emitted.
    Set-MainLog $dir @($L3, $L4)
    $uf = Join-Path (Split-Path $dir) 'union.ndjson'
    $r = Invoke-Collector @('--session-dir', $dir, '--store', $store, '--facts-out', $uf)
    $results['X_trim_after_snapshot_stays_full'] = ($r.Output -match '(?m)^\s*coverage:\s*full\s*$')
    $results['X_union_total'] = ($r.Output -match '(?m)^\s*credits:\s*7(\.0+)?\s*$' -and
                                 $r.Output -match '(?m)^\s*requests:\s*3\s*$')
    # The workflow artifact is written from the union, not from what is left.
    $results['X_facts_out_from_union'] = ((Test-Path $uf) -and
        @([IO.File]::ReadAllLines($uf) | Where-Object { $_ -match '"record":\s*"fact"|"nano_aiu"' }).Count -eq 3)

    # (c) The cut went past the last line read: what lay between is lost and
    # the store says where, instead of certifying a total.
    $dir = New-SessionFixture -Main @($L1, $L2)
    $fixtures += $dir
    $store = Join-Path (Split-Path $dir) 'store'
    $null = Invoke-Snapshot $dir $store
    Set-MainLog $dir @($L4)
    $r = Invoke-Collector @('--session-dir', $dir, '--store', $store)
    $results['X_gap_flagged'] = ($r.Output -match '(?m)^\s*coverage:\s*gapped\s*$')
    $results['X_gap_withholds_total'] = ($r.Output -match '(?m)^\s*credits:\s*null\s*$')
    $results['X_gap_dated'] = ($r.Output -match "after_ts:\s*$($T0 + 1000)\b" -and
                               $r.Output -match "resumed_ts:\s*$($T0 + 3000)\b")
    # The rows that survived are a lower bound, and labelled as one.
    $results['X_gap_surviving_lower_bound'] = ($r.Output -match
        '(?m)^\s*surviving:\s*\{\s*requests:\s*2,\s*unbilled_requests:\s*0,\s*credits:\s*5(\.0+)?\s*\}')

    # (d) The cut landed inside the last line read: its tail is the first
    # line now. Nothing after it was lost, so this is not a gap.
    $canary = 'SUPERSECRET-STORE-' + ('q' * 400)
    $Lf = New-LlmRequest -NanoAiu 1000000000 -Ts ($T0 + 1000) -SecretText $canary
    $dir = New-SessionFixture -Main @($L1, $Lf)
    $fixtures += $dir
    $store = Join-Path (Split-Path $dir) 'store'
    $null = Invoke-Snapshot $dir $store
    Set-MainLog $dir @($Lf.Substring($Lf.Length - 300), $L3)
    $r = Invoke-Collector @('--session-dir', $dir, '--store', $store)
    $results['X_cut_inside_anchor_is_no_gap'] = ($r.Output -match '(?m)^\s*coverage:\s*full\s*$' -and
                                                 $r.Output -match '(?m)^\s*credits:\s*3(\.0+)?\s*$')
    # The continuity proof keeps hashes, never the line: the line is a prompt.
    $leak = @(Get-ChildItem $store -File | Where-Object { [IO.File]::ReadAllText($_.FullName) -match 'SUPERSECRET' })
    $results['X_store_no_prompt_leak'] = ((Get-ChildItem $store -File).Count -ge 2 -and $leak.Count -eq 0)

    # (e) The head was gone before the first snapshot: a lower bound from the
    # start, dated by the first surviving event.
    $dir = New-SessionFixture -Main @($L2, $L3)
    $fixtures += $dir
    $store = Join-Path (Split-Path $dir) 'store'
    $r = Invoke-Collector @('--session-dir', $dir, '--store', $store)
    $results['X_head_lost_truncated'] = ($r.Output -match '(?m)^\s*coverage:\s*truncated\s*$' -and
                                         $r.Output -match "(?m)^\s*earliest_ts:\s*$($T0 + 1000)\s*$")
    $results['X_head_lost_surviving'] = ($r.Output -match 'surviving:\s*\{\s*requests:\s*2,[^}]*credits:\s*3(\.0+)?\s*\}')

    # (e2) #467: SessionStart hook spans ahead of session_start are the intact head.
    $H1 = New-HookSpan -Ts ($T0 - 600)
    $H2 = New-HookSpan -Ts ($T0 - 300)
    $dir = New-SessionFixture -Main @($H1, $H2, $L1, $L2)
    $fixtures += $dir
    $store = Join-Path (Split-Path $dir) 'store'
    $r = Invoke-Collector @('--session-dir', $dir, '--store', $store)
    $results['X_hook_head_is_full'] = ($r.Output -match '(?m)^\s*coverage:\s*full\s*$' -and
                                       $r.Output -match '(?m)^\s*credits:\s*1(\.0+)?\s*$')

    # A snapshot can land between the hook spans and session_start: the verdict
    # waits for the line that decides it instead of judging the first one.
    $dir = New-SessionFixture -Main @($H1)
    $fixtures += $dir
    $store = Join-Path (Split-Path $dir) 'store'
    $null = Invoke-Snapshot $dir $store
    [IO.File]::AppendAllText((Join-Path $dir 'main.jsonl'), "$H2`n$L1`n$L2`n")
    $r = Invoke-Collector @('--session-dir', $dir, '--store', $store)
    $results['X_hook_head_verdict_waits_across_snapshots'] = ($r.Output -match '(?m)^\s*coverage:\s*full\s*$')

    # Stores written under the old rule carry head_seen false for intact logs.
    # They are re-read, not left withholding forever.
    $dir = New-SessionFixture -Main @($H1, $H2, $L1, $L2)
    $fixtures += $dir
    $store = Join-Path (Split-Path $dir) 'store'
    $null = Invoke-Snapshot $dir $store
    $statePath = Join-Path $store "$SID.state.json"
    $old = [IO.File]::ReadAllText($statePath) | ConvertFrom-Json
    $old.store_version = 1
    $old.head_seen = $false
    $old.earliest_ts = $T0 - 600
    [IO.File]::WriteAllText($statePath, ($old | ConvertTo-Json -Compress -Depth 10))
    $r = Invoke-Collector @('--session-dir', $dir, '--store', $store)
    $results['X_old_store_rejudged'] = ($r.Output -match '(?m)^\s*coverage:\s*full\s*$' -and
                                        $r.Output -match '(?m)^\s*credits:\s*1(\.0+)?\s*$')

    # (f) A line still being written is not consumed: reading it half would
    # either drop it or count it twice once it is complete.
    $dir = New-SessionFixture -Main @($L1)
    $fixtures += $dir
    $store = Join-Path (Split-Path $dir) 'store'
    [IO.File]::AppendAllText((Join-Path $dir 'main.jsonl'), $L2)
    $null = Invoke-Snapshot $dir $store
    $results['X_partial_line_deferred'] = ((Get-StoreRows $store).Count -eq 0)
    [IO.File]::AppendAllText((Join-Path $dir 'main.jsonl'), "`n")
    $null = Invoke-Snapshot $dir $store
    $results['X_partial_line_counted_once'] = ((Get-StoreRows $store).Count -eq 1)

    # (g) Two hooks firing at once must not both append: a fresh lock skips,
    # a stale one (a crashed run) is taken over.
    $dir = New-SessionFixture -Main @($L1, $L2)
    $fixtures += $dir
    $store = Join-Path (Split-Path $dir) 'store'
    New-Item -ItemType Directory -Path $store -Force | Out-Null
    $lock = Join-Path $store "$SID.lock"
    [IO.File]::WriteAllText($lock, 'held')
    $r = Invoke-Snapshot $dir $store
    $results['X_fresh_lock_skips'] = ($r.Code -eq 0 -and (Get-StoreRows $store).Count -eq 0)
    (Get-Item $lock).LastWriteTime = (Get-Date).AddHours(-2)
    $null = Invoke-Snapshot $dir $store
    $results['X_stale_lock_taken_over'] = ((Get-StoreRows $store).Count -eq 1 -and -not (Test-Path $lock))

    # (h) Subagent logs are followed the same way.
    $dir = New-SessionFixture -Main @($L1, $L2) -Child @(
        (New-LlmRequest -Model 'claude-haiku-4.5' -NanoAiu 500000000 -Ts ($T0 + 1500) -DebugName 'tool/runSubagent-implementer')
    )
    $fixtures += $dir
    $store = Join-Path (Split-Path $dir) 'store'
    $null = Invoke-Snapshot $dir $store
    [IO.File]::AppendAllText((Join-Path $dir 'runSubagent-implementer-toolu_test.jsonl'),
        ((New-LlmRequest -Model 'claude-haiku-4.5' -NanoAiu 500000000 -Ts ($T0 + 2500) -DebugName 'tool/runSubagent-implementer') + "`n"))
    $r = Invoke-Collector @('--session-dir', $dir, '--store', $store)
    $results['X_subagent_followed'] = ($r.Output -match '(?m)^\s*credits:\s*2(\.0+)?\s*$' -and
        $r.Output -match 'implementer:\s+totals:\s*\{\s*invocations:\s*1,\s*requests:\s*2\b')

    # (i) The total across sessions: complete sessions sum to a number, the
    # rest only to a lower bound, and the report keeps the two apart.
    $dir = New-SessionFixture -Main @($L1, $L2, $L3)
    $fixtures += $dir
    $store = Join-Path (Split-Path $dir) 'store'
    $null = Invoke-Snapshot $dir $store
    $other = New-SessionFixture -SessionId 'a1b2c3d4-0000-4000-8000-000000000457' -Main @($L4)
    $fixtures += $other
    $null = Invoke-Snapshot $other $store
    $r = Invoke-Collector @('--report', $store)
    $results['X_report_exit_zero'] = ($r.Code -eq 0)
    $results['X_report_sessions'] = ($r.Output -match '(?m)^\s*sessions:\s*2\s*$' -and
                                     $r.Output -match '(?m)^\s*complete:\s*1\s*$')
    $results['X_report_complete_total'] = ($r.Output -match '(?m)^\s*credits_complete:\s*3(\.0+)?\s*$')
    $results['X_report_lower_bound'] = ($r.Output -match '(?m)^\s*credits_lower_bound:\s*7(\.0+)?\s*$')
    # #477: the store report declares its kinds like the block does.
    $reportProbe = @'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("c", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print(json.dumps(getattr(mod, "REPORT_FIELD_KINDS", {})))
'@
    $reportFile = Join-Path ([IO.Path]::GetTempPath()) ("cost-rkinds-" + [Guid]::NewGuid().ToString('N') + '.py')
    Set-Content -LiteralPath $reportFile -Value $reportProbe -Encoding UTF8
    $reportKinds = @()
    try { $reportKinds = @((((& $python $reportFile $collector 2>&1) -join '') | ConvertFrom-Json).PSObject.Properties.Name | Where-Object { $_ }) } catch {}
    Remove-Item $reportFile -Force -ErrorAction SilentlyContinue
    $reportFields = @([regex]::Matches($r.Output, '(?m)^  ([a-z_]+):') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $results['X_report_every_field_declares_a_kind'] = ($reportFields.Count -ge 8 -and
        @($reportFields | Where-Object { $reportKinds -notcontains $_ }).Count -eq 0)
    $results['X_report_names_lower_bounds'] = ($r.Output -match
        '(?m)^  kinds: .*lower_bound: \[credits_lower_bound, requests, unbilled_requests, by_model\]')
    # #479: the floor (first request of a complete session) is a direct measure
    # of what an empty turn reads; only `full` sessions vouch for their first request.
    $results['X_report_context_floor'] = ($r.Output -match
        '(?m)^  context_floor: \{ sessions: 1, min: 1000, median: 1000, max: 1000 \}\s*$' -and
        $r.Output -match '(?m)^  kinds: .*context_floor: first-request')

    # (j) Withheld is not zero (#457): with the totals withheld, the splits say
    # so instead of printing an empty map that reads as "cost nothing".
    $dir = New-SessionFixture -Main @($L2, $L3)
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['X_by_model_withheld_null'] = ($r.Output -match '(?m)^\s*by_model:\s*null\s*$')
    $results['X_by_purpose_withheld_null'] = ($r.Output -match '(?m)^\s*by_purpose:\s*null\s*$')
    $results['X_surviving_without_store'] = ($r.Output -match 'surviving:\s*\{\s*requests:\s*2,[^}]*credits:\s*3(\.0+)?\s*\}')
    # Control: a complete log carries no lower bound -- it has the total.
    $dir = New-SessionFixture -Main @($L1, $L2)
    $fixtures += $dir
    $r = Invoke-Collector @('--session-dir', $dir)
    $results['X_full_has_no_surviving'] = ($r.Output -match '(?m)^\s*coverage:\s*full\s*$' -and
                                           $r.Output -notmatch 'surviving:')
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
