# Regression suite: a hook is declared once -- globally or per agent, not both (#345).
#
# agent-hooks.json registers a hook for every agent; an agent's frontmatter adds
# hooks only that agent needs. The shipped coordinator re-declared four global
# hooks, and four other agents re-declared scan-secrets, so those ran twice per
# call (measured: 4,951 repeats in 8 logs, every one from a second declaration).
# The copies were removed once test-hooks-integration.ps1 could prove the global
# hook still runs in every invocation; this suite keeps them from coming back.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$githubDir = Split-Path -Parent $scriptDir

$results = [ordered]@{}
$details = [ordered]@{}
function Add-Result([string]$Name, [bool]$Ok, [string]$Detail) {
    $script:results[$Name] = $Ok
    $script:details[$Name] = $Detail
}

function Get-Stem([string]$Command) {
    if (($Command -replace '\\+', '/') -match 'hooks/scripts/([\w-]+)\.\w+') { return $Matches[1] }
    return $null
}

function Get-GlobalHooks([string]$JsonPath) {
    $map = @{}
    $json = Get-Content $JsonPath -Raw | ConvertFrom-Json
    foreach ($ev in $json.hooks.PSObject.Properties) {
        $map[$ev.Name] = @($ev.Value | ForEach-Object { Get-Stem ([string]$_.command) } | Where-Object { $_ } | Sort-Object -Unique)
    }
    return $map
}

# Event -> stems from the `hooks:` block of an agent's YAML frontmatter.
function Get-AgentHooks([string]$Path) {
    $map = @{}
    $text = Get-Content $Path -Raw
    $fm = [regex]::Match($text, '(?s)\A---\r?\n(.*?)\r?\n---').Groups[1].Value
    $inHooks = $false
    $event = $null
    foreach ($line in ($fm -split '\r?\n')) {
        if ($line -match '^hooks:\s*$') { $inHooks = $true; continue }
        if (-not $inHooks) { continue }
        if ($line -match '^\S') { break }
        if ($line -match '^  (\w+):\s*$') { $event = $Matches[1]; continue }
        if ($event -and $line -match '^\s+(command|windows|linux|osx):') {
            $stem = Get-Stem $line
            if ($stem) {
                if (-not $map.ContainsKey($event)) { $map[$event] = @() }
                if ($map[$event] -notcontains $stem) { $map[$event] += $stem }
            }
        }
    }
    return $map
}

function Find-Redeclarations([hashtable]$Global, [string]$AgentsDir) {
    $found = @()
    foreach ($agent in Get-ChildItem $AgentsDir -Filter '*.agent.md') {
        $own = Get-AgentHooks $agent.FullName
        foreach ($ev in $own.Keys) {
            foreach ($stem in $own[$ev]) {
                if ($Global.ContainsKey($ev) -and $Global[$ev] -contains $stem) { $found += "$($agent.Name): $ev $stem" }
            }
        }
    }
    return $found
}

$global = Get-GlobalHooks (Join-Path $githubDir 'hooks/agent-hooks.json')
Add-Result 'H0_global_hooks_are_read_from_agent_hooks_json' ($global.ContainsKey('PreToolUse') -and $global['PreToolUse'] -contains 'block-dangerous') "events: $($global.Keys -join ', ')"

$redeclared = @(Find-Redeclarations $global (Join-Path $githubDir 'agents'))
Add-Result 'H1_no_agent_redeclares_a_global_hook_for_the_same_event' ($redeclared.Count -eq 0) "redeclared: $($redeclared -join '; ')"

$missing = @()
foreach ($agent in Get-ChildItem (Join-Path $githubDir 'agents') -Filter '*.agent.md') {
    $own = Get-AgentHooks $agent.FullName
    foreach ($ev in $own.Keys) {
        foreach ($stem in $own[$ev]) {
            if (-not (Test-Path (Join-Path $githubDir "hooks/scripts/$stem.ps1"))) { $missing += "$($agent.Name): $stem" }
        }
    }
}
Add-Result 'H2_every_agent_hook_points_at_a_shipped_script' ($missing.Count -eq 0) "missing: $($missing -join '; ')"

# The detector must see a re-declaration, or H1 passes by reading nothing.
$fx = Join-Path ([IO.Path]::GetTempPath()) ("af345-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $fx -Force | Out-Null
try {
    [IO.File]::WriteAllText((Join-Path $fx 'probe.agent.md'), (@(
        '---', 'name: probe', 'hooks:', '  PreToolUse:', '    - type: command',
        "      command: 'bash .github/hooks/scripts/probe-pretooluse.sh'",
        '    - type: command',
        "      windows: 'powershell -File .github\\\\hooks\\\\scripts\\\\block-dangerous.ps1'",
        '---', '# Probe') -join "`n"))
    $probe = @(Find-Redeclarations $global $fx)
    Add-Result 'H3_the_detector_finds_a_planted_redeclaration' ($probe.Count -eq 1 -and $probe[0] -match 'PreToolUse block-dangerous') "found: $($probe -join '; ')"
} finally {
    Remove-Item $fx -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output '===== hook declaration tests (issue #345) ====='
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
