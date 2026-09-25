# Regression suite: an agent cannot create an unowned ADO work item (#36).
#
# Unowned items fall off the board. They kept appearing -- 6 of 7 in one run --
# because ownership was neither configurable nor checked: it depended on the
# agent remembering. A reminder in prose is the mechanism that failed, so the
# check lives in the PreToolUse hook, the one event both harnesses let deny.
#
# add_child is refused outright: its MCP schema has no assignee field, so every
# child it creates is unowned by construction, whatever the agent intends.
#
# The gate is not a separately registered hook. The Local harness ignores
# matchers and runs every PreToolUse hook on every tool call, so a new one
# would cost a PowerShell start on each call. It rides in block-dangerous.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ghDir = Split-Path -Parent $scriptDir
$hookScripts = Join-Path $ghDir 'hooks/scripts'
$psHook = Join-Path $hookScripts 'block-dangerous.ps1'
$shHook = Join-Path $hookScripts 'block-dangerous.sh'
$shippedConf = Join-Path $ghDir 'af-env.conf'
$agentFile = Join-Path $ghDir 'agents/ado-work-item-manager.agent.md'

$results = [ordered]@{}
$details = [ordered]@{}

function Add-Result([string]$Name, [bool]$Ok, [string]$Detail) {
    $script:results[$Name] = $Ok
    $script:details[$Name] = $Detail
}

$fixture = Join-Path ([IO.Path]::GetTempPath()) ("af36-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
$owner = 'Test Owner <owner@example.com>'
$confWithOwner = Join-Path $fixture 'with-owner.conf'
$confWithout = Join-Path $fixture 'without-owner.conf'
[IO.File]::WriteAllText($confWithOwner, "ADO_DEFAULT_ASSIGNED_TO=$owner`n")
[IO.File]::WriteAllText($confWithout, "ADO_DEFAULT_ASSIGNED_TO=`n")

$bashExe = $null
foreach ($b in @('C:\Program Files\Git\bin\bash.exe', '/bin/bash')) {
    if (Test-Path $b) { $bashExe = $b; break }
}

function New-WritePayload {
    param([string]$Action, [hashtable]$Fields, [string]$ToolName = 'mcp_azure_devops__wit_work_item_write')
    $ti = @{ action = $Action; project = 'P' }
    if ($Action -eq 'create') {
        $ti.workItemType = 'Task'
        $ti.fields = @($Fields.GetEnumerator() | ForEach-Object { @{ name = $_.Key; value = $_.Value } })
    }
    if ($Action -eq 'add_child') {
        $ti.parentId = 7
        $ti.items = @(@{ title = 'child'; description = 'd' })
    }
    if ($Action -eq 'update') {
        $ti.id = 7
        $ti.updates = @(@{ op = 'add'; path = '/fields/System.Title'; value = 't' })
    }
    return (@{ tool_name = $ToolName; tool_input = $ti } | ConvertTo-Json -Depth 6 -Compress)
}

function Invoke-Gate {
    param([string]$Payload, [string]$Conf, [string]$Dialect = 'ps')
    $ErrorActionPreference = 'Continue'
    $prev = $env:AF_CONF_PATH
    $env:AF_CONF_PATH = $Conf
    try {
        if ($Dialect -eq 'sh') {
            $out = $Payload | & $bashExe ($shHook -replace '\\', '/') 2>$null | Out-String
        } else {
            $out = $Payload | & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $psHook 2>$null | Out-String
        }
        $code = $LASTEXITCODE
    } finally {
        $env:AF_CONF_PATH = $prev
    }
    $decision = ''
    $reason = ''
    try {
        $parsed = $out | ConvertFrom-Json
        $hso = $parsed.PSObject.Properties['hookSpecificOutput']
        if ($hso) {
            $d = $hso.Value.PSObject.Properties['permissionDecision']
            $r = $hso.Value.PSObject.Properties['permissionDecisionReason']
            if ($d) { $decision = [string]$d.Value }
            if ($r) { $reason = [string]$r.Value }
        }
    } catch {
        $decision = '<unparsable>'
    }
    return [pscustomobject]@{ Exit = $code; Out = $out.Trim(); Decision = $decision; Reason = $reason }
}

$noOwner = @{ 'System.Title' = 'x' }
$blankOwner = @{ 'System.Title' = 'x'; 'System.AssignedTo' = '  ' }
$withOwner = @{ 'System.Title' = 'x'; 'System.AssignedTo' = $owner }

try {
    $r = Invoke-Gate (New-WritePayload 'create' $noOwner) $confWithOwner
    Add-Result 'W1_create_without_an_owner_is_denied_naming_the_default' `
        ($r.Exit -eq 0 -and $r.Decision -eq 'deny' -and $r.Reason.Contains($owner) -and $r.Reason.Contains('System.AssignedTo')) `
        "exit=$($r.Exit) decision='$($r.Decision)' out=$($r.Out)"

    $r = Invoke-Gate (New-WritePayload 'create' $blankOwner) $confWithOwner
    Add-Result 'W2_a_blank_owner_counts_as_no_owner' ($r.Decision -eq 'deny') "decision='$($r.Decision)'"

    $r = Invoke-Gate (New-WritePayload 'create' $withOwner) $confWithOwner
    Add-Result 'W3_create_with_an_owner_is_not_denied' `
        ($r.Exit -eq 0 -and $r.Decision -ne 'deny' -and $r.Decision -ne '<unparsable>') `
        "exit=$($r.Exit) decision='$($r.Decision)' out=$($r.Out)"

    $r = Invoke-Gate (New-WritePayload 'create' $noOwner) $confWithout
    Add-Result 'W4_without_a_configured_default_the_agent_is_told_to_ask' `
        ($r.Decision -eq 'deny' -and $r.Reason.Contains('ADO_DEFAULT_ASSIGNED_TO') -and $r.Reason -match '(?i)\bask\b') `
        "decision='$($r.Decision)' reason=$($r.Reason)"

    $r = Invoke-Gate (New-WritePayload 'add_child' @{}) $confWithOwner
    Add-Result 'W5_add_child_is_denied_and_points_at_create_plus_link' `
        ($r.Decision -eq 'deny' -and $r.Reason.Contains('wit_work_item_link_write') -and $r.Reason.Contains('create')) `
        "decision='$($r.Decision)' reason=$($r.Reason)"

    $r = Invoke-Gate (New-WritePayload 'update' @{}) $confWithOwner
    Add-Result 'W6_an_update_is_not_judged' ($r.Decision -ne 'deny') "decision='$($r.Decision)'"

    # The hook-side spelling of an MCP tool id has not been captured, so the
    # match is by suffix; a different server prefix must still be caught.
    $r = Invoke-Gate (New-WritePayload 'create' $noOwner 'mcp_other_prefix_wit_work_item_write') $confWithOwner
    Add-Result 'W7_the_tool_is_matched_by_suffix_not_by_one_prefix' ($r.Decision -eq 'deny') "decision='$($r.Decision)'"

    $r = Invoke-Gate '{"tool_name":"read_file","tool_input":{"filePath":"a.py","startLine":1,"endLine":2}}' $confWithOwner
    Add-Result 'W8_an_unrelated_tool_is_untouched' ($r.Exit -eq 0 -and $r.Out -eq '{}') "exit=$($r.Exit) out=$($r.Out)"

    if ($bashExe) {
        $a = Invoke-Gate (New-WritePayload 'create' $noOwner) $confWithOwner 'sh'
        $c = Invoke-Gate (New-WritePayload 'create' $withOwner) $confWithOwner 'sh'
        $k = Invoke-Gate (New-WritePayload 'add_child' @{}) $confWithOwner 'sh'
        Add-Result 'W9_the_bash_twin_gives_the_same_verdicts' `
            ($a.Decision -eq 'deny' -and $a.Reason.Contains($owner) -and $c.Decision -ne 'deny' -and $c.Decision -ne '<unparsable>' -and $k.Decision -eq 'deny') `
            "create-no-owner='$($a.Decision)' create-owner='$($c.Decision)' add_child='$($k.Decision)' out=$($a.Out)"
    } else {
        Add-Result 'W9_the_bash_twin_gives_the_same_verdicts' $false 'no bash found -- this case would prove nothing'
    }

    $confText = if (Test-Path $shippedConf) { Get-Content $shippedConf -Raw } else { '' }
    Add-Result 'W10_the_shipped_config_declares_the_owner_key' `
        ($confText -match '(?m)^ADO_DEFAULT_ASSIGNED_TO=\s*$') 'af-env.conf must ship the key, empty'

    $agentText = if (Test-Path $agentFile) { Get-Content $agentFile -Raw } else { '' }
    Add-Result 'W11_the_worker_gate_table_carries_a_hard_owner_row' `
        ($agentText -match '(?m)^\|\s*Owner set on create\s*\|\s*HARD\s*\|') 'ado-work-item-manager Exit Gates needs the row'
} finally {
    Remove-Item $fixture -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output '===== work item owner gate tests (issue #36) ====='
$failed = 0
foreach ($k in $results.Keys) {
    if ($results[$k]) {
        Write-Output "PASS  $k"
    } else {
        $failed++
        Write-Output "FAIL  $k"
        Write-Output "      $($details[$k])"
    }
}
Write-Output "----- $($results.Count - $failed)/$($results.Count) passed -----"
if ($failed -gt 0) { exit 1 }
exit 0
