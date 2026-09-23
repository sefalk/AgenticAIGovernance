# Regression smoke tests for deploy flag behavior.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$deployScript = Join-Path $repoRoot 'deploy.ps1'

$failures = 0

function Assert-Contains {
    param(
        [string]$Output,
        [string]$Needle,
        [string]$Label
    )

    if ($Output -notmatch [regex]::Escape($Needle)) {
        Write-Host "FAIL: $Label" -ForegroundColor Red
        Write-Host "  Missing: $Needle" -ForegroundColor DarkGray
        $script:failures++
    } else {
        Write-Host "PASS: $Label" -ForegroundColor Green
    }
}

function Assert-Excludes {
    param(
        [string]$Output,
        [string]$Needle,
        [string]$Label
    )

    if ($Output -match [regex]::Escape($Needle)) {
        Write-Host "FAIL: $Label" -ForegroundColor Red
        Write-Host "  Present but should not be: $Needle" -ForegroundColor DarkGray
        $script:failures++
    } else {
        Write-Host "PASS: $Label" -ForegroundColor Green
    }
}

function New-TestTarget {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("af-deploy-test-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $dir '.github') -Force | Out-Null
    return $dir
}

function Invoke-DeployDryRun {
    param([string]$TargetDir, [string[]]$ExtraArgs)

    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $deployScript, '-DryRun', '-TargetDir', $TargetDir)
    if ($ExtraArgs) { $args += $ExtraArgs }
    return (& powershell @args 2>&1 | Out-String)
}

$target1 = New-TestTarget
try {
    $out = Invoke-DeployDryRun -TargetDir $target1
    Assert-Contains -Output $out -Needle 'Backup prune: enabled (older than 14 day(s))' -Label 'Default backup prune is 14 days'
    Assert-Contains -Output $out -Needle 'DRYRUN_JSON {' -Label 'Dry-run emits machine-readable summary'
    Assert-Contains -Output $out -Needle 'Note: Target is not a git repository -- branch checks skipped.' -Label 'Non-repo target says so instead of skipping in silence (#244)'
} finally {
    Remove-Item $target1 -Recurse -Force -ErrorAction SilentlyContinue
}

$target2 = New-TestTarget
try {
    Set-Content -Path (Join-Path $target2 '.github/af-env.conf') -Value @(
        'SRC_DIR=src',
        'BACKUP_PRUNE_DAYS=7'
    )
    $out = Invoke-DeployDryRun -TargetDir $target2
    Assert-Contains -Output $out -Needle 'Backup prune: enabled (older than 7 day(s))' -Label 'af-env BACKUP_PRUNE_DAYS is applied'

    $out = Invoke-DeployDryRun -TargetDir $target2 -ExtraArgs @('-BackupPruneDays', '30')
    Assert-Contains -Output $out -Needle 'Backup prune: enabled (older than 30 day(s))' -Label 'CLI BackupPruneDays overrides af-env'
} finally {
    Remove-Item $target2 -Recurse -Force -ErrorAction SilentlyContinue
}

# What preflight consists of is a different question from what its checks
# conclude, and only the first one is asserted here. Running them to find out
# re-ran test-hooks.ps1 nested inside this suite -- 708 of its 788 seconds, for
# a string comparison whose outcome it never read (#334).
$out = (& powershell -NoProfile -ExecutionPolicy Bypass -File $deployScript -ListPreflightChecks 2>&1 | Out-String)
Assert-Contains -Output $out -Needle 'Hook integration tests' -Label 'Quick profile includes the hook suite'
Assert-Contains -Output $out -Needle 'Notebook git filter alignment (NOTEBOOKS_ENABLED=true)' -Label 'Notebook preflight check is part of the quick set'

# Without this the list could quietly start executing again and every assertion
# above would still pass, just slowly.
Assert-Excludes -Output $out -Needle '  RUN     ' -Label 'Listing the checks does not run them'
Assert-Excludes -Output $out -Needle 'RESULT  ' -Label 'Listing the checks reaches no verdict'

$out = (& powershell -NoProfile -ExecutionPolicy Bypass -File $deployScript -ListPreflightChecks -PreflightMode full 2>&1 | Out-String)
Assert-Contains -Output $out -Needle 'Worktree integration tests' -Label 'Full profile adds the worktree suite'

if ($failures -gt 0) {
    Write-Host "`nDeploy flag tests failed: $failures" -ForegroundColor Red
    exit 1
}

Write-Host "`nAll deploy flag tests passed." -ForegroundColor Green
exit 0
