# Contract tests for the native payload adapter (_native_adapter.py, #566).
#
# A `version: 1` hook registration hands AF hooks a camelCase payload
# (toolName / toolArgs / sessionId). Every AF policy reads snake_case, so fed
# that payload directly each one returns `{}` -- a success-shaped no-op. The
# adapter must translate the recorded camelCase shapes into the snake_case
# shape the PascalCase registration delivers, and fail visibly on what it
# cannot translate. The policy cases run the real hooks, not stubs.
# Run from anywhere:
#   powershell -File .github/scripts/test-native-adapter.ps1
$ErrorActionPreference = 'Continue'

$scriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptDir '_suite_env.ps1')
$hooksDir = (Resolve-Path (Join-Path $scriptDir '..\hooks\scripts')).Path
$adapter = Join-Path $hooksDir '_native_adapter.py'
$payloadRoot = Split-Path (Split-Path $scriptDir)
$python = Get-AfSuitePython -ScriptsDir $scriptDir
if (-not $python) { Write-Host 'FAIL python -- no Python 3 interpreter for the adapter'; exit 1 }

$results = [ordered]@{}
$work = Join-Path ([IO.Path]::GetTempPath()) ("af-native-adapter-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $work | Out-Null

# Echo target: returns exactly the stdin it was given, so a case can inspect
# what the adapter handed on.
$echo = Join-Path $work 'echo_target.py'
Set-Content -Path $echo -Encoding ascii -Value 'import sys; sys.stdout.buffer.write(sys.stdin.buffer.read())'

function Invoke-Adapter([string]$event, [string]$stdin, [string[]]$target) {
    $inFile = Join-Path $work 'in.json'; $outFile = Join-Path $work 'out.txt'; $errFile = Join-Path $work 'err.txt'
    [IO.File]::WriteAllText($inFile, $stdin, [Text.UTF8Encoding]::new($false))
    $argList = @($adapter, $event, '--') + $target
    Push-Location $payloadRoot
    try {
        $p = Start-Process -FilePath $python -ArgumentList ($argList | ForEach-Object { '"' + $_ + '"' }) -NoNewWindow -Wait -PassThru `
            -RedirectStandardInput $inFile -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    } finally { Pop-Location }
    return [pscustomobject]@{
        Out  = [IO.File]::ReadAllText($outFile).Trim()
        Err  = [IO.File]::ReadAllText($errFile)
        Code = $p.ExitCode
    }
}

function Get-Json([string]$text) { try { return ($text | ConvertFrom-Json) } catch { return $null } }
$ps = @('powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File')
$blockDangerous = $ps + @((Join-Path $hooksDir 'block-dangerous.ps1'))
$scanSecrets = @($python, (Join-Path $hooksDir 'scan-secrets.py'))
$echoTarget = @($python, $echo)

# Assembled at run time: the literal would trip the very gate under test.
$forcePush = 'git push --' + 'force origin ma' + 'in'

# Recorded shape, Copilot harness, `version: 1` preToolUse (#447).
function New-CamelPre($toolName, $toolArgs) {
    return (@{ sessionId = 's-566'; timestamp = 1794413978762; cwd = $payloadRoot; toolCallId = 'call_566'
            toolName = $toolName; toolArgs = $toolArgs } | ConvertTo-Json -Compress -Depth 6)
}

# A: a hard-denied shell command reaches block-dangerous and is denied, in the
#    top-level form a version-1 registration honours.
$r = Invoke-Adapter 'preToolUse' (New-CamelPre 'powershell' @{ command = $forcePush; description = 'x' }) $blockDangerous
$j = Get-Json $r.Out
$results['A_camel_force_push_denied_top_level'] = ($j -and $j.permissionDecision -eq 'deny' -and $j.permissionDecisionReason -match 'force push')

# A2: the snake_case control gives the same verdict through the adapter.
$snake = @{ session_id = 's-566'; timestamp = 1; cwd = $payloadRoot; tool_use_id = 'c'; hook_event_name = 'PreToolUse'
    tool_name = 'powershell'; tool_input = @{ command = $forcePush; description = 'x' } } | ConvertTo-Json -Compress -Depth 6
$r = Invoke-Adapter 'PreToolUse' $snake $blockDangerous
$j = Get-Json $r.Out
$results['A2_snake_control_denied'] = ($j -and $j.permissionDecision -eq 'deny')

# B: a harmless command stays silent -- the adapter adds no verdict of its own.
$r = Invoke-Adapter 'preToolUse' (New-CamelPre 'powershell' @{ command = 'Write-Output ok'; description = 'x' }) $blockDangerous
$results['B_harmless_still_empty'] = ($r.Out -eq '{}' -and $r.Code -eq 0)

# C: snake_case input passes through byte-equal.
$r = Invoke-Adapter 'PreToolUse' $snake $echoTarget
$results['C_snake_passthrough_byte_equal'] = ($r.Out -ceq $snake)

# D: camelCase becomes the snake_case shape the PascalCase registration delivers.
$r = Invoke-Adapter 'preToolUse' (New-CamelPre 'powershell' @{ command = 'x' }) $echoTarget
$j = Get-Json $r.Out
$results['D_tool_name_mapped'] = ($j -and $j.tool_name -eq 'powershell' -and $j.tool_input.command -eq 'x')
$results['D_ids_mapped'] = ($j -and $j.session_id -eq 's-566' -and $j.tool_use_id -eq 'call_566' -and $j.hook_event_name -eq 'PreToolUse')
$results['D_no_camel_keys_left'] = ($j -and -not ($j.PSObject.Properties.Name | Where-Object { $_ -cmatch '[a-z][A-Z]' }))

# E: a patch string (apply_patch arrives as a string) stays a string.
$patch = "*** Begin Patch`n*** Update File: src/x.py`n@@`n+y`n*** End Patch`n"
$r = Invoke-Adapter 'preToolUse' (New-CamelPre 'Edit' $patch) $echoTarget
$j = Get-Json $r.Out
$results['E_patch_string_kept'] = ($j -and $j.tool_input -is [string] -and $j.tool_input -ceq $patch)

# F: what cannot be translated is refused on preToolUse, naming the adapter.
$r = Invoke-Adapter 'preToolUse' 'not json at all' $echoTarget
$j = Get-Json $r.Out
$results['F_garbage_denied'] = ($j -and $j.permissionDecision -eq 'deny' -and $j.permissionDecisionReason -match 'native adapter')
$r = Invoke-Adapter 'preToolUse' '{"sessionId":"s","toolArgs":{"command":"x"}}' $echoTarget
$j = Get-Json $r.Out
$results['F_missing_tool_name_denied'] = ($j -and $j.permissionDecision -eq 'deny' -and $j.permissionDecisionReason -match 'native adapter')

# G: a secret written through the native `create` tool is flagged by
#    scan-secrets exactly as the snake_case control is.
$secretFile = Join-Path $work 'config.py'
Set-Content -Path $secretFile -Encoding ascii -Value (Get-AfSecretFixture password)
$camelPost = @{ sessionId = 's-566'; timestamp = 1; cwd = $payloadRoot; toolCallId = 'c'; toolName = 'create'
    toolArgs = @{ path = $secretFile; file_text = 'x' }; toolResult = @{ resultType = 'success'; textResultForLlm = 'Created' } } | ConvertTo-Json -Compress -Depth 6
$snakePost = @{ session_id = 's-566'; timestamp = 1; cwd = $payloadRoot; tool_use_id = 'c'; hook_event_name = 'PostToolUse'; tool_name = 'create'
    tool_input = @{ path = $secretFile; file_text = 'x' }; tool_result = @{ result_type = 'success'; text_result_for_llm = 'Created' } } | ConvertTo-Json -Compress -Depth 6
$rc = Invoke-Adapter 'postToolUse' $camelPost $scanSecrets
$rs = Invoke-Adapter 'PostToolUse' $snakePost $scanSecrets
$jc = Get-Json $rc.Out; $js = Get-Json $rs.Out
$results['G_snake_control_flags_secret'] = ($js -and $js.decision -eq 'block')
$results['G_camel_flags_secret_same'] = ($jc -and $jc.decision -eq 'block' -and $jc.additionalContext -eq $js.additionalContext)

# H: the tool result keeps the shape the PascalCase registration delivers.
$r = Invoke-Adapter 'postToolUse' $camelPost $echoTarget
$j = Get-Json $r.Out
$results['H_tool_result_snake'] = ($j -and $j.tool_result.text_result_for_llm -eq 'Created' -and $j.tool_result.result_type -eq 'success' -and $j.hook_event_name -eq 'PostToolUse')

# I: subagent and stop identity fields are renamed, never guessed.
$camelStop = '{"sessionId":"s","timestamp":1,"cwd":"x","agentId":"a1","agentType":"implementer","parentAgentId":"p","stopReason":"end_turn","stop_hook_active":false,"transcriptPath":"t"}'
$r = Invoke-Adapter 'subagentStop' $camelStop $echoTarget
$j = Get-Json $r.Out
$results['I_identity_renamed'] = ($j -and $j.agent_id -eq 'a1' -and $j.agent_type -eq 'implementer' -and $j.parent_agent_id -eq 'p' -and $j.stop_reason -eq 'end_turn' -and $j.transcript_path -eq 't' -and $j.hook_event_name -eq 'SubagentStop')

# J: a verdict nested under hookSpecificOutput is lifted to the top level.
$nested = Join-Path $work 'nested_target.py'
Set-Content -Path $nested -Encoding ascii -Value 'import sys,json; sys.stdin.read(); print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"why","additionalContext":"ctx"}}))'
$r = Invoke-Adapter 'preToolUse' (New-CamelPre 'powershell' @{ command = 'x' }) @($python, $nested)
$j = Get-Json $r.Out
$results['J_verdict_lifted'] = ($j -and $j.permissionDecision -eq 'ask' -and $j.permissionDecisionReason -eq 'why' -and $j.additionalContext -eq 'ctx' -and $j.hookSpecificOutput.permissionDecision -eq 'ask')

# K: the target's exit code and stderr reach the host unchanged.
$fail = Join-Path $work 'fail_target.py'
Set-Content -Path $fail -Encoding ascii -Value 'import sys; sys.stdin.read(); sys.stderr.write("boom-566"); sys.exit(3)'
$r = Invoke-Adapter 'postToolUse' $camelPost @($python, $fail)
$results['K_exit_code_propagated'] = ($r.Code -eq 3)
$results['K_stderr_propagated'] = ($r.Err -match 'boom-566')

# L: a target that cannot start is a refusal on preToolUse, not a silent pass.
$r = Invoke-Adapter 'preToolUse' (New-CamelPre 'powershell' @{ command = 'x' }) @((Join-Path $work 'does-not-exist.exe'))
$j = Get-Json $r.Out
$results['L_missing_target_denied'] = ($j -and $j.permissionDecision -eq 'deny' -and $j.permissionDecisionReason -match 'native adapter')

# M: an unknown event name is a registration error -- non-zero, named.
$r = Invoke-Adapter 'preToolUseTypo' (New-CamelPre 'powershell' @{ command = 'x' }) $echoTarget
$results['M_unknown_event_fails'] = ($r.Code -ne 0 -and $r.Err -match 'preToolUseTypo')

# N: the deployed registration is untouched by this slice.
$registration = Get-Content (Join-Path $payloadRoot '.github\hooks\agent-hooks.json') -Raw
$results['N_registration_unchanged'] = ($registration -notmatch '_native_adapter')

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue

Write-Host '===== native payload adapter tests ====='
$allPass = $true
foreach ($k in $results.Keys) {
    if (-not $results[$k]) { $allPass = $false }
    Write-Host ("  {0,-38} {1}" -f $k, $(if ($results[$k]) { 'PASS' } else { 'FAIL' }))
}
Write-Host '========================================'
if ($allPass) { Write-Host 'RESULT: ALL GREEN'; exit 0 }
else { Write-Host 'RESULT: FAILURES PRESENT'; exit 1 }
