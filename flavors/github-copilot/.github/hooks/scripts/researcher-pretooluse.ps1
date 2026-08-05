# Agent-scoped PreToolUse hook for the researcher agent.
#
# CREDENTIAL-URL SCAN (SOFT -- warns when fetch URLs contain embedded credentials)
#
# Prevents credential leakage via URLs passed to web/fetch.
# Advisory only -- does not block the fetch. The researcher must
# sanitize credentials from its output (existing Critical Constraint).
#
# Fires only when the researcher agent is active.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

$ErrorActionPreference = 'SilentlyContinue'

# Root, config and interpreter come from this script's location, never from the
# cwd the agent happens to run in (issue #54).
. "$PSScriptRoot/_common.ps1"

# Read and parse stdin
$raw = [Console]::In.ReadToEnd()
try {
    $inputData = $raw | ConvertFrom-Json
} catch {
    Write-Output '{}'
    exit 0
}

# Only inspect fetch tool calls
$toolName = $inputData.tool_name
if ($toolName -notmatch 'fetch') {
    Write-Output '{}'
    exit 0
}

# VS Code's fetch tool sends `urls` -- an array, beside `query`. The single
# `url`/`uri` string this hook was written against is a legacy shape, so both
# are read and every entry is examined (issue #64).
$ti = $inputData.tool_input
$urls = @()
if ($ti.urls) { $urls += @($ti.urls) }
if ($ti.url) { $urls += $ti.url }
if ($ti.uri) { $urls += $ti.uri }
$urls = @($urls | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
if ($urls.Count -eq 0) {
    Write-Output '{}'
    exit 0
}

# Check for embedded credentials in URL
$credPatterns = @(
    @{ name = "Basic auth"; pattern = '://[^/@]+:[^/@]+@' }
    @{ name = "Token query param"; pattern = '[?&](token|access_token|api_key|apikey|auth|key|secret|password)=' }
    @{ name = "Authorization query param"; pattern = '[?&]Authorization=' }
    @{ name = "Credential fragment"; pattern = '#(access_token|token)=' }
)

function Emit-Fetch([string]$decision, [string]$reason) {
    @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = $decision
            permissionDecisionReason = $reason
        }
    } | ConvertTo-Json -Depth 3 -Compress
    exit 0
}

# ---------------------------------------------------------------------------
# Domain allowlist: auto-approve official docs; prompt (with seed-add offer)
# for everything else. Allowlist lives in .github/af-env.conf.
# ---------------------------------------------------------------------------
$allow = Get-AfConfig -Key 'WEB_FETCH_ALLOWLIST'
$domains = @($allow -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })

$findings = @()
$unlisted = @()
$matchedAny = $false

foreach ($u in $urls) {
    $hits = @($credPatterns | Where-Object { $u -match $_.pattern } | ForEach-Object { $_.name })
    if ($hits.Count -gt 0) {
        $sanitized = $u -replace '://([^/@]+):([^/@]+)@', '://***:***@'
        $sanitized = $sanitized -replace '([?&])(token|access_token|api_key|apikey|auth|key|secret|password)=[^&]*', '$1$2=***'
        $findings += "$($hits -join ', ') in $sanitized"
    }

    # The host is what follows the last `@` in the authority. Stopping at the
    # first `:` reads the userinfo instead, so `https://docs.python.org:x@evil/`
    # would pass the allowlist as `docs.python.org`.
    $fetchHost = ''
    if ($u -match '^[a-zA-Z][a-zA-Z0-9+.-]*://([^/?#]+)') {
        $fetchHost = ($Matches[1] -replace '^.*@', '' -replace ':\d*$', '').ToLower()
    }
    if (-not $fetchHost) { continue }

    if ($domains | Where-Object { $fetchHost -eq $_ -or $fetchHost.EndsWith('.' + $_) }) {
        $matchedAny = $true
    } else {
        $unlisted += $fetchHost
    }
}

# Build a credential warning note (appended to whatever decision follows).
# We do NOT short-circuit to 'allow' here: a credentialed URL to a
# non-allowlisted domain must still go through the allowlist prompt below.
$credNote = ''
if ($findings.Count -gt 0) {
    $credNote = " WARNING: URL contains embedded credentials ($($findings -join '; ')). " +
        "Strip them from your research brief output."
}

# One unlisted entry decides the batch: the tool fetches every URL in the
# array, so approving on the first match would wave the rest through unseen.
if ($unlisted.Count -gt 0) {
    $why = if ($AfConfFound) { "Not in WEB_FETCH_ALLOWLIST: $(($unlisted | Select-Object -Unique) -join ', ')." }
           else { "No allowlist available: .github/af-env.conf was not found at $AfConfPath." }
    Emit-Fetch 'ask' ("$why Approve to fetch once. " +
        "To auto-approve in future, add the domain to WEB_FETCH_ALLOWLIST in .github/af-env.conf " +
        "(the agent can do this on your confirmation).$credNote")
}

if ($matchedAny) { Emit-Fetch 'allow' "Allowlisted documentation domain.$credNote" }

# No parseable host: keep the fetch flowing but surface any credential warning.
if ($credNote) { Emit-Fetch 'allow' "URL fetch.$credNote" }

Write-Output '{}'
exit 0
