# copilot:generated | implementer | 2026-03-17
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

if ($findings.Count -gt 0) {
    # WARN only -- do not deny the fetch
    $sanitized = $url -replace '://([^/@]+):([^/@]+)@', '://***:***@'
    $sanitized = $sanitized -replace '([?&])(token|access_token|api_key|apikey|auth|key|secret|password)=[^&]*', '$1$2=***'

    @{
        hookSpecificOutput = @{
            hookEventName      = 'PreToolUse'
            permissionDecision = 'allow'
            permissionDecisionReason = "WARNING: URL contains embedded credentials ($($findings -join ', ')). " +
                "Ensure credentials are stripped from your research brief output. " +
                "Sanitized URL: $sanitized"
        }
    } | ConvertTo-Json -Depth 3 -Compress
    exit 0
}

Write-Output '{}'
exit 0
