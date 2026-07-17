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

.PARAMETER Preflight
    Run integrity preflight checks before deploy. In this mode, failed checks
    are reported but do not block deployment.

.PARAMETER RequirePreflight
    Run integrity preflight checks before deploy and BLOCK deployment on any
    failed check.

.PARAMETER PreflightMode
    Select preflight profile:
    - quick: test-hooks + validate-skills + audit-tools
    - full:  quick + test-worktree-scripts

.PARAMETER BackupPruneDays
    Automatically delete stale .af-backup-* folders in the target root that
    are older than this many days.
    Set to 0 to disable pruning.
    Precedence: CLI parameter > af-env.conf BACKUP_PRUNE_DAYS > default (14).

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

.EXAMPLE
    .\deploy.ps1 -Preflight -DryRun
    Runs quick integrity checks, reports results, and shows dry-run changes.

.EXAMPLE
    .\deploy.ps1 -RequirePreflight -PreflightMode full
    Runs full integrity checks and blocks deploy if any check fails.

.EXAMPLE
    .\deploy.ps1 -BackupPruneDays 30
    Keeps conflict backups for up to 30 days and prunes older ones.
#>
[CmdletBinding()]
param(
    [string]$TargetDir,
    [switch]$DryRun,
    [switch]$Diff,
    [switch]$Force,
    [switch]$UpdateHashes,
    [switch]$Preflight,
    [switch]$RequirePreflight,
    [ValidateSet('quick', 'full')]
    [string]$PreflightMode = 'quick',
    [int]$BackupPruneDays = -1
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
$TargetAFEnv = Join-Path $TargetGitHub 'af-env.conf'
$script:BackupPruneDaysFromCli = $PSBoundParameters.ContainsKey('BackupPruneDays')

function Get-AFEnvValue {
    param(
        [string]$Key,
        [string]$Default = ''
    )

    if (-not (Test-Path $TargetAFEnv)) { return $Default }
    $match = Select-String -Path $TargetAFEnv -Pattern "^$([regex]::Escape($Key))=(.+)$" -ErrorAction SilentlyContinue
    if (-not $match) { return $Default }
    return $match.Matches[0].Groups[1].Value.Trim()
}

# ── Agent model tier resolution ────────────────────────────────────────────
# Subagent .agent.md files carry a tier placeholder (__AF_TIER_PREMIUM__ etc.)
# in their `model:` frontmatter. At deploy time it is replaced with the concrete
# model list for that tier, resolved from the TARGET project's af-env.conf
# (AF_MODEL_TIER_*) or, if unset, the curated defaults below. A multi-entry list
# becomes a YAML array so VS Code tries each model until one is available
# (drift-resilient). Curate these defaults when the model line-up changes.
$script:TierDefaults = @{
    PREMIUM   = 'Claude Opus 4.8 (copilot), Claude Opus 4.7 (copilot), Claude Sonnet 5 (copilot)'
    BALANCED  = 'Claude Sonnet 5 (copilot), Claude Sonnet 4.6 (copilot), Claude Sonnet 4.5 (copilot)'
    EFFICIENT = 'Claude Haiku 4.5 (copilot), Claude Sonnet 5 (copilot)'
}
function Get-TierModels([string]$Tier) {
    $val = Get-AFEnvValue -Key "AF_MODEL_TIER_$Tier" -Default ''
    if (-not $val) { $val = $script:TierDefaults[$Tier] }
    return @($val -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
function Resolve-TierTokens([string]$Text) {
    $nl = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    foreach ($tier in 'PREMIUM', 'BALANCED', 'EFFICIENT') {
        $token = "__AF_TIER_${tier}__"
        if ($Text -notmatch [regex]::Escape($token)) { continue }
        $models = Get-TierModels $tier
        if ($models.Count -le 1) {
            $repl = "model: $($models[0])"
        } else {
            $repl = "model:$nl" + (($models | ForEach-Object { "  - $_" }) -join $nl)
        }
        # Match the whole `model: <token>` line without consuming the line break
        # (lookahead), so CRLF/LF endings are preserved. Model names contain no
        # '$', so a literal replacement string is safe.
        $pattern = '(?m)^model:[ \t]*' + [regex]::Escape($token) + '[ \t]*(?=\r?\n|$)'
        $Text = [regex]::Replace($Text, $pattern, $repl)
    }
    return $Text
}
function Get-TierTransform([string]$Source) {
    # Returns transformed content if the file carries a tier token, else $null.
    $raw = [System.IO.File]::ReadAllText($Source)
    if ($raw -notmatch '__AF_TIER_(PREMIUM|BALANCED|EFFICIENT)__') { return $null }
    return (Resolve-TierTokens $raw)
}
function Get-BytesHashUpper([byte[]]$Bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $h = $sha.ComputeHash($Bytes) } finally { $sha.Dispose() }
    return (($h | ForEach-Object { $_.ToString('X2') }) -join '')
}
function Get-StringHashUpper([string]$Text) {
    return (Get-BytesHashUpper ((New-Object System.Text.UTF8Encoding($false)).GetBytes($Text)))
}
# Canonical deployed bytes: UTF-8 without BOM, LF line endings, tier tokens
# resolved. Returns $null for binary (non-UTF-8) content so the caller copies it
# verbatim. Keeps deploy.ps1 byte-identical to the MCP deploy's
# resolved_source_bytes, so switching deploy paths produces no spurious EOL diffs.
function Get-CanonicalBytes([string]$Source) {
    $bytes = [System.IO.File]::ReadAllBytes($Source)
    $decoder = New-Object System.Text.UTF8Encoding($false, $true)  # throw on invalid bytes
    try { $text = $decoder.GetString($bytes) } catch { return $null }  # binary -- copy verbatim
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }  # strip BOM
    $text = $text -replace "`r`n", "`n"
    $text = $text -replace "`r", "`n"
    if ($text -match '__AF_TIER_(PREMIUM|BALANCED|EFFICIENT)__') { $text = Resolve-TierTokens $text }
    return (New-Object System.Text.UTF8Encoding($false)).GetBytes($text)
}
function Get-SourceHashResolved([string]$Source) {
    # Hash of the canonical deployed content (LF, no BOM, tier-resolved).
    $canon = Get-CanonicalBytes $Source
    if ($null -eq $canon) { return (Get-FileHash $Source).Hash }
    return (Get-BytesHashUpper $canon)
}

function Resolve-BackupPruneDays {
    param([int]$CliValue)

    $defaultDays = 14
    if ($script:BackupPruneDaysFromCli -and $CliValue -ge 0) {
        return $CliValue
    }

    $fromConf = Get-AFEnvValue -Key 'BACKUP_PRUNE_DAYS' -Default ''
    if ($fromConf -and $fromConf -match '^\d+$') {
        return [int]$fromConf
    }

    return $defaultDays
}

function Get-CurrentGitBranch {
    param([string]$RepoDir)

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return '' }
    try {
        return (& git -C $RepoDir branch --show-current 2>$null).Trim()
    } catch {
        return ''
    }
}

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
# Python bytecode caches regenerate whenever a hook/script test runs; they must
# never enter the deploy payload. Exclude them from every file enumeration.
function Test-DeployIgnored([string]$FullPath) {
    return ($FullPath -match '[\\/]__pycache__[\\/]') -or ($FullPath -match '\.py[co]$')
}
function Get-AFSourceFiles {
    # Returns relative paths under .github/ (excludes vscode files)
    $files = @()
    foreach ($dir in $ManifestDirs) {
        $srcDir = Join-Path $SourceGitHub $dir
        if (Test-Path $srcDir) {
            Get-ChildItem $srcDir -Recurse -File | Where-Object { -not (Test-DeployIgnored $_.FullName) } | ForEach-Object {
                $rel = ($_.FullName.Substring($SourceGitHub.Length).TrimStart('\', '/')) -replace '\\', '/'
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
                # Normalize keys to forward slashes so a baseline written on Windows
                # (backslash keys) matches the forward-slash manifest/customizable set.
                $hashes[($Matches[1].Trim() -replace '\\', '/')] = $Matches[2].Trim()
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
    [System.IO.File]::WriteAllText($path, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
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

function Invoke-PruneOldBackups {
    param(
        [string]$RootDir,
        [int]$Days,
        [string]$ActiveBackupDir
    )

    if ($Days -le 0) { return }

    $cutoff = (Get-Date).AddDays(-$Days)
    $staleBackups = @(Get-ChildItem -Path $RootDir -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -like '.af-backup-*' -and
            $_.LastWriteTime -lt $cutoff -and
            (-not $ActiveBackupDir -or $_.FullName -ne $ActiveBackupDir)
        })

    if ($staleBackups.Count -eq 0) { return }

    Write-Host ""
    Write-Host "=== Backup Prune ===" -ForegroundColor Cyan
    if ($DryRun) {
        Write-Host "  [DRY RUN] Would remove $($staleBackups.Count) stale backup folder(s) older than $Days day(s)." -ForegroundColor Yellow
        foreach ($b in ($staleBackups | Sort-Object LastWriteTime)) {
            Write-Host "  WOULD   $($b.FullName)" -ForegroundColor Yellow
        }
        return
    }

    foreach ($b in ($staleBackups | Sort-Object LastWriteTime)) {
        Remove-Item $b.FullName -Recurse -Force
        Write-Host "  PRUNE   $($b.FullName)" -ForegroundColor Cyan
    }
    Write-Host "  Pruned $($staleBackups.Count) stale backup folder(s) older than $Days day(s)." -ForegroundColor Green
}

function Invoke-CleanupConflictBackups {
    param([string]$RootDir)

    $backups = @(Get-ChildItem -Path $RootDir -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like '.af-backup-*' })

    if ($backups.Count -eq 0) { return }

    Write-Host ""
    Write-Host "=== Conflict Backup Cleanup ===" -ForegroundColor Cyan
    if ($DryRun) {
        Write-Host "  [DRY RUN] Would remove $($backups.Count) conflict backup folder(s)." -ForegroundColor Yellow
        foreach ($b in ($backups | Sort-Object LastWriteTime)) {
            Write-Host "  WOULD   $($b.FullName)" -ForegroundColor Yellow
        }
        return
    }

    foreach ($b in ($backups | Sort-Object LastWriteTime)) {
        Remove-Item $b.FullName -Recurse -Force
        Write-Host "  CLEAN   $($b.FullName)" -ForegroundColor Cyan
    }
    Write-Host "  Removed $($backups.Count) conflict backup folder(s)." -ForegroundColor Green
}

function Test-NotebookGitFilterConfig {
    if (-not (Test-Path $TargetAFEnv)) { return 0 }
    $notebooksEnabled = Select-String -Path $TargetAFEnv -Pattern '^NOTEBOOKS_ENABLED=true$' -Quiet
    if (-not $notebooksEnabled) { return 0 }

    $gitattributesPath = Join-Path $TargetDir '.gitattributes'
    if (-not (Test-Path $gitattributesPath)) { return 2 }

    $hasFilter = Select-String -Path $gitattributesPath -Pattern 'filter=nbstripout' -Quiet
    if (-not $hasFilter) { return 2 }

    return 0
}

function Find-PythonCommand {
    $candidates = @('python', 'py', 'python3')
    foreach ($cmd in $candidates) {
        $found = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($found) {
            if ($cmd -eq 'py') {
                return @($found.Source, '-3')
            }
            return @($found.Source)
        }
    }
    return @()
}

function Invoke-IntegrityPreflight {
    param(
        [ValidateSet('quick', 'full')]
        [string]$Mode,
        [switch]$Required
    )

    Write-Host "=== AF Preflight ($Mode) ===" -ForegroundColor Cyan

    $checks = @(
        [PSCustomObject]@{
            Name = 'Hook integration tests'
            Run  = {
                $scriptPath = Join-Path $AFRoot '.github/scripts/test-hooks.ps1'
                & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath | Out-Null
                return $LASTEXITCODE
            }
        },
        [PSCustomObject]@{
            Name = 'Skills validation'
            Run  = {
                $scriptPath = Join-Path $AFRoot '.github/scripts/validate-skills.py'
                $py = @(Find-PythonCommand)
                if (-not $py -or $py.Count -eq 0) {
                    return 127
                }
                if ($py.Count -gt 1) {
                    & $py[0] $py[1] $scriptPath | Out-Null
                } else {
                    & $py[0] $scriptPath | Out-Null
                }
                return $LASTEXITCODE
            }
        },
        [PSCustomObject]@{
            Name = 'Tool audit'
            Run  = {
                $scriptPath = Join-Path $AFRoot '.github/scripts/audit-tools.ps1'
                & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath | Out-Null
                return $LASTEXITCODE
            }
        },
        [PSCustomObject]@{
            Name = 'Notebook git filter alignment (NOTEBOOKS_ENABLED=true)'
            Run  = {
                return (Test-NotebookGitFilterConfig)
            }
        }
    )

    if ($Mode -eq 'full') {
        $checks += [PSCustomObject]@{
            Name = 'Worktree integration tests'
            Run  = {
                $scriptPath = Join-Path $AFRoot '.github/scripts/test-worktree-scripts.ps1'
                & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath | Out-Null
                return $LASTEXITCODE
            }
        }
    }

    $failed = @()
    foreach ($check in $checks) {
        Write-Host "  RUN     $($check.Name)"
        $code = & $check.Run
        if ($code -eq 0) {
            Write-Host "  PASS    $($check.Name)" -ForegroundColor Green
        } else {
            Write-Host "  FAIL    $($check.Name) (exit $code)" -ForegroundColor Red
            $failed += "$($check.Name) [exit $code]"
        }
    }

    if ($failed.Count -eq 0) {
        Write-Host "  RESULT  PASS ($($checks.Count)/$($checks.Count))" -ForegroundColor Green
        Write-Host ""
        return $true
    }

    Write-Host "  RESULT  FAIL ($($checks.Count - $failed.Count)/$($checks.Count))" -ForegroundColor Yellow
    foreach ($f in $failed) { Write-Host "          - $f" -ForegroundColor Yellow }
    Write-Host ""

    if ($Required) {
        Write-Host "Preflight required and failed. Deployment blocked." -ForegroundColor Red
        exit 1
    }

    Write-Host "Preflight failed, but deployment will continue (optional mode)." -ForegroundColor Yellow
    Write-Host ""
    return $false
}

# ── UpdateHashes mode ─────────────────────────────────────────────────────
if ($UpdateHashes) {
    Write-Host ""
    Write-Host "=== Update AF Baseline Hashes ===" -ForegroundColor Cyan
    $sourceFiles = Get-AFSourceFiles
    $hashEntries = @{}
    foreach ($rel in $sourceFiles) {
        $src = Join-Path $SourceGitHub $rel
        $hashEntries[$rel] = Get-SourceHashResolved $src
    }
    foreach ($f in $ManifestVSCodeFiles) {
        $src = Join-Path $SourceVSCode $f
        if (Test-Path $src) {
            $hashEntries["vscode/$f"] = Get-SourceHashResolved $src
        }
    }
    if (-not $DryRun) {
        Write-HashFile $hashEntries
        Write-Host "  Wrote .af-hashes with $($hashEntries.Count) entries (v$AFVersion)" -ForegroundColor Green
    } else {
        Write-Host "  [DRY RUN] Would write .af-hashes with $($hashEntries.Count) entries" -ForegroundColor Yellow
    }
    # When hashes are refreshed, previous conflict backups are no longer needed.
    Invoke-CleanupConflictBackups -RootDir $TargetDir
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
    $canon = Get-CanonicalBytes $Source
    $sourceHash = if ($null -ne $canon) { Get-BytesHashUpper $canon } else { (Get-FileHash $Source).Hash }

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
        if ($null -ne $canon) {
            [System.IO.File]::WriteAllBytes($Target, $canon)
        } else {
            Copy-Item $Source $Target -Force
        }
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
            } elseif ((Get-SourceHashResolved $src) -ne (Get-FileHash $tgt).Hash) {
                $bh = $script:BaselineHashes[$rel]
                if ($bh) {
                    $sh = Get-SourceHashResolved $src
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
                Get-ChildItem $tgtDir -Recurse -File | Where-Object { -not (Test-DeployIgnored $_.FullName) } | ForEach-Object {
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
                $sh = Get-SourceHashResolved $src
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
if ($Preflight -or $RequirePreflight) {
    [void](Invoke-IntegrityPreflight -Mode $PreflightMode -Required:$RequirePreflight)
}

$resolvedBackupPruneDays = Resolve-BackupPruneDays -CliValue $BackupPruneDays
if ($resolvedBackupPruneDays -lt 0 -or $resolvedBackupPruneDays -gt 3650) {
    Write-Error 'BackupPruneDays must be in range 0..3650 (CLI or af-env.conf BACKUP_PRUNE_DAYS).'
    exit 1
}

Write-Host ""
Write-Host "=== AF Deployment ===" -ForegroundColor Cyan
Write-Host "  Source  : $AFRoot"
Write-Host "  Target  : $TargetDir"
Write-Host "  Version : $AFVersion"
if ($resolvedBackupPruneDays -gt 0) {
    Write-Host "  Backup prune: enabled (older than $resolvedBackupPruneDays day(s))"
} else {
    Write-Host "  Backup prune: disabled"
}
$currentBranch = Get-CurrentGitBranch -RepoDir $TargetDir
if ($currentBranch -like 'agent/*') {
    Write-Host "  WARNING: Target repo is on '$currentBranch'. Prefer running framework rollouts on dev/main." -ForegroundColor Yellow
}
if ($DryRun) { Write-Host '  [DRY RUN -- no changes will be made]' -ForegroundColor Yellow }
Write-Host ""

# Deploy .github/ directories
Write-Host "  .github/ directories:" -ForegroundColor White
foreach ($dir in $ManifestDirs) {
    $srcDir = Join-Path $SourceGitHub $dir
    if (-not (Test-Path $srcDir)) { continue }
    Get-ChildItem $srcDir -Recurse -File | Where-Object { -not (Test-DeployIgnored $_.FullName) } | ForEach-Object {
        $rel = ($_.FullName.Substring($SourceGitHub.Length).TrimStart('\', '/')) -replace '\\', '/'
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
    $vc = ($versionContent -replace "`r`n", "`n" -replace "`r", "`n")
    if (-not $vc.EndsWith("`n")) { $vc += "`n" }
    [System.IO.File]::WriteAllText($DeployedVersionFile, $vc, (New-Object System.Text.UTF8Encoding($false)))
}
Write-Host "  WRITE   .github/.af-version" -ForegroundColor Cyan

# ── Stale activation check ─────────────────────────────────────────────────
# Warn when a project has activated a skill (skills/{name}/) but the
# _available/{name}/SKILL.md copy is newer. This happens when AF updates
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
    Write-Host "  To resolve conflicts: ask the agent to merge, then run -UpdateHashes (the MCP af_resolve_conflicts prompt automates this)." -ForegroundColor Yellow
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

# ── Curated skills reminder ────────────────────────────────────────────────
# If the project has a curated-assignments.json, remind the user to reapply
# curated skill state after deploy (agent sections, activated/deactivated folders).
$curatedJsonPath = Join-Path $TargetGitHub 'skills\curated-assignments.json'
if (Test-Path $curatedJsonPath) {
    Write-Host ""
    Write-Host "  Post-deploy step: curated skills detected." -ForegroundColor Cyan
    Write-Host "  A deploy overwrites AF-owned files (agents) and resets curated skill assignments." -ForegroundColor Cyan
    Write-Host "  -> Run /af-curate-skills --reapply to restore them (the MCP af_deploy prompt does this automatically)." -ForegroundColor Cyan
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

# Prune stale backups from previous deploy runs
Invoke-PruneOldBackups -RootDir $TargetDir -Days $resolvedBackupPruneDays -ActiveBackupDir $script:BackupDir

if ($DryRun) {
    $dryRunSummary = [ordered]@{
        mode = 'dry-run'
        created = $script:Stats.Created
        updated = $script:Stats.Updated
        unchanged = $script:Stats.Unchanged
        protected = $script:Stats.Protected
        preserved = $script:Stats.Preserved
        conflict = $script:Stats.Conflict
        backup_prune_days = $resolvedBackupPruneDays
    }
    Write-Host ""
    Write-Host ("  DRYRUN_JSON {0}" -f (($dryRunSummary | ConvertTo-Json -Compress))) -ForegroundColor DarkGray
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
