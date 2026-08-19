# Regression tests for the planner's write-scope gate (planner-pretooluse.ps1).
#
# Issue #130 widened the write surface of an agent that could not previously
# touch the repository. The tool list is not what holds that open door shut --
# this gate is -- so the case that matters most here is the one that TRIES to
# write outside the plan directory and must be refused.
# Run from anywhere:
#   pwsh .github/scripts/test-planner-write-scope.ps1
$ErrorActionPreference = 'Continue'

$scriptDir = Split-Path -Parent $PSCommandPath
$hook = (Resolve-Path (Join-Path $scriptDir '..' | Join-Path -ChildPath 'hooks/scripts/planner-pretooluse.ps1')).Path

function Invoke-Hook([string]$json) {
    $out = $json | powershell -NoProfile -ExecutionPolicy Bypass -File $hook 2>&1 | Out-String
    return $out.Trim()
}

function New-Payload([string]$tool, [string]$path) {
    return (@{ tool_name = $tool; tool_input = @{ filePath = $path } } | ConvertTo-Json -Compress -Depth 4)
}

function Test-Denied([string]$out) { return $out -match '"permissionDecision":"deny"' }
function Test-Allowed([string]$out) { return $out -eq '{}' }

$results = [ordered]@{}

# A: the write the planner exists to make.
$results['A_plan_md_allowed'] = Test-Allowed (Invoke-Hook (New-Payload 'create_file' 'docs/plans/feat-2026-08-18-x.md'))

# B: a project that keeps plans elsewhere is not locked out of planning --
#    `plans` as a segment is the same rule check-plan-budget.py applies.
$results['B_other_plans_dir_allowed'] = Test-Allowed (Invoke-Hook (New-Payload 'create_file' 'planning/plans/fix-2026-08-18-y.md'))

# C: production code. The whole point of the gate.
$results['C_src_denied']    = Test-Denied (Invoke-Hook (New-Payload 'create_file' 'src/mpusage/helper.py'))
$results['C_test_denied']   = Test-Denied (Invoke-Hook (New-Payload 'create_file' 'tests/test_helper.py'))
$results['C_reason_named']  = (Invoke-Hook (New-Payload 'create_file' 'src/mpusage/helper.py')) -match 'src/mpusage/helper.py'

# D: the framework's own configuration is not a plan.
$results['D_agent_file_denied']   = Test-Denied (Invoke-Hook (New-Payload 'create_file' '.github/agents/implementer.agent.md'))
$results['D_hook_denied']         = Test-Denied (Invoke-Hook (New-Payload 'create_file' '.github/hooks/scripts/evil.ps1'))
$results['D_af_env_denied']       = Test-Denied (Invoke-Hook (New-Payload 'create_file' '.github/af-env.conf'))

# E: a markdown file that is not in a plans directory is still not a plan.
$results['E_readme_denied']       = Test-Denied (Invoke-Hook (New-Payload 'create_file' 'README.md'))
$results['E_docs_md_denied']      = Test-Denied (Invoke-Hook (New-Payload 'create_file' 'docs/architecture.md'))

# F: a non-markdown file inside the plan directory is not a plan either --
#    otherwise `docs/plans/payload.ps1` would be a way out.
$results['F_script_in_plans_denied'] = Test-Denied (Invoke-Hook (New-Payload 'create_file' 'docs/plans/payload.ps1'))

# G: traversal. `../../elsewhere/plans/x.md` resolves to a real path with a
#    real `plans` segment, so shape alone would clear it.
$results['G_traversal_denied']  = Test-Denied (Invoke-Hook (New-Payload 'create_file' '../../elsewhere/plans/x.md'))
$results['G_absolute_denied']   = Test-Denied (Invoke-Hook (New-Payload 'create_file' 'C:/Windows/Temp/plans/x.md'))

# H: a batch edit is checked path by path. One bad path among good ones is
#    still a bad write -- and this is the shape that made a gate inert in #64.
$batch = @{
    tool_name  = 'multi_replace_string_in_file'
    tool_input = @{ replacements = @(
        @{ filePath = 'docs/plans/feat-2026-08-18-x.md' },
        @{ filePath = 'src/mpusage/helper.py' }
    ) }
} | ConvertTo-Json -Compress -Depth 5
$results['H_batch_smuggle_denied'] = Test-Denied (Invoke-Hook $batch)

$batchClean = @{
    tool_name  = 'multi_replace_string_in_file'
    tool_input = @{ replacements = @(@{ filePath = 'docs/plans/feat-2026-08-18-x.md' }) }
} | ConvertTo-Json -Compress -Depth 5
$results['H_batch_clean_allowed'] = Test-Allowed (Invoke-Hook $batchClean)

# I: a write tool naming no path cannot be cleared, so it is refused. A gate
#    that fails open on an unrecognised payload is the failure it exists to stop.
$results['I_pathless_write_denied'] = Test-Denied (Invoke-Hook (@{
    tool_name = 'create_file'; tool_input = @{ content = 'x' }
} | ConvertTo-Json -Compress -Depth 4))

# J: reading is untouched. A gate that also blocked the planner's own research
#    would make the agent useless.
$results['J_read_allowed']   = Test-Allowed (Invoke-Hook (New-Payload 'read_file' 'src/mpusage/helper.py'))
$results['J_search_allowed'] = Test-Allowed (Invoke-Hook (@{
    tool_name = 'grep_search'; tool_input = @{ query = 'x' }
} | ConvertTo-Json -Compress -Depth 4))

# K: a write tool this gate has never heard of is still a write. Test-AfWriteTool
#    matches on verb + noun so an unknown tool does not fail open (#69).
$results['K_unknown_write_tool_denied'] = Test-Denied (Invoke-Hook (New-Payload 'apply_patch_to_file' 'src/mpusage/helper.py'))

# L: malformed stdin is not a write to allow or deny -- it is not a write.
$results['L_garbage_stdin_silent'] = Test-Allowed (Invoke-Hook 'not json at all')

Write-Host '===== planner write-scope tests ====='
$allPass = $true
foreach ($k in $results.Keys) {
    if (-not $results[$k]) { $allPass = $false }
    Write-Host ("  {0,-32} {1}" -f $k, $(if ($results[$k]) { 'PASS' } else { 'FAIL' }))
}
Write-Host '====================================='
if ($allPass) { Write-Host 'RESULT: ALL GREEN'; exit 0 }
else { Write-Host 'RESULT: FAILURES PRESENT'; exit 1 }
