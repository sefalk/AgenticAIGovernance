# Regression suite: the shipped suites run where they are delivered (#349).
#
# Deploying 1.23.142 into a consumer and running the payload's own suites there
# failed six of them for layout reasons alone: a framework CHANGELOG, deploy.ps1,
# a venv at this repository's depth, a shipped-empty config key. None of it was
# a hook misbehaving, and none of it was visible here or in CI -- both run the
# suites inside the framework repo, the one place the assumptions hold.
#
# So this suite runs them somewhere else: a copy of .github with nothing beside
# it, which is what a consumer has.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ghDir = Split-Path -Parent $scriptDir

$results = [ordered]@{}
$details = [ordered]@{}
function Add-Result([string]$Name, [bool]$Ok, [string]$Detail) {
    $script:results[$Name] = $Ok
    $script:details[$Name] = $Detail
}

# Files that exist only in the framework payload, never in a consumer.
$frameworkOnly = @('CHANGELOG.md', 'deploy.ps1', 'deploy.sh')

$unguarded = @()
foreach ($suite in Get-ChildItem $scriptDir -Filter 'test-*.ps1') {
    if ($suite.Name -eq 'test-suite-portability.ps1') { continue }
    $text = Get-Content $suite.FullName -Raw
    $pathRef = $false
    foreach ($f in $frameworkOnly) {
        if ($text -match ("Join-Path[^\r\n]*'" + [regex]::Escape($f) + "'")) { $pathRef = $true }
    }
    if ($pathRef -and $text -notmatch '_suite_env\.ps1') { $unguarded += $suite.Name }
}
Add-Result 'P1_every_suite_touching_a_framework_only_file_uses_the_shared_guard' ($unguarded.Count -eq 0) "unguarded: $($unguarded -join ', ')"

# One interpreter resolver. Fourteen private copies had drifted into three
# shapes, one of which returned `py -3` as an array that `& $python` cannot run.
$ownProbe = @(Get-ChildItem $scriptDir -Filter '*.ps1' |
    Where-Object { $_.Name -notin @('_suite_env.ps1', 'test-suite-portability.ps1') -and (Get-Content $_.FullName -Raw) -match "-match 'Python 3'" } |
    ForEach-Object { $_.Name })
Add-Result 'P3_no_suite_carries_its_own_interpreter_probe' ($ownProbe.Count -eq 0) "own probe: $($ownProbe -join ', ')"

# Each entry: the suite, and the skip it must print when it is not in the
# framework repo -- proof the guard was reached, not merely that nothing failed.
$live = [ordered]@{
    'test-changelog-headings.ps1' = 'SKIP  A2_shipped_changelog_passes'
    'test-deploy-flags.ps1'       = 'SKIP  deploy flags'
    'test-rule-drift.ps1'         = 'PASS  R1_'
    'test-suite-scope.ps1'        = 'SKIP  S5 '
    'test-work-item-owner.ps1'    = 'PASS  W10_'
}

$consumer = Join-Path ([IO.Path]::GetTempPath()) ("af349-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    New-Item -ItemType Directory -Path $consumer -Force | Out-Null
    Copy-Item $ghDir (Join-Path $consumer '.github') -Recurse
    Get-ChildItem (Join-Path $consumer '.github') -Recurse -Directory -Filter '__pycache__' | Remove-Item -Recurse -Force
    # A configured consumer, not the shipped template: the template's empty owner
    # key would let W10 pass here while it fails in every real project.
    $conf = Join-Path $consumer '.github/af-env.conf'
    $confText = [IO.File]::ReadAllText($conf) -replace '(?m)^ADO_DEFAULT_ASSIGNED_TO=\s*$', 'ADO_DEFAULT_ASSIGNED_TO=owner@example.com'
    [IO.File]::WriteAllText($conf, $confText)

    foreach ($name in $live.Keys) {
        $path = Join-Path $consumer ".github/scripts/$name"
        $ErrorActionPreference = 'Continue'
        $out = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $path 2>&1 | Out-String
        $code = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        $fails = @([regex]::Matches($out, '(?m)^\s*FAIL[: ]\s*(\S+)') | ForEach-Object { $_.Groups[1].Value })
        $marker = $live[$name]
        $case = 'P2_' + ($name -replace '^test-', '' -replace '\.ps1$', '' -replace '-', '_') + '_runs_clean_in_a_consumer'
        Add-Result $case ($code -eq 0 -and $fails.Count -eq 0 -and $out.Contains($marker)) `
            "exit=$code fails=$($fails -join ', ') marker '$marker' seen=$($out.Contains($marker))"
    }
} finally {
    Remove-Item $consumer -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output '===== suite portability tests (issue #349) ====='
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
