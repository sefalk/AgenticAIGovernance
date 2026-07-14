#!/usr/bin/env pwsh
# SessionStart hook: verifies Azure DevOps MCP readiness and optionality state.
# Output: additionalContext with READY, DEGRADED, or BLOCKED readiness summary.

$ErrorActionPreference = 'SilentlyContinue'

try { [void][Console]::In.ReadToEnd() } catch {}

$repoRoot = (git rev-parse --show-toplevel 2>$null)
if (-not $repoRoot) {
    Write-Output '{}'
    exit 0
}

$confPath = Join-Path $repoRoot '.github/af-env.conf'
$mode = 'off'
$missing = New-Object System.Collections.Generic.List[string]
$advisories = New-Object System.Collections.Generic.List[string]
$project = ''
$wikiIdentifier = ''

if (-not (Test-Path $confPath)) {
    $missing.Add('.github/af-env.conf')
} else {
    $conf = Get-Content $confPath -ErrorAction SilentlyContinue
    $modeMatch = $conf | Select-String -Pattern '^ADO_CAPABILITY_MODE=(.+)$'
    if ($modeMatch) {
        $mode = $modeMatch.Matches[0].Groups[1].Value.Trim().ToLower()
    }

    $projectMatch = $conf | Select-String -Pattern '^ADO_PROJECT=(.+)$'
    $wikiMatch = $conf | Select-String -Pattern '^ADO_WIKI_IDENTIFIER=(.+)$'
    $repoIdMatch = $conf | Select-String -Pattern '^ADO_REPOSITORY_ID=(.+)$'
    $repoNameMatch = $conf | Select-String -Pattern '^ADO_REPOSITORY_NAME=(.+)$'

    if ($projectMatch) { $project = $projectMatch.Matches[0].Groups[1].Value.Trim() }
    if ($wikiMatch) { $wikiIdentifier = $wikiMatch.Matches[0].Groups[1].Value.Trim() }

    if ($mode -eq 'required') {
        if (-not $project) { $missing.Add('ADO_PROJECT') }
    } elseif ($mode -eq 'optional') {
        if (-not $project) { $advisories.Add('ADO_PROJECT missing (work-item workflows will use fallback traceability)') }
    }

    if (-not $wikiIdentifier) {
        $advisories.Add('ADO_WIKI_IDENTIFIER missing (wiki workflows may need confirmation)')
    }

    if (-not $repoIdMatch -and -not $repoNameMatch) {
        $advisories.Add('ADO_REPOSITORY_ID/ADO_REPOSITORY_NAME missing (branch artifact links may degrade to comments)')
    }

    if ($mode -ne 'off') {
        $targetMatch = $conf | Select-String -Pattern '^ADO_DEFAULT_TARGET_BRANCH=(.+)$'
        if (-not $targetMatch) {
            $advisories.Add('ADO_DEFAULT_TARGET_BRANCH missing (PR integration defaults to dev)')
        }
        $acMatch = $conf | Select-String -Pattern '^ADO_PR_AUTOCOMPLETE_BRANCHES=(.+)$'
        $hoMatch = $conf | Select-String -Pattern '^ADO_PR_HUMAN_ONLY_BRANCHES=(.+)$'
        if (-not $acMatch -or -not $hoMatch) {
            $advisories.Add('ADO_PR_AUTOCOMPLETE_BRANCHES/ADO_PR_HUMAN_ONLY_BRANCHES missing (PR completion policy uses defaults)')
        }
    }
}

$agentsDir = Join-Path $repoRoot '.github/agents'
if (Test-Path $agentsDir) {
    $agentFiles = Get-ChildItem -Path $agentsDir -Filter '*.agent.md' -File -ErrorAction SilentlyContinue
    foreach ($f in $agentFiles) {
        $txt = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
        if ($txt -match 'Azure DevOps' -and $txt -match '^name:\s*(.+)$') {
            $agentName = ($txt | Select-String -Pattern '^name:\s*(.+)$' | Select-Object -First 1).Matches[0].Groups[1].Value
            if ($agentName -and -not $agentName.StartsWith('ado-')) {
                $advisories.Add("ADO agent without ado- prefix: $agentName")
            }
        }
    }
}

$authHint = 'auth-provider-managed'
if ($env:AZURE_DEVOPS_EXT_PAT -or $env:ADO_PAT -or $env:SYSTEM_ACCESSTOKEN) {
    $authHint = 'token-env-present'
}

$status = 'READY'
if ($mode -eq 'required' -and $missing.Count -gt 0) {
    $status = 'BLOCKED'
} elseif ($mode -eq 'optional' -and $missing.Count -gt 0) {
    $status = 'DEGRADED'
} elseif ($mode -eq 'off') {
    $advisories.Add('ADO capability mode is off')
}

$msg = "ADO MCP readiness: $status | mode=$mode | auth=$authHint"
if ($missing.Count -gt 0) {
    $msg += " | missing=" + ($missing -join ', ')
}
if ($advisories.Count -gt 0) {
    $msg += " | advisory=" + ($advisories -join '; ')
}
if ($project) {
    $msg += " | defaults:project=$project"
}
if ($wikiIdentifier) {
    $msg += " | wiki=$wikiIdentifier"
}

@{
    hookSpecificOutput = @{
        hookEventName     = 'SessionStart'
        additionalContext = $msg
    }
} | ConvertTo-Json -Depth 3 -Compress

exit 0