# copilot:generated | test-writer | 2026-04-14
# Integration tests for setup-worktree.ps1 and cleanup-worktree.ps1.
#
# Creates a temporary git repository, copies the scripts into it (so that
# their $repoRoot resolves to the temp repo), and exercises each script's
# happy path and error paths.
#
# Usage:
#   .github/scripts/test-worktree-scripts.ps1
#   .github/scripts/test-worktree-scripts.ps1 -Verbose     # show passing tests
#   .github/scripts/test-worktree-scripts.ps1 -KeepTemp    # do not delete temp repo
#
# Exit codes: 0 = all passed, 1 = failures

param(
    [switch]$Verbose,
    [switch]$KeepTemp
)

$ErrorActionPreference = 'Stop'

# ── Harness ─────────────────────────────────────────────────────────────────

$script:passed = 0
$script:failed = 0
$script:errors = @()

function Invoke-WT-Script {
    param(
        [string]$ScriptPath,
        [string[]]$ScriptArgs = @()
    )
    # Run as subprocess so that 'exit N' inside the script does not kill the harness.
    # Use SilentlyContinue locally: stderr captured via 2>&1 produces ErrorRecord objects
    # which would throw under Stop, masking the real $LASTEXITCODE.
    $prevPref = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    $output = powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @ScriptArgs 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prevPref
    $text = ($output | ForEach-Object { "$_" } | Out-String).Trim()
    return @{ Output = $text; ExitCode = $code }
}

function Assert-Exit {
    param(
        [string]$TestName,
        [string]$ScriptPath,
        [string[]]$ScriptArgs,
        [int]$Expected
    )
    try {
        $r = Invoke-WT-Script -ScriptPath $ScriptPath -ScriptArgs $ScriptArgs
        if ($r.ExitCode -eq $Expected) {
            $script:passed++
            if ($Verbose) { Write-Output "  PASS  $TestName" }
        } else {
            $script:failed++
            $detail = if ($Verbose) { "`n        Output: $($r.Output)" } else { '' }
            $script:errors += "FAIL  $TestName -- expected exit $Expected, got $($r.ExitCode)$detail"
        }
    } catch {
        $script:failed++
        $script:errors += "ERROR $TestName -- $($_.Exception.Message)"
    }
}

function Assert-PathExists {
    param([string]$TestName, [string]$Path)
    if (Test-Path $Path) {
        $script:passed++
        if ($Verbose) { Write-Output "  PASS  $TestName" }
    } else {
        $script:failed++
        $script:errors += "FAIL  $TestName -- path does not exist: $Path"
    }
}

function Assert-PathGone {
    param([string]$TestName, [string]$Path)
    if (-not (Test-Path $Path)) {
        $script:passed++
        if ($Verbose) { Write-Output "  PASS  $TestName" }
    } else {
        $script:failed++
        $script:errors += "FAIL  $TestName -- path still exists: $Path"
    }
}

function Assert-GitListContains {
    param([string]$TestName, [string]$RepoRoot, [string]$Pattern)
    Push-Location $RepoRoot
    $wl = (git worktree list 2>&1 | Out-String)
    Pop-Location
    if ($wl -match $Pattern) {
        $script:passed++
        if ($Verbose) { Write-Output "  PASS  $TestName" }
    } else {
        $script:failed++
        $script:errors += "FAIL  $TestName -- pattern '$Pattern' not in worktree list: $wl"
    }
}

function Assert-GitListAbsent {
    param([string]$TestName, [string]$RepoRoot, [string]$Pattern)
    Push-Location $RepoRoot
    $wl = (git worktree list 2>&1 | Out-String)
    Pop-Location
    if ($wl -notmatch $Pattern) {
        $script:passed++
        if ($Verbose) { Write-Output "  PASS  $TestName" }
    } else {
        $script:failed++
        $script:errors += "FAIL  $TestName -- pattern '$Pattern' should be absent from worktree list: $wl"
    }
}

# ── Temp repo setup ──────────────────────────────────────────────────────────

$guid     = [System.Guid]::NewGuid().ToString('N').Substring(0,8)
$tempRoot = Join-Path $env:TEMP "af-wt-test-$guid"
$srcDir   = $PSScriptRoot   # AF .github/scripts/

Write-Output "=== Worktree Script Tests ==="
Write-Output "  Temp repo: $tempRoot"
Write-Output ""

try {
    # --- Create isolated temp repo ---
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    Push-Location $tempRoot
    git init -q 2>&1 | Out-Null
    git checkout -q -b dev  2>&1 | Out-Null
    git config user.email 'test@af-worktree.local'
    git config user.name  'AF Test'
    '# Test repo' | Set-Content README.md
    git add README.md
    git commit -q -m 'initial'
    Pop-Location

    # --- Install scripts into temp repo (.github/scripts/) ---
    $testScriptsDir = Join-Path $tempRoot '.github\scripts'
    New-Item -ItemType Directory -Path $testScriptsDir -Force | Out-Null
    Copy-Item (Join-Path $srcDir 'setup-worktree.ps1')   $testScriptsDir
    Copy-Item (Join-Path $srcDir 'cleanup-worktree.ps1') $testScriptsDir

    # --- af-env.conf: WORKTREE_DIR=wt puts worktrees inside $tempRoot\wt\ ---
    $githubDir = Join-Path $tempRoot '.github'
    New-Item -ItemType Directory -Path $githubDir -Force | Out-Null
    "WORKTREE_DIR=wt`nWORKTREE_BRANCH_PREFIX=agent" |
        Set-Content (Join-Path $githubDir 'af-env.conf')

    $setupSrc = Join-Path $testScriptsDir 'setup-worktree.ps1'
    $cleanSrc = Join-Path $testScriptsDir 'cleanup-worktree.ps1'
    $wtBase   = Join-Path $tempRoot 'wt'

    # ── SECTION 1: setup-worktree.ps1 ─────────────────────────────────────────
    Write-Output "## setup-worktree.ps1"

    # 1. Valid ID: worktree created + registered
    Assert-Exit "Valid ID exits 0" `
        $setupSrc @('-WorkflowId', 'feat-auth', '-BaseBranch', 'dev', '-SkipVenv') 0

    Assert-PathExists "feat-auth directory created" (Join-Path $wtBase 'feat-auth')

    Assert-GitListContains "feat-auth registered in git worktree list" `
        $tempRoot 'feat-auth'

    # 2. Invalid ID: uppercase letters
    Assert-Exit "Uppercase ID rejected (exit 1)" `
        $setupSrc @('-WorkflowId', 'FEAT-AUTH', '-SkipVenv') 1

    # 3. Invalid ID: contains slash
    Assert-Exit "ID with slash rejected (exit 1)" `
        $setupSrc @('-WorkflowId', 'feat/auth', '-SkipVenv') 1

    # 4. Invalid ID: starts with hyphen
    Assert-Exit "ID starting with hyphen rejected (exit 1)" `
        $setupSrc @('-WorkflowId', '-bad-start', '-SkipVenv') 1

    # 5. Nonexistent base branch
    Assert-Exit "Nonexistent base branch rejected (exit 1)" `
        $setupSrc @('-WorkflowId', 'feat-nobranch', '-BaseBranch', 'nonexistent', '-SkipVenv') 1

    # 6. Path collision (feat-auth already exists)
    Assert-Exit "Path collision rejected (exit 1)" `
        $setupSrc @('-WorkflowId', 'feat-auth', '-SkipVenv') 1

    # 7. Second valid worktree (parallel)
    Assert-Exit "Second worktree (feat-beta) exits 0" `
        $setupSrc @('-WorkflowId', 'feat-beta', '-BaseBranch', 'dev', '-SkipVenv') 0

    Assert-PathExists "feat-beta directory created" (Join-Path $wtBase 'feat-beta')

    # ── SECTION 2: cleanup-worktree.ps1 ───────────────────────────────────────
    Write-Output ""
    Write-Output "## cleanup-worktree.ps1"

    # Create worktrees directly for isolated cleanup tests
    Push-Location $tempRoot
    $wt3Path = Join-Path $wtBase 'fix-db'
    git worktree add $wt3Path -b agent/fix-db dev -q 2>&1 | Out-Null

    $wt4Path = Join-Path $wtBase 'fix-dirty'
    git worktree add $wt4Path -b agent/fix-dirty dev -q 2>&1 | Out-Null
    # Make fix-dirty worktree dirty
    'uncommitted change' | Set-Content (Join-Path $wt4Path 'dirty.txt')
    Pop-Location

    # 8. Clean worktree: exits 0 + directory removed
    Assert-Exit "Clean worktree removed (exit 0)" `
        $cleanSrc @('-WorkflowId', 'fix-db') 0

    Assert-PathGone "fix-db directory gone after cleanup" $wt3Path

    Assert-GitListAbsent "fix-db absent from git worktree list" `
        $tempRoot 'fix-db'

    # 9. Unregistered workflow ID: exits 1
    Assert-Exit "Unregistered ID rejected (exit 1)" `
        $cleanSrc @('-WorkflowId', 'nonexistent-task') 1

    # 10. Dirty worktree blocked: exits 2
    Assert-Exit "Dirty worktree blocked (exit 2)" `
        $cleanSrc @('-WorkflowId', 'fix-dirty') 2

    # 11. -Force removes dirty worktree: exits 0
    Assert-Exit "Force-removes dirty worktree (exit 0)" `
        $cleanSrc @('-WorkflowId', 'fix-dirty', '-Force') 0

    Assert-PathGone "fix-dirty directory gone after -Force cleanup" $wt4Path

    # 12. Cleanup one of the setup-worktree worktrees (round-trip test)
    Assert-Exit "Round-trip: feat-auth cleaned up (exit 0)" `
        $cleanSrc @('-WorkflowId', 'feat-auth') 0

    Assert-PathGone "feat-auth directory gone after round-trip cleanup" (Join-Path $wtBase 'feat-auth')

} catch {
    $script:failed++
    $script:errors += "SETUP ERROR: $_"
} finally {
    # Step out of the temp dir before deleting it
    Set-Location $env:TEMP -ErrorAction SilentlyContinue

    if (-not $KeepTemp -and (Test-Path $tempRoot)) {
        # Worktrees under $tempRoot\wt\ are inside $tempRoot, so a single recursive
        # Remove-Item cleans everything.  -Force handles read-only git objects.
        Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    } elseif ($KeepTemp) {
        Write-Output ""
        Write-Output "  Temp repo kept at: $tempRoot"
    }
}

# ── Summary ──────────────────────────────────────────────────────────────────

Write-Output ""
Write-Output "=== Results ==="
$total = $script:passed + $script:failed
Write-Output "  $($script:passed)/$total passed"

if ($script:errors.Count -gt 0) {
    Write-Output ""
    foreach ($e in $script:errors) { Write-Output "  $e" }
}

if ($script:failed -gt 0) { exit 1 }
exit 0
