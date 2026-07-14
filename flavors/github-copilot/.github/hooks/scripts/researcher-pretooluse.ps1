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

# Extract URL from tool input
$url = $inputData.tool_input.url
if (-not $url) {
    $url = $inputData.tool_input.uri
}
if (-not $url) {
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

$findings = @()
foreach ($p in $credPatterns) {
    if ($url -match $p.pattern) {
        $findings += $p.name
    }
}

# Build a credential warning note (appended to whatever decision follows).
# We do NOT short-circuit to 'allow' here: a credentialed URL to a
# non-allowlisted domain must still go through the allowlist prompt below.
$credNote = ''
if ($findings.Count -gt 0) {
    $sanitized = $url -replace '://([^/@]+):([^/@]+)@', '://***:***@'
    $sanitized = $sanitized -replace '([?&])(token|access_token|api_key|apikey|auth|key|secret|password)=[^&]*', '$1$2=***'
    $credNote = " WARNING: URL contains embedded credentials ($($findings -join ', ')). " +
        "Strip them from your research brief output. Sanitized URL: $sanitized"
}

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
$allow = ''
$repo = (git rev-parse --show-toplevel 2>$null)
if ($repo) {
    $conf = Join-Path $repo '.github/af-env.conf'
    if (Test-Path $conf) {
        $line = Select-String -Path $conf -Pattern '^\s*WEB_FETCH_ALLOWLIST=(.*)$' | Select-Object -First 1
        if ($line) { $allow = $line.Matches[0].Groups[1].Value.Trim() }
    }
}

$fetchHost = ''
if ($url -match '^[a-zA-Z][a-zA-Z0-9+.-]*://([^/:?#]+)') { $fetchHost = $Matches[1].ToLower() }

if ($fetchHost) {
    $domains = @($allow -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
    foreach ($d in $domains) {
        if ($fetchHost -eq $d -or $fetchHost.EndsWith('.' + $d)) {
            Emit-Fetch 'allow' "Allowlisted documentation domain ($d).$credNote"
        }
    }
    Emit-Fetch 'ask' ("Domain '$fetchHost' is not in WEB_FETCH_ALLOWLIST. Approve to fetch once. " +
        "To auto-approve this domain in future, add '$fetchHost' to WEB_FETCH_ALLOWLIST in .github/af-env.conf " +
        "(the agent can do this on your confirmation).$credNote")
}

# No parseable host: keep the fetch flowing but surface any credential warning.
if ($credNote) { Emit-Fetch 'allow' "URL fetch.$credNote" }

Write-Output '{}'
exit 0
