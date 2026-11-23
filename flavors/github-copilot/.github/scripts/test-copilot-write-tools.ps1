# Regression suite: Copilot-harness write tools are writes (#564).
#
# Every write gate starts with "is this a write?" and answers it from a list of
# tool names read out of Local-harness payloads (#69). Under the Copilot harness
# the model's file tools arrive under other names, and the answer was "no" --
# so plan confinement, test-only writes, the trust-store deny and the secret
# scan all returned {} for every write. {} is also what an approving gate says,
# which is why nothing looked wrong.
#
# The fixture below is the captured payload, not a guess: a native apply_patch
# call reached a PascalCase PreToolUse hook as tool_name "Edit" with the patch
# as a bare STRING in tool_input. A string carries no filePath, so recognising
# the name alone would still leave every path-based gate with nothing to judge.
#
# Four implementations answer the question (_common.ps1, _common.sh,
# scan-secrets.py, _agentlog.py). Each is asked here, because the defect this
# guards against is one of them drifting from the others.

# No StrictMode: _common.ps1 is dot-sourced, and the hooks never run strict.
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir '_suite_env.ps1')
$hookScripts = Join-Path (Split-Path -Parent $scriptDir) 'hooks/scripts'
# _common probes python3 on load; the Windows Store stub writes to stderr, which 'Stop' would make fatal.
$ErrorActionPreference = 'Continue'
. (Join-Path $hookScripts '_common.ps1')
$ErrorActionPreference = 'Stop'

$results = [ordered]@{}
$details = @{}
function Add-Result {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    $script:results[$Name] = $Ok
    $script:details[$Name] = $Detail
}

$python = Get-AfSuitePython -ScriptsDir $scriptDir
$bashExe = $null
$bashCmd = Get-Command bash -ErrorAction SilentlyContinue
if ($bashCmd) { $bashExe = $bashCmd.Source }
if (-not $bashExe -and (Test-Path 'C:/Program Files/Git/bin/bash.exe')) { $bashExe = 'C:/Program Files/Git/bin/bash.exe' }

$writeNames = @('Edit', 'Write', 'create', 'edit', 'apply_patch')
$readNames = @('Read', 'view', 'Grep', 'Glob', 'Bash', 'powershell')

function New-Patch([string[]]$Lines) { return ((@('*** Begin Patch') + $Lines + @('*** End Patch')) -join "`n") + "`n" }

# Captured shape (#564), with the absolute path replaced.
$capturedPatch = New-Patch @('*** Update File: docs/plans/feat-x.md', '@@', ' beta', '+gamma')
$multiPatch = New-Patch @(
    '*** Add File: docs/plans/a.md', '+a',
    '*** Update File: src/domain/b.py', '*** Move to: src/domain/c.py', '@@', '-x', '+y',
    '*** Delete File: src/domain/d.py',
    '*** Update File: docs/plans/a.md', '@@', '+again'
)
$multiExpected = 'docs/plans/a.md|src/domain/b.py|src/domain/c.py|src/domain/d.py'

# --- N: names --------------------------------------------------------------
$psWrong = @($writeNames | Where-Object { -not (Test-AfWriteTool $_) }) + @($readNames | Where-Object { Test-AfWriteTool $_ })
Add-Result 'N1_ps_names' ($psWrong.Count -eq 0) "misjudged: $($psWrong -join ', ')"

$pyNames = @"
import importlib.util, sys
sys.path.insert(0, sys.argv[1])
def load(name, file):
    spec = importlib.util.spec_from_file_location(name, file)
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); return mod
scan = load('scan_secrets', sys.argv[1] + '/scan-secrets.py')
log = load('agentlog', sys.argv[1] + '/_agentlog.py')
writes, reads = sys.argv[2].split(','), sys.argv[3].split(',')
bad = [n for n in writes if not scan.is_write_tool(n)] + [n for n in reads if scan.is_write_tool(n)]
bad += ['log:' + n for n in writes if not log.is_edit_tool(n)] + ['log:' + n for n in reads if log.is_edit_tool(n)]
print(','.join(bad))
"@
if ($python) {
    $out = (& $python -c $pyNames $hookScripts ($writeNames -join ',') ($readNames -join ',') 2>&1 | Out-String).Trim()
    Add-Result 'N2_py_names' ($LASTEXITCODE -eq 0 -and $out -eq '') "misjudged: $out"
} else { Write-Output '  SKIP  N2_py_names -- no Python 3' }

$shCommon = (Join-Path $hookScripts '_common.sh') -replace '\\', '/'
if ($bashExe) {
    $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $shProbe = "source '$shCommon'; for n in $($writeNames -join ' '); do af_is_write_tool `"`$n`" || echo `"`$n`"; done; for n in $($readNames -join ' '); do af_is_write_tool `"`$n`" && echo `"`$n`"; done; true"
    $out = (& $bashExe -c $shProbe 2>&1 | Out-String).Trim()
    $ErrorActionPreference = $prevEap
    Add-Result 'N3_sh_names' ($out -eq '') "misjudged: $out"
} else { Write-Output '  SKIP  N3_sh_names -- no bash on this host' }

# --- P: paths out of a patch string ----------------------------------------
$psPaths = (@(Get-AfWritePaths $multiPatch) -join '|')
Add-Result 'P1_ps_patch_string' ($psPaths -eq $multiExpected) "got: $psPaths"
$psLocal = (@(Get-AfWritePaths ([pscustomobject]@{ input = $capturedPatch; explanation = 'x' })) -join '|')
Add-Result 'P2_ps_patch_in_input_key' ($psLocal -eq 'docs/plans/feat-x.md') "got: $psLocal"
$psNative = (@(Get-AfWritePaths ([pscustomobject]@{ path = 'src/domain/e.py'; old_str = 'a'; new_str = 'b' })) -join '|')
Add-Result 'P3_ps_native_edit_path' ($psNative -eq 'src/domain/e.py') "got: $psNative"

$pyPaths = @"
import importlib.util, json, sys
sys.path.insert(0, sys.argv[1])
spec = importlib.util.spec_from_file_location('scan_secrets', sys.argv[1] + '/scan-secrets.py')
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
for raw in sys.stdin.read().split('\x1e'):
    print('|'.join(mod.write_paths(json.loads(raw))))
"@
if ($python) {
    $inputs = @(
        ($multiPatch | ConvertTo-Json -Compress),
        (@{ input = $capturedPatch; explanation = 'x' } | ConvertTo-Json -Compress)
    ) -join [char]0x1e
    $out = @(($inputs | & $python -c $pyPaths $hookScripts 2>&1 | Out-String).Trim() -split "`r?`n")
    Add-Result 'P4_py_patch_paths' ($out.Count -eq 2 -and $out[0] -eq $multiExpected -and $out[1] -eq 'docs/plans/feat-x.md') "got: $($out -join ' / ')"
} else { Write-Output '  SKIP  P4_py_patch_paths -- no Python 3' }

if ($bashExe -and $python) {
    $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $payload = @{ tool_name = 'Edit'; tool_input = $multiPatch } | ConvertTo-Json -Compress
    $out = (($payload | & $bashExe -c "source '$shCommon'; af_write_paths") 2>&1 | Out-String).Trim() -replace "`r?`n", '|'
    $ErrorActionPreference = $prevEap
    Add-Result 'P5_sh_patch_paths' ($out -eq $multiExpected) "got: $out"
} else { Write-Output '  SKIP  P5_sh_patch_paths -- no bash or no Python 3' }

# --- E: the gates, end to end ----------------------------------------------
function Invoke-PsHook([string]$Hook, [string]$Json) {
    $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = ($Json | powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $hookScripts $Hook) 2>&1 | Out-String).Trim()
    $ErrorActionPreference = $prevEap
    return $out
}
function Invoke-ShHook([string]$Hook, [string]$Json) {
    $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = ($Json | & $bashExe ((Join-Path $hookScripts $Hook) -replace '\\', '/') 2>&1 | Out-String).Trim()
    $ErrorActionPreference = $prevEap
    return $out
}
function Test-Deny([string]$Out) { return $Out -match '"permissionDecision"\s*:\s*"deny"' }

$srcPatch = @{ hook_event_name = 'PreToolUse'; tool_name = 'Edit'; tool_input = (New-Patch @('*** Add File: src/domain/x.py', '+print(1)')) } | ConvertTo-Json -Compress
$planPatch = @{ hook_event_name = 'PreToolUse'; tool_name = 'Edit'; tool_input = $capturedPatch } | ConvertTo-Json -Compress
$nativeCreate = @{ hook_event_name = 'PreToolUse'; tool_name = 'create'; tool_input = @{ path = 'src/domain/x.py'; file_text = 'print(1)' } } | ConvertTo-Json -Compress

$o = Invoke-PsHook 'planner-pretooluse.ps1' $srcPatch;    Add-Result 'E1_ps_planner_patch_src_denied' (Test-Deny $o) $o
$o = Invoke-PsHook 'planner-pretooluse.ps1' $planPatch;   Add-Result 'E2_ps_planner_patch_plan_allowed' ($o -eq '{}') $o
$o = Invoke-PsHook 'planner-pretooluse.ps1' $nativeCreate; Add-Result 'E3_ps_planner_native_create_denied' (Test-Deny $o) $o
if ($bashExe -and $python) {
    $o = Invoke-ShHook 'planner-pretooluse.sh' $srcPatch;  Add-Result 'E4_sh_planner_patch_src_denied' (Test-Deny $o) $o
    $o = Invoke-ShHook 'planner-pretooluse.sh' $planPatch; Add-Result 'E5_sh_planner_patch_plan_allowed' ($o -eq '{}') $o
} else { Write-Output '  SKIP  E4/E5 sh planner -- no bash or no Python 3' }

# The secret scan runs after the write and reads the file the patch names.
if ($python) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("af564-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        $secretFile = Join-Path $tmp 'settings.py'
        [IO.File]::WriteAllText($secretFile, (Get-AfSecretFixture 'password') + "`n")
        $post = @{ hook_event_name = 'PostToolUse'; tool_name = 'Edit'; tool_input = (New-Patch @("*** Add File: $secretFile", '+x')) } | ConvertTo-Json -Compress
        $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $o = ($post | & $python (Join-Path $hookScripts 'scan-secrets.py') 2>&1 | Out-String).Trim()
        $ErrorActionPreference = $prevEap
        Add-Result 'E6_secret_scan_patch_blocks' ($o -match '"decision"\s*:\s*"block"') $o
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
} else { Write-Output '  SKIP  E6_secret_scan_patch_blocks -- no Python 3' }

Write-Output '===== copilot write-tool tests (#564) ====='
$allPass = $true
foreach ($k in $results.Keys) {
    if (-not $results[$k]) { $allPass = $false }
    $line = '  {0,-38} {1}' -f $k, $(if ($results[$k]) { 'PASS' } else { 'FAIL' })
    if (-not $results[$k] -and $details[$k]) { $line += " -- $($details[$k])" }
    Write-Output $line
}
Write-Output '==========================================='
if ($allPass) { Write-Output 'RESULT: ALL GREEN'; exit 0 }
Write-Output 'RESULT: FAILURES PRESENT'; exit 1
