# Regression tests for the ADO MCP tool-id guard (check-mcp-tool-ids.py, #550).
#
# In the Copilot harness a subagent's `tools:` grant resolves only as
# `<server name>/<tool>`, where the server name is the key in .vscode/mcp.json.
# The ADO agents granted `microsoft/azure-devops-mcp/<tool>`, which names no
# configured server: all four ran with no ADO tools and reported BLOCKED
# (measured in #447). With `ado-remote-mcp/<tool>` the worker read a work item.
# The guard now flags the old prefix next to the legacy tool ids it already knew.
#
# Run from anywhere:
#   powershell -File .github/scripts/test-mcp-tool-ids.ps1
# Exits non-zero if any scenario fails (CI-friendly).
$ErrorActionPreference = 'Continue'

$scriptDir = Split-Path -Parent $PSCommandPath
$githubDir = (Resolve-Path (Join-Path $scriptDir '..')).Path
$checker = Join-Path $scriptDir 'check-mcp-tool-ids.py'

. (Join-Path $scriptDir '_suite_env.ps1')
$python = @(Get-AfSuitePython $scriptDir)
if ($python.Count -eq 0 -or -not $python[0]) {
    Write-Host 'SKIP: no Python 3 interpreter found; cannot run MCP tool-id tests.'
    exit 0
}
$pyExe = $python[0]
$pyPre = if ($python.Count -gt 1) { $python[1..($python.Count - 1)] } else { @() }

$results = [ordered]@{}
$details = [ordered]@{}
$fixtures = @()

function New-Fixture([string]$AgentText) {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("af550 fixture " + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path (Join-Path $dir 'agents') -Force | Out-Null
    $clean = $AgentText -replace "`r", ''
    [System.IO.File]::WriteAllText((Join-Path $dir 'agents/x.agent.md'), $clean, (New-Object System.Text.UTF8Encoding($false)))
    $script:fixtures += $dir
    return $dir
}

function Invoke-Checker([string]$Root) {
    $out = & $pyExe @pyPre $checker --root $Root 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}

function Add-Result([string]$Name, [bool]$Pass, [string]$Detail) {
    $script:results[$Name] = $Pass
    $script:details[$Name] = $Detail
}

try {
    $dir = New-Fixture "---`nname: x`ntools:`n  - microsoft/azure-devops-mcp/wit_work_item`n---`nBody.`n"
    $r = Invoke-Checker $dir
    Add-Result 'P1_the_unresolvable_server_prefix_fails' ($r.Code -eq 1 -and $r.Out -match 'ado-remote-mcp/wit_work_item') "exit $($r.Code): $($r.Out)"

    # The readiness hook parses "<n> legacy" from the quiet summary.
    $q = & $pyExe @pyPre $checker --root $dir --quiet 2>&1 | Out-String
    Add-Result 'P2_the_prefix_counts_in_the_readiness_summary' ($q -match '\b1 legacy') "out: $q"

    $dir = New-Fixture "---`nname: x`ntools:`n  - ado-remote-mcp/wit_work_item`n---`nThe azure-devops-mcp default toolset; package @azure-devops/mcp.`n"
    $r = Invoke-Checker $dir
    Add-Result 'P3_the_resolvable_prefix_and_package_prose_pass' ($r.Code -eq 0) "exit $($r.Code): $($r.Out)"

    $dir = New-Fixture "---`nname: x`ntools:`n  - ado-remote-mcp/wit_get_work_item`n---`n"
    $r = Invoke-Checker $dir
    Add-Result 'P4_a_legacy_tool_id_still_fails' ($r.Code -eq 1 -and $r.Out -match 'wit_work_item \(action `get`\)') "exit $($r.Code): $($r.Out)"

    $r = Invoke-Checker $githubDir
    Add-Result 'P5_the_shipped_payload_passes' ($r.Code -eq 0) "exit $($r.Code): $($r.Out)"

    $agents = @('ado-work-item-manager', 'ado-wiki-manager', 'ado-pr-manager', 'ado-pipeline-manager')
    $bad = @()
    foreach ($a in $agents) {
        $text = Get-Content (Join-Path $githubDir "agents/$a.agent.md") -Raw
        if ($text -notmatch '(?m)^\s+-\s+ado-remote-mcp/\w+') { $bad += $a }
    }
    Add-Result 'P6_every_ado_worker_grants_ado_remote_mcp_tools' ($bad.Count -eq 0) "without ado-remote-mcp/ grants: $($bad -join ', ')"
}
finally {
    foreach ($f in $fixtures) { Remove-Item $f -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host '===== MCP tool-id guard tests (#550) ====='
$allPass = $true
foreach ($k in $results.Keys) {
    if ($results[$k]) {
        Write-Host ("PASS  {0}" -f $k)
    } else {
        $allPass = $false
        Write-Host ("FAIL  {0}" -f $k)
        if ($details[$k]) { Write-Host ("      {0}" -f $details[$k]) }
    }
}
$passCount = @($results.Values | Where-Object { $_ }).Count
Write-Host ("----- {0}/{1} passed -----" -f $passCount, $results.Count)
if (-not $allPass) { exit 1 }
exit 0
