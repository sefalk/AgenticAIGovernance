# gh-api.ps1 -- the one way this repository's workflows call `gh api` (#323).
#
# A single transient API response used to fail a whole regression build, and
# the sentence it printed was shared word for word by two gates -- so "GitHub
# hiccuped", "the token lost a permission" and "PR_NUMBER was empty" all looked
# the same. This helper asks again on transient answers and fails at once on
# the ones that are answers, and every failure names its step and endpoint.
#
# Transient (retried, bounded): 5xx, 429, a 403 that says "rate limit", and a
# failure with no HTTP status at all (network). Everything else is an answer.
# Writes are never retried: the caller states -Mode, the helper does not infer
# it, so a later non-idempotent caller cannot inherit a retry by accident.
#
# Usage (from a workflow step, after actions/checkout):
#   $ghApi = Join-Path $env:GITHUB_WORKSPACE '.github/scripts/gh-api.ps1'
#   $files = & $ghApi -Step 'Attestation gate: list changed files' -Mode Read `
#       -Arguments @("repos/$env:REPO/pulls/$env:PR_NUMBER/files", '--paginate', '--jq', '.[].filename')
#   if ($LASTEXITCODE -ne 0) { exit 1 }
#
# Output: gh's stdout lines on success (exit 0). On failure: an ::error:: line
# and exit 1; the caller only has to stop.

param(
    [Parameter(Mandatory = $true)][string]$Step,
    [Parameter(Mandatory = $true)][ValidateSet('Read', 'Write')][string]$Mode,
    [Parameter(Mandatory = $true)][string[]]$Arguments
)

# The Actions powershell shell runs with Stop, which turns gh's stderr into a
# terminating error under 2>&1 in Windows PowerShell 5.1.
$ErrorActionPreference = 'Continue'

$maxAttempts = if ($Mode -eq 'Read') { 3 } else { 1 }
$backoff = 5
if ($env:GH_API_BACKOFF_SECONDS -match '^\d+$') { $backoff = [int]$env:GH_API_BACKOFF_SECONDS }

$valueFlags = @('-X', '--method', '--jq', '-q', '-f', '-F', '--field', '--raw-field', '-H', '--header', '--template', '-t')
$endpoint = '(no endpoint)'
for ($i = 0; $i -lt $Arguments.Count; $i++) {
    if ($valueFlags -contains $Arguments[$i]) { $i++; continue }
    if (-not $Arguments[$i].StartsWith('-')) { $endpoint = $Arguments[$i]; break }
}

$reason = ''
for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    $global:LASTEXITCODE = 0
    $raw = & gh api @Arguments 2>&1
    $code = $LASTEXITCODE
    $stdout = @($raw | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
    if ($code -eq 0) {
        $stdout
        exit 0
    }

    $said = (@($raw | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) | ForEach-Object { "$_" }) -join ' '
    $status = $null
    if ($said -match 'HTTP (\d{3})') { $status = [int]$Matches[1] }
    $transient = ($null -eq $status) -or ($status -ge 500) -or ($status -eq 429) -or
        ($status -eq 403 -and $said -match '(?i)rate limit')
    $label = if ($null -eq $status) { 'no HTTP status' } else { "HTTP $status" }

    if ($Mode -eq 'Write') {
        $reason = "$label; not retried: writes are never retried"
        break
    }
    if (-not $transient) {
        $reason = "$label; not retried: that is an answer, not a hiccup"
        break
    }
    $reason = "$label after $attempt attempts"
    if ($attempt -lt $maxAttempts) {
        Write-Host "gh api $endpoint -> $label (attempt $attempt of $maxAttempts); asking again."
        Start-Sleep -Seconds ($backoff * $attempt)
    }
}

Write-Host "::error::$Step -- gh api $endpoint failed ($reason). Failing rather than passing on an unanswered question."
if ($said) { Write-Host "  gh said: $said" }
exit 1
