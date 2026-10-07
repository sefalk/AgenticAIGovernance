# close-delivered-issues.ps1 -- close the issues that pull requests merged into dev name (#160).
#
# `Closes #N` fires only on merges into the default branch (main). Work lands on
# dev long before a release, so its issues stayed open and the list hid what had
# shipped; closing them by hand at merge time was the step agents forgot.
#
# A wrong close hides work that was left open on purpose, so the match is narrow:
#   - only pull requests merged into -Base at or after -Since: older history holds
#     issues deliberately kept open past their pull request;
#   - only a keyword at the start of a body line, outside HTML comments and code
#     fences, and only the one issue right after it;
#   - only open issues, never pull requests.
# The delivery note is posted before the close, and any failed call fails the run.
#
# Usage (workflow step, after actions/checkout):
#   & .github/scripts/close-delivered-issues.ps1 -Repo $env:REPO -Since $env:SINCE [-DryRun]

param(
    [Parameter(Mandatory = $true)][string]$Repo,
    [Parameter(Mandatory = $true)][string]$Since,
    [string]$Base = 'dev',
    [int]$Limit = 50,
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
$ghApi = Join-Path $PSScriptRoot 'gh-api.ps1'
$utc = [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal

function ConvertTo-UtcTime($Value) {
    # pwsh's ConvertFrom-Json yields a DateTime, Windows PowerShell 5.1 a string.
    if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
    return [datetime]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, $utc)
}

function Get-ClosingRef([string]$Body) {
    $text = [regex]::Replace($Body, '(?s)<!--.*?-->', '')
    $text = [regex]::Replace($text, '(?ms)^[ \t]*```.*?^[ \t]*```', '')
    $pattern = '(?im)^[ \t]*(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)[ \t]*:?[ \t]+#(\d+)\b'
    [regex]::Matches($text, $pattern) | ForEach-Object { [int]$_.Groups[1].Value }
}

$cutoff = ConvertTo-UtcTime $Since
$endpoint = "repos/$Repo/pulls?state=closed&base=$Base&sort=updated&direction=desc&per_page=$Limit"
$jq = '.[] | select(.merged_at != null) | {number, merged_at, merge_commit_sha, body} | @json'
$lines = & $ghApi -Step 'Close delivered: list merged pull requests' -Mode Read -Arguments @($endpoint, '--jq', $jq)
if ($LASTEXITCODE -ne 0) { exit 1 }

$seen = @{}
$closed = 0
foreach ($line in @($lines)) {
    if (-not "$line".Trim()) { continue }
    $pr = "$line" | ConvertFrom-Json
    if ($null -eq $pr.merged_at -or (ConvertTo-UtcTime $pr.merged_at) -lt $cutoff) { continue }

    foreach ($n in @(Get-ClosingRef ([string]$pr.body))) {
        if ($seen.ContainsKey($n)) { continue }
        $seen[$n] = $true

        $info = & $ghApi -Step "Close delivered: read #$n" -Mode Read `
            -Arguments @("repos/$Repo/issues/$n", '--jq', '[.state, (.pull_request != null)] | @tsv')
        if ($LASTEXITCODE -ne 0) { exit 1 }
        $state, $isPr = "$info".Trim() -split "`t", 2
        if ($isPr -eq 'true') {
            Write-Host "skip   #$n -- a pull request, named by #$($pr.number)"
            continue
        }
        if ($state -ne 'open') { continue }

        $sha = ([string]$pr.merge_commit_sha).Substring(0, 7)
        if ($DryRun) {
            Write-Host "would close #$n -- delivered to $Base in #$($pr.number) ($sha)"
            continue
        }

        $note = "Delivered to ``$Base`` in #$($pr.number) ($sha). Closed automatically: ``Closes #$n`` " +
            "fires only on the default branch, so issues delivered to ``$Base`` are closed at merge time instead (#160)."
        & $ghApi -Step "Close delivered: note on #$n" -Mode Write `
            -Arguments @('-X', 'POST', "repos/$Repo/issues/$n/comments", '-f', "body=$note") | Out-Null
        if ($LASTEXITCODE -ne 0) { exit 1 }
        & $ghApi -Step "Close delivered: close #$n" -Mode Write `
            -Arguments @('-X', 'PATCH', "repos/$Repo/issues/$n", '-f', 'state=closed', '-f', 'state_reason=completed') | Out-Null
        if ($LASTEXITCODE -ne 0) { exit 1 }
        Write-Host "closed #$n -- delivered to $Base in #$($pr.number) ($sha)"
        $closed++
    }
}

Write-Host "::notice::closed $closed issue(s) delivered to $Base since $Since"
exit 0
