<#
.SYNOPSIS
    Deploys the Agent Framework (AF) into a target project.

.DESCRIPTION
    Copies AF-owned files listed in .af-manifest from the framework source
    into a project's .github/ and .vscode/ directories. Uses 3-way merge
    detection (via .af-hashes baseline) to protect project customizations.

    Supports two use cases:
    - UC1 (one-time): Run once to install AF into a project.
    - UC2 (coupled):  Re-run to sync updates from AF source to project.

    The .af-manifest supports annotations:
    - [customizable] -- file contains project-specific content; protected on update
    - [optional]     -- directory may not exist in AF source; no warning if missing
    - [vscode]       -- file deployed to .vscode/ instead of .github/

    Customizable files are protected on update -- they won't be overwritten
    unless -Force is used. When AF has changes to a customizable file, a
    PROTECT message with "review manually" guidance is shown.

    An ephemeral backup directory (.af-backup-{timestamp}) is created before
    files are overwritten. If no conflicts remain after deploy, the backup
    is automatically deleted. If conflicts exist, the backup persists for
    manual recovery.

.PARAMETER TargetDir
    Project root directory. Defaults to parent of the _agent-framework directory.

.PARAMETER DryRun
    Show what would be copied without making changes.

.PARAMETER Diff
    Compare AF source against deployed copy. Shows differences in both
    directions with 3-way merge awareness (useful for UC2 bidirectional feedback).

.PARAMETER Force
    Overwrite customizable files even if they were modified in the project.

.PARAMETER UpdateHashes
    Write baseline hashes from current AF source. Run after resolving
    conflicts to establish the baseline for future 3-way merge detection.

.EXAMPLE
    .\deploy.ps1
    Deploys AF to the parent directory.

.EXAMPLE
    .\deploy.ps1 -TargetDir C:\Projects\MyApp -DryRun
    Shows what would be deployed without making changes.

.EXAMPLE
    .\deploy.ps1 -Diff
    Shows differences between AF source and deployed copy.

.EXAMPLE
    .\deploy.ps1 -UpdateHashes
    Writes baseline hashes after resolving merge conflicts.
#>
[CmdletBinding()]
param(
    [string]$TargetDir,
    [switch]$DryRun,
    [switch]$Diff,
    [switch]$Force,
    [switch]$UpdateHashes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Configuration ──────────────────────────────────────────────────────────
$AFRoot       = $PSScriptRoot
$SourceGitHub = Join-Path $AFRoot '.github'
$SourceVSCode = Join-Path $AFRoot '.vscode'
$ManifestPath = Join-Path $SourceGitHub '.af-manifest'
$VersionPath  = Join-Path $AFRoot 'VERSION'

# Customizable files, optional dirs, and vscode files are derived from
# .af-manifest annotations — no hardcoded arrays.

# ── Resolve paths ──────────────────────────────────────────────────────────
if (-not $TargetDir) {
    $TargetDir = Split-Path $AFRoot -Parent
}
if (-not (Test-Path $TargetDir -PathType Container)) {
    Write-Error "Target directory not found: $TargetDir"
    exit 1
}
$TargetDir = (Resolve-Path $TargetDir).Path

$TargetGitHub = Join-Path $TargetDir '.github'
$TargetVSCode = Join-Path $TargetDir '.vscode'

# ── Read versions ──────────────────────────────────────────────────────────
$AFVersion = if (Test-Path $VersionPath) {
    (Get-Content $VersionPath -Raw).Trim()
} else { 'unknown' }

$DeployedVersionFile = Join-Path $TargetGitHub '.af-version'
$DeployedInfo = $null
if (Test-Path $DeployedVersionFile) {
    $DeployedInfo = Get-Content $DeployedVersionFile -Raw
}

# ── Parse manifest with annotations ───────────────────────────────────────
# Format: path  [annotation1, annotation2]
#   [customizable] — project may modify; protected on update
#   [optional]     — may not exist in AF source; no warning if missing
#   [vscode]       — deployed to .vscode/ instead of .github/

if (-not (Test-Path $ManifestPath)) {
    Write-Error ".af-manifest not found at: $ManifestPath"
    exit 1
}

$ManifestDirs        = @()
$ManifestFiles       = @()
$ManifestVSCodeFiles = @()
$script:CustomizableFiles = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
$script:OptionalDirs = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
$script:OptionalFiles = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)

foreach ($rawLine in (Get-Content $ManifestPath)) {
    $line = $rawLine.Trim()
    if (-not $line -or $line.StartsWith('#')) { continue }

    # Parse annotations from end of line: path  [ann1, ann2]
    $annotations = @()
    $entryPath = $line
    if ($line -match '^(.+?)\s+\[(.+)\]\s*$') {
        $entryPath = $Matches[1].Trim()
        $annotations = ($Matches[2] -split ',') | ForEach-Object { $_.Trim().ToLower() }
    }

    $isVSCode       = $annotations -contains 'vscode'
    $isCustomizable = $annotations -contains 'customizable'
    $isOptional     = $annotations -contains 'optional'

    if ($entryPath.EndsWith('/')) {
        $dirName = $entryPath.TrimEnd('/')
        $ManifestDirs += $dirName
        if ($isOptional) { [void]$script:OptionalDirs.Add($dirName) }
    } elseif ($isVSCode) {
        $ManifestVSCodeFiles += $entryPath
        if ($isOptional) { [void]$script:OptionalFiles.Add($entryPath) }
    } else {
        $ManifestFiles += $entryPath
        if ($isOptional) { [void]$script:OptionalFiles.Add($entryPath) }
    }

    if ($isCustomizable) {
        $customKey = if ($isVSCode) { "vscode/$entryPath" } else { $entryPath }
        [void]$script:CustomizableFiles.Add($customKey)
    }
}

# Files within manifest directories are annotation-only (deployed via dir
# traversal). Filter them out to avoid duplicate processing.
$ManifestRootFiles = @()
foreach ($f in $ManifestFiles) {
    $inDir = $false
    foreach ($d in $ManifestDirs) {
        if ($f.StartsWith("$d/")) { $inDir = $true; break }
    }
    if (-not $inDir) { $ManifestRootFiles += $f }
}

# ── Manifest validation ───────────────────────────────────────────────────
foreach ($dir in $ManifestDirs) {
    $srcDir = Join-Path $SourceGitHub $dir
    if (-not (Test-Path $srcDir) -and -not $script:OptionalDirs.Contains($dir)) {
        Write-Host "  WARNING: Manifest directory '$dir/' not found in AF source" -ForegroundColor Yellow
    }
}
foreach ($f in $ManifestRootFiles) {
    $src = Join-Path $SourceGitHub $f
    if (-not (Test-Path $src) -and -not $script:OptionalFiles.Contains($f)) {
        Write-Host "  WARNING: Manifest file '$f' not found in AF source" -ForegroundColor Yellow
    }
}
foreach ($f in $ManifestVSCodeFiles) {
    $src = Join-Path $SourceVSCode $f
    if (-not (Test-Path $src) -and -not $script:OptionalFiles.Contains($f)) {
        Write-Host "  WARNING: Manifest vscode file '$f' not found in AF source" -ForegroundColor Yellow
    }
}

# ── Counters ───────────────────────────────────────────────────────────────
$script:Stats = @{ Created = 0; Updated = 0; Unchanged = 0; Protected = 0; Conflict = 0; Preserved = 0 }
$script:BackupDir = $null
$script:BackupCount = 0

# ── Collect all source files ───────────────────────────────────────────────
function Get-AFSourceFiles {
    # Returns relative paths under .github/ (excludes vscode files)
    $files = @()
    foreach ($dir in $ManifestDirs) {
        $srcDir = Join-Path $SourceGitHub $dir
        if (Test-Path $srcDir) {
            Get-ChildItem $srcDir -Recurse -File | ForEach-Object {
                $rel = $_.FullName.Substring($SourceGitHub.Length).TrimStart('\', '/')
                $files += $rel
            }
        }
    }
    foreach ($f in $ManifestRootFiles) {
        if (Test-Path (Join-Path $SourceGitHub $f)) { $files += $f }
    }
    return $files
}

# ── Hash-based 3-way merge ────────────────────────────────────────────────
function Read-HashFile {
    $hashes = @{}
    $path = Join-Path $TargetGitHub '.af-hashes'
    if (Test-Path $path) {
        Get-Content $path | ForEach-Object {
            if ($_ -match '^([^#=]+)=(.+)$') {
                $hashes[$Matches[1].Trim()] = $Matches[2].Trim()
            }
        }
    }
    return $hashes
}

function Write-HashFile {
    param([hashtable]$Hashes)
    $path = Join-Path $TargetGitHub '.af-hashes'
    $lines = @(
        "# AF deployment baseline hashes"
        "# Updated: $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')"
        "# Version: $AFVersion"
    )
    $Hashes.GetEnumerator() | Sort-Object Key | ForEach-Object {
        $lines += "$($_.Key)=$($_.Value)"
    }
    Set-Content -Path $path -Value ($lines -join "`n")
}

$script:BaselineHashes = Read-HashFile
$script:HasBaseline = $script:BaselineHashes.Count -gt 0
$script:DeployedHashes = @{}
foreach ($k in $script:BaselineHashes.Keys) {
    $script:DeployedHashes[$k] = $script:BaselineHashes[$k]
}

# ── Helper: show content diff on conflict ──────────────────────────────────
function Show-ContentDiff {
    param(
        [string]$FileA,
        [string]$FileB,
        [int]$MaxLines = 15
    )
    try {
        if (Get-Command git -ErrorAction SilentlyContinue) {
            $diffOutput = & git diff --no-index --color=never -U2 -- $FileA $FileB 2>&1
            $diffLines = ($diffOutput | Out-String) -split "`n"
            # Show only change lines (skip headers)
            $body = @($diffLines | Where-Object {
                $_ -match '^[-+@]' -and $_ -notmatch '^(---|\+\+\+|diff |index )'
            })
            $show = $body | Select-Object -First $MaxLines
            foreach ($l in $show) {
                Write-Host "      $l" -ForegroundColor DarkGray
            }
            if ($body.Count -gt $MaxLines) {
                Write-Host "      ... ($($body.Count - $MaxLines) more lines)" -ForegroundColor DarkGray
            }
        } else {
            $cmp = Compare-Object (Get-Content $FileA) (Get-Content $FileB) |
                   Select-Object -First $MaxLines
            foreach ($c in $cmp) {
                $indicator = if ($c.SideIndicator -eq '<=') { '- ' } else { '+ ' }
                Write-Host "      $indicator$($c.InputObject)" -ForegroundColor DarkGray
            }
        }
    } catch {
        # Diff display is best-effort — never blocks deployment
    }
}

# ── Helper: ephemeral backup before overwrite ──────────────────────────────
function Backup-BeforeOverwrite {
    param(
        [string]$TargetFile,
        [string]$DisplayPath
    )
    if ($DryRun -or -not (Test-Path $TargetFile)) { return }

    if (-not $script:BackupDir) {
        $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
        $script:BackupDir = Join-Path $TargetDir ".af-backup-$timestamp"
    }
    $backupPath = Join-Path $script:BackupDir $DisplayPath
    $backupParent = Split-Path $backupPath -Parent
    if (-not (Test-Path $backupParent)) {
        New-Item -Path $backupParent -ItemType Directory -Force | Out-Null
    }
    Copy-Item $TargetFile $backupPath
    $script:BackupCount++
}

# ── UpdateHashes mode ─────────────────────────────────────────────────────
if ($UpdateHashes) {
    Write-Host ""
    Write-Host "=== Update AF Baseline Hashes ===" -ForegroundColor Cyan
    $sourceFiles = Get-AFSourceFiles
    $hashEntries = @{}
    foreach ($rel in $sourceFiles) {
        $src = Join-Path $SourceGitHub $rel
        $hashEntries[$rel] = (Get-FileHash $src).Hash
    }
    foreach ($f in $ManifestVSCodeFiles) {
        $src = Join-Path $SourceVSCode $f
        if (Test-Path $src) {
            $hashEntries["vscode/$f"] = (Get-FileHash $src).Hash
        }
    }
    if (-not $DryRun) {
        Write-HashFile $hashEntries
        Write-Host "  Wrote .af-hashes with $($hashEntries.Count) entries (v$AFVersion)" -ForegroundColor Green
    } else {
        Write-Host "  [DRY RUN] Would write .af-hashes with $($hashEntries.Count) entries" -ForegroundColor Yellow
    }
    Write-Host ""
    exit 0
}

# ── Publish a single file ──────────────────────────────────────────────────
function Publish-SingleFile {
    param(
        [string]$Source,
        [string]$Target,
        [string]$DisplayPath,
        [string]$HashKey
    )
    if (-not $HashKey) {
        $HashKey = $DisplayPath -replace '^\.github/', ''
    }
    $isCustom = $script:CustomizableFiles.Contains($HashKey)
    $exists = Test-Path $Target
    $sourceHash = (Get-FileHash $Source).Hash

    # ── New file: always deploy ──
    if (-not $exists) {
        Write-Host "  CREATE  $DisplayPath" -ForegroundColor Green
        $script:Stats.Created++
        $script:DeployedHashes[$HashKey] = $sourceHash
    } else {
        $targetHash = (Get-FileHash $Target).Hash

        # ── Identical: nothing to do ──
        if ($sourceHash -eq $targetHash) {
            $script:DeployedHashes[$HashKey] = $sourceHash
            $script:Stats.Unchanged++
            return
        }

        # ── 3-way merge detection ──
        $baselineHash = $script:BaselineHashes[$HashKey]

        if ($baselineHash) {
            $afChanged   = $sourceHash -ne $baselineHash
            $projChanged = $targetHash -ne $baselineHash

            # Customizable files: never auto-overwrite (unless -Force)
            if ($isCustom -and -not $Force) {
                if ($afChanged -and $projChanged) {
                    Write-Host "  CONFLICT $DisplayPath  (both AF and project changed)" -ForegroundColor Red
                    Show-ContentDiff $Source $Target
                    $script:Stats.Conflict++
                } elseif ($afChanged) {
                    Write-Host "  PROTECT $DisplayPath  (AF has changes -- review manually)" -ForegroundColor Yellow
                    $script:Stats.Protected++
                } else {
                    Write-Host "  PRESERVE $DisplayPath  (project customization)" -ForegroundColor Magenta
                    $script:Stats.Preserved++
                }
                return
            }

            # Non-customizable (or Force) 3-way merge
            if ($afChanged -and -not $projChanged) {
                Write-Host "  UPDATE  $DisplayPath" -ForegroundColor Cyan
                $script:Stats.Updated++
                $script:DeployedHashes[$HashKey] = $sourceHash
            } elseif (-not $afChanged -and $projChanged) {
                Write-Host "  PRESERVE $DisplayPath  (project customization)" -ForegroundColor Magenta
                $script:Stats.Preserved++
                return
            } else {
                Write-Host "  CONFLICT $DisplayPath  (both AF and project changed)" -ForegroundColor Red
                Show-ContentDiff $Source $Target
                $script:Stats.Conflict++
                return
            }
        } elseif ($script:HasBaseline) {
            # Hash file exists but file not tracked — new in AF
            if ($isCustom -and -not $Force) {
                Write-Host "  PROTECT $DisplayPath  (new in AF, customizable -- review manually)" -ForegroundColor Yellow
                $script:Stats.Protected++
                return
            }
            Write-Host "  UPDATE  $DisplayPath" -ForegroundColor Cyan
            $script:Stats.Updated++
            $script:DeployedHashes[$HashKey] = $sourceHash
        } else {
            # No hash file — bootstrap — conservative
            if ($isCustom -and -not $Force) {
                Write-Host "  PROTECT $DisplayPath  (customizable -- use -Force to overwrite)" -ForegroundColor Yellow
                $script:Stats.Protected++
                return
            }
            Write-Host "  CONFLICT $DisplayPath  (no baseline -- run -UpdateHashes after resolving)" -ForegroundColor Red
            Show-ContentDiff $Source $Target
            $script:Stats.Conflict++
            return
        }
    }

    # Perform the copy (with backup for existing files)
    if (-not $DryRun) {
        Backup-BeforeOverwrite -TargetFile $Target -DisplayPath $DisplayPath
        $dir = Split-Path $Target -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item $Source $Target -Force
    }
}

# ══════════════════════════════════════════════════════════════════════════
# DIFF MODE
# ══════════════════════════════════════════════════════════════════════════
if ($Diff) {
    try {
        Write-Host ""
        Write-Host "=== AF Deployment Diff ===" -ForegroundColor Cyan
        Write-Host "  AF source version : $AFVersion"
        $deployedVer = if ($DeployedInfo) { ($DeployedInfo -split "`n")[0] } else { '(not deployed)' }
        Write-Host "  Deployed version  : $deployedVer"
        Write-Host ""

        $sourceFiles = Get-AFSourceFiles
        $diffs = @()

        # Source -> project: files in AF that are missing or differ in project
        foreach ($rel in $sourceFiles) {
            $src = Join-Path $SourceGitHub $rel
            $tgt = Join-Path $TargetGitHub $rel
            if (-not (Test-Path $tgt)) {
                $diffs += [PSCustomObject]@{ File = ".github/$rel"; Direction = '-> project'; Status = 'New in AF (not deployed)' }
            } elseif ((Get-FileHash $src).Hash -ne (Get-FileHash $tgt).Hash) {
                $bh = $script:BaselineHashes[$rel]
                if ($bh) {
                    $sh = (Get-FileHash $src).Hash
                    $th = (Get-FileHash $tgt).Hash
                    if (($sh -ne $bh) -and ($th -eq $bh)) {
                        $diffs += [PSCustomObject]@{ File = ".github/$rel"; Direction = '-> UPDATE'; Status = 'AF changed (safe to deploy)' }
                    } elseif (($sh -eq $bh) -and ($th -ne $bh)) {
                        $diffs += [PSCustomObject]@{ File = ".github/$rel"; Direction = '<- CUSTOM'; Status = 'Project customized (preserved)' }
                    } else {
                        $diffs += [PSCustomObject]@{ File = ".github/$rel"; Direction = '!! CONFLICT'; Status = 'Both AF and project changed' }
                    }
                } else {
                    $diffs += [PSCustomObject]@{ File = ".github/$rel"; Direction = '<->'; Status = 'Modified (no baseline)' }
                }
            }
        }

        # Project -> AF: files added in project but not in AF source
        foreach ($dir in $ManifestDirs) {
            $tgtDir = Join-Path $TargetGitHub $dir
            if (Test-Path $tgtDir) {
                Get-ChildItem $tgtDir -Recurse -File | ForEach-Object {
                    $rel = $_.FullName.Substring($TargetGitHub.Length).TrimStart('\', '/')
                    $src = Join-Path $SourceGitHub $rel
                    if (-not (Test-Path $src)) {
                        $diffs += [PSCustomObject]@{ File = ".github/$rel"; Direction = '<- project'; Status = 'Added in project (not in AF source)' }
                    }
                }
            }
        }

        # Check vscode files from manifest
        foreach ($f in $ManifestVSCodeFiles) {
            $src = Join-Path $SourceVSCode $f
            $tgt = Join-Path $TargetVSCode $f
            if ((Test-Path $src) -and -not (Test-Path $tgt)) {
                $diffs += [PSCustomObject]@{ File = ".vscode/$f"; Direction = '-> project'; Status = 'New in AF (not deployed)' }
            } elseif ((Test-Path $src) -and (Test-Path $tgt)) {
                $sh = (Get-FileHash $src).Hash
                $th = (Get-FileHash $tgt).Hash
                if ($sh -ne $th) {
                    $bh = $script:BaselineHashes["vscode/$f"]
                    if ($bh) {
                        if (($sh -ne $bh) -and ($th -eq $bh)) {
                            $diffs += [PSCustomObject]@{ File = ".vscode/$f"; Direction = '-> UPDATE'; Status = 'AF changed (safe to deploy)' }
                        } elseif (($sh -eq $bh) -and ($th -ne $bh)) {
                            $diffs += [PSCustomObject]@{ File = ".vscode/$f"; Direction = '<- CUSTOM'; Status = 'Project customized (preserved)' }
                        } else {
                            $diffs += [PSCustomObject]@{ File = ".vscode/$f"; Direction = '!! CONFLICT'; Status = 'Both AF and project changed' }
                        }
                    } else {
                        $diffs += [PSCustomObject]@{ File = ".vscode/$f"; Direction = '<->'; Status = 'Modified (no baseline)' }
                    }
                }
            }
        }

        if ($diffs.Count -eq 0) {
            Write-Host "  No differences. Deployment is in sync." -ForegroundColor Green
        } else {
            $diffs | Format-Table File, Direction, Status -AutoSize
            Write-Host "  $($diffs.Count) difference(s) found." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  -> project  : New in AF, not yet deployed"
            Write-Host '  <- project  : Added in project, not in AF source'
            Write-Host '  -> UPDATE   : AF changed, project unchanged (safe to deploy)'
            Write-Host '  <- CUSTOM   : Project customized, AF unchanged (preserved)'
            Write-Host '  !! CONFLICT : Both AF and project changed (needs manual merge)'
            Write-Host '  <->         : Modified (no baseline -- run -UpdateHashes)'
        }
        Write-Host ""
    } catch {
        Write-Host ""
        Write-Host "  Error during diff: $_" -ForegroundColor Red
        Write-Host ""
        exit 1
    }
    exit 0
}

# ══════════════════════════════════════════════════════════════════════════
# DEPLOY MODE
# ══════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "=== AF Deployment ===" -ForegroundColor Cyan
Write-Host "  Source  : $AFRoot"
Write-Host "  Target  : $TargetDir"
Write-Host "  Version : $AFVersion"
if ($DryRun) { Write-Host '  [DRY RUN -- no changes will be made]' -ForegroundColor Yellow }
Write-Host ""

# Deploy .github/ directories
Write-Host "  .github/ directories:" -ForegroundColor White
foreach ($dir in $ManifestDirs) {
    $srcDir = Join-Path $SourceGitHub $dir
    if (-not (Test-Path $srcDir)) { continue }
    Get-ChildItem $srcDir -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($SourceGitHub.Length).TrimStart('\', '/')
        Publish-SingleFile -Source $_.FullName `
                          -Target (Join-Path $TargetGitHub $rel) `
                          -DisplayPath ".github/$rel" `
                          -HashKey $rel
    }
}

# Deploy .github/ root files
Write-Host ""
Write-Host "  .github/ root files:" -ForegroundColor White
foreach ($file in $ManifestRootFiles) {
    $src = Join-Path $SourceGitHub $file
    if (-not (Test-Path $src)) { continue }
    Publish-SingleFile -Source $src `
                      -Target (Join-Path $TargetGitHub $file) `
                      -DisplayPath ".github/$file" `
                      -HashKey $file
}

# Deploy vscode files from manifest
if ($ManifestVSCodeFiles.Count -gt 0) {
    Write-Host ""
    Write-Host "  .vscode/:" -ForegroundColor White
    foreach ($f in $ManifestVSCodeFiles) {
        $src = Join-Path $SourceVSCode $f
        if (-not (Test-Path $src)) { continue }
        Publish-SingleFile -Source $src `
                          -Target (Join-Path $TargetVSCode $f) `
                          -DisplayPath ".vscode/$f" `
                          -HashKey "vscode/$f"
    }
}

# Write .af-hashes
if (-not $DryRun) {
    Write-HashFile $script:DeployedHashes
}
Write-Host ""
Write-Host "  WRITE   .github/.af-hashes" -ForegroundColor Cyan

# Write .af-version
$versionContent = @"
version: $AFVersion
deployed: $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
source: $AFRoot
"@
if (-not $DryRun) {
    if (-not (Test-Path $TargetGitHub)) {
        New-Item -ItemType Directory -Path $TargetGitHub -Force | Out-Null
    }
    Set-Content -Path $DeployedVersionFile -Value $versionContent
}
Write-Host "  WRITE   .github/.af-version" -ForegroundColor Cyan

# ── Stale activation check ─────────────────────────────────────────────────
# Warn when a project has activated a skill (skills/{name}/) but the
# _available/{name}/SKILL.md copy is newer. This happens when AAIG updates
# a skill and deploy syncs _available/ but can't know about activated copies.
$staleSkills = @()
$targetAvailable = Join-Path $TargetGitHub 'skills\_available'
$targetSkills    = Join-Path $TargetGitHub 'skills'
if ((Test-Path $targetAvailable) -and (Test-Path $targetSkills)) {
    foreach ($activeDir in (Get-ChildItem $targetSkills -Directory)) {
        if ($activeDir.Name -eq '_available' -or $activeDir.Name.StartsWith('.')) { continue }
        $availCopy = Join-Path $targetAvailable "$($activeDir.Name)\SKILL.md"
        $activeCopy = Join-Path $activeDir.FullName 'SKILL.md'
        if ((Test-Path $availCopy) -and (Test-Path $activeCopy)) {
            $availHash  = (Get-FileHash $availCopy).Hash
            $activeHash = (Get-FileHash $activeCopy).Hash
            if ($availHash -ne $activeHash) {
                $staleSkills += $activeDir.Name
            }
        }
    }
}

# Summary
Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "  Created:   $($script:Stats.Created)"
Write-Host "  Updated:   $($script:Stats.Updated)"
Write-Host "  Unchanged: $($script:Stats.Unchanged)"
if ($script:Stats.Protected -gt 0) {
    Write-Host "  Protected: $($script:Stats.Protected) -- review these manually" -ForegroundColor Yellow
}
if ($script:Stats.Preserved -gt 0) {
    Write-Host "  Preserved: $($script:Stats.Preserved) -- project customizations kept" -ForegroundColor Magenta
}
if ($script:Stats.Conflict -gt 0) {
    Write-Host "  Conflict:  $($script:Stats.Conflict) -- both sides changed, use agent to merge" -ForegroundColor Red
    Write-Host ""
    Write-Host "  To resolve conflicts: ask the agent to merge, then run -UpdateHashes" -ForegroundColor Yellow
}
if ($DryRun) {
    Write-Host ""
    Write-Host '  [DRY RUN -- no files were changed. Remove -DryRun to apply.]' -ForegroundColor Yellow
}
if ($staleSkills.Count -gt 0) {
    Write-Host ""
    Write-Host "  Stale activations ($($staleSkills.Count)): _available/ has newer SKILL.md" -ForegroundColor Yellow
    foreach ($s in $staleSkills | Sort-Object) {
        Write-Host "    - skills/$s/  (re-copy from skills/_available/$s/ to update)" -ForegroundColor Yellow
    }
}

# ── Version-stale detection ────────────────────────────────────────────────
# Warn when files were updated/created but VERSION hasn't changed since last
# deploy. This catches the common mistake of forgetting to bump VERSION.
$filesChanged = $script:Stats.Created + $script:Stats.Updated
if ($filesChanged -gt 0 -and $DeployedInfo) {
    $deployedVerLine = ($DeployedInfo -split "`n") | Where-Object { $_ -match '^version:\s*(.+)' } | Select-Object -First 1
    if ($deployedVerLine -match '^version:\s*(.+)') {
        $previousVer = $Matches[1].Trim()
        if ($previousVer -eq $AFVersion) {
            Write-Host ""
            Write-Host "  WARNING: VERSION is still $AFVersion but $filesChanged file(s) changed." -ForegroundColor Red
            Write-Host "  Did you forget to bump VERSION and update CHANGELOG.md?" -ForegroundColor Red
        }
    }
}

# Backup cleanup
if ($script:BackupDir -and (Test-Path $script:BackupDir)) {
    if ($script:Stats.Conflict -eq 0) {
        Remove-Item $script:BackupDir -Recurse -Force
        Write-Host ""
        Write-Host "  Backup cleaned up (no conflicts)." -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "  Backup: $($script:BackupDir)  ($($script:BackupCount) files)" -ForegroundColor Yellow
        Write-Host "  Delete manually after resolving conflicts." -ForegroundColor Yellow
    }
}

Write-Host ""
exit 0
