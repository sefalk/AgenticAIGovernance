# Regression tests for the af-github MCP namespace and its .mcp.json registration (#547, #573).
#
# In the Copilot harness a subagent grant `github/<tool>` does not resolve when
# the server is named `github`; the same server under another name resolves in
# slash form (AF #447). So the GitHub agents grant `af-github/<tool>`, and the
# deploy registers that server in a repo-root .mcp.json -- only where none
# exists, because a project's own .mcp.json is not the framework's to edit.
#
# The deploy cases stop the run once it is past the registration step: it runs
# before the payload copy, and waiting for the copy would buy nothing but time.
# Run from anywhere:
#   powershell .github/scripts/test-github-mcp-registration.ps1
# Exits non-zero if any scenario fails (CI-friendly).
# copilot:generated | coordinator | 2026-11-16

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_suite_env.ps1')
if (-not (Test-AfSourceTree)) {
    Write-Output '  SKIP  github MCP registration -- deploy.ps1 ships only with the framework, not into a project'
    exit 0
}

$payloadRoot = Split-Path (Split-Path $PSScriptRoot)
$deployScript = Join-Path $payloadRoot 'deploy.ps1'
$agentsDir = Join-Path $payloadRoot '.github/agents'
$pastStepMarker = '.github/ directories:'
$missingWarning = 'has no "af-github" server'

$results = [ordered]@{}
$details = [ordered]@{}
function Add-Result([string]$Name, [bool]$Ok, [string]$Detail = '') {
    $script:results[$Name] = $Ok
    $script:details[$Name] = $Detail
}

function Get-ToolGrants([string]$Path) {
    $lines = Get-Content -LiteralPath $Path
    $grants = @()
    $inFrontmatter = $false
    $inTools = $false
    foreach ($line in $lines) {
        if ($line -eq '---') {
            if ($inFrontmatter) { break }
            $inFrontmatter = $true
            continue
        }
        if (-not $inFrontmatter) { continue }
        if ($line -match '^tools:') { $inTools = $true; continue }
        if ($inTools -and $line -match '^\s+-\s+(\S+)') { $grants += $Matches[1]; continue }
        if ($line -match '^\S') { $inTools = $false }
    }
    return $grants
}

# Runs deploy.ps1 until it has passed the registration step, then stops it.
function Invoke-DeployPastRegistration([string]$TargetDir, [switch]$DryRun) {
    $log = Join-Path $TargetDir '..\deploy.log'
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$deployScript`"", '-TargetDir', "`"$TargetDir`"")
    if ($DryRun) { $argList += '-DryRun' }
    $proc = Start-Process -FilePath 'powershell' -ArgumentList $argList -RedirectStandardOutput $log `
        -RedirectStandardError "$log.err" -NoNewWindow -PassThru
    $deadline = (Get-Date).AddSeconds(120)
    while (-not $proc.HasExited -and (Get-Date) -lt $deadline) {
        if ((Test-Path $log) -and ((Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue) -match [regex]::Escape($pastStepMarker))) { break }
        Start-Sleep -Milliseconds 250
    }
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue; $proc.WaitForExit() }
    return (Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue) + (Get-Content -LiteralPath "$log.err" -Raw -ErrorAction SilentlyContinue)
}

function New-Target {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('af547-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $target = Join-Path $root 'target'
    New-Item -ItemType Directory -Path (Join-Path $target '.github') -Force | Out-Null
    $script:roots += $root
    return $target
}

$roots = @()
try {
    # --- grants -----------------------------------------------------------
    $legacy = @()
    foreach ($agent in Get-ChildItem -LiteralPath $agentsDir -Filter '*.agent.md' -File) {
        foreach ($grant in Get-ToolGrants $agent.FullName) {
            if ($grant -like 'github/*') { $legacy += "$($agent.Name): $grant" }
        }
    }
    Add-Result 'G1_no_agent_grants_the_reserved_github_namespace' ($legacy.Count -eq 0) ($legacy -join '; ')

    foreach ($name in 'gh-issue-manager', 'gh-pr-manager') {
        $grants = @(Get-ToolGrants (Join-Path $agentsDir "$name.agent.md"))
        Add-Result "G2_${name}_probes_af-github/get_me" ($grants -contains 'af-github/get_me') ($grants -join ', ')
    }

    # --- deploy: absent .mcp.json ------------------------------------------
    $target = New-Target
    $out = Invoke-DeployPastRegistration $target
    $mcp = Join-Path $target '.mcp.json'
    $created = Test-Path -LiteralPath $mcp
    Add-Result 'D1_absent_mcp_json_is_created' $created $out
    if ($created) {
        $json = Get-Content -LiteralPath $mcp -Raw | ConvertFrom-Json
        $server = $json.mcpServers.'af-github'
        Add-Result 'D2_created_file_registers_af-github_over_http' ($null -ne $server -and $server.type -eq 'http' -and
            $server.url -eq 'https://api.githubcopilot.com/mcp/') (Get-Content -LiteralPath $mcp -Raw)
        Add-Result 'D3_token_is_an_env_reference_not_a_secret' ($null -ne $server -and
            $server.headers.Authorization -eq 'Bearer ${AF_GH_TOKEN}') (Get-Content -LiteralPath $mcp -Raw)
        # #573: without it the server hands issue/PR writes to a form the human must submit.
        $features = if ($null -ne $server) { $server.headers.PSObject.Properties['X-MCP-Features'] } else { $null }
        Add-Result 'D10_writes_execute_without_a_form' ($null -ne $features -and
            $features.Value -eq 'mcp_apps_disable_form_deferral') (Get-Content -LiteralPath $mcp -Raw)
    } else {
        Add-Result 'D2_created_file_registers_af-github_over_http' $false 'no file'
        Add-Result 'D3_token_is_an_env_reference_not_a_secret' $false 'no file'
        Add-Result 'D10_writes_execute_without_a_form' $false 'no file'
    }

    # --- deploy: absent .mcp.json, dry run ---------------------------------
    $target = New-Target
    $out = Invoke-DeployPastRegistration $target -DryRun
    Add-Result 'D4_dry_run_writes_no_mcp_json' (-not (Test-Path -LiteralPath (Join-Path $target '.mcp.json'))) $out
    Add-Result 'D5_dry_run_announces_the_creation' ($out -match 'CREATE\s+\.mcp\.json') $out

    # --- deploy: project .mcp.json without af-github -----------------------
    $target = New-Target
    $mcp = Join-Path $target '.mcp.json'
    $own = [Text.Encoding]::UTF8.GetBytes("{`r`n  `"mcpServers`": { `"other`": { `"type`": `"stdio`", `"command`": `"x`" } }`r`n}`r`n")
    [IO.File]::WriteAllBytes($mcp, $own)
    $out = Invoke-DeployPastRegistration $target
    $after = [IO.File]::ReadAllBytes($mcp)
    Add-Result 'D6_project_mcp_json_is_byte_identical' ([Convert]::ToBase64String($after) -eq [Convert]::ToBase64String($own)) $out
    Add-Result 'D7_missing_af-github_is_warned_with_the_snippet' (($out -match [regex]::Escape($missingWarning)) -and
        ($out -match [regex]::Escape('"af-github"')) -and ($out -match [regex]::Escape('${AF_GH_TOKEN}'))) $out

    # --- deploy: project .mcp.json with af-github --------------------------
    $target = New-Target
    $mcp = Join-Path $target '.mcp.json'
    $own = [Text.Encoding]::UTF8.GetBytes('{"mcpServers":{"af-github":{"type":"http","url":"https://example.invalid/mcp/"}}}')
    [IO.File]::WriteAllBytes($mcp, $own)
    $out = Invoke-DeployPastRegistration $target -DryRun
    Add-Result 'D8_registered_af-github_draws_no_warning' (($out -match [regex]::Escape($pastStepMarker)) -and
        ($out -notmatch [regex]::Escape($missingWarning))) $out
    Add-Result 'D9_registered_af-github_file_is_untouched' ([Convert]::ToBase64String([IO.File]::ReadAllBytes($mcp)) -eq
        [Convert]::ToBase64String($own)) ''
}
finally {
    foreach ($r in $roots) { Remove-Item -LiteralPath $r -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host '=== GitHub MCP registration (#547) ==='
$failed = 0
foreach ($name in $results.Keys) {
    if ($results[$name]) { Write-Host "  PASS: $name" }
    else {
        Write-Host "  FAIL: $name"
        $d = [string]$details[$name]
        if ($d) { Write-Host ('        ' + ($d.Substring(0, [Math]::Min(400, $d.Length)) -replace "`r?`n", ' | ')) }
        $failed++
    }
}
Write-Host ''
Write-Host "  Checks passed: $($results.Count - $failed)"
Write-Host "  Checks failed: $failed"
if ($failed -gt 0) { exit 1 }
exit 0
