# Regression tests for the large-file commit guard (check-large-files.py).
# copilot:generated | implementer | 2026-07-13
#
# Portable + deterministic: drives the checker directly (no shim/venv coupling)
# inside throwaway git repos, asserting the exit-code contract (0 ok, 1 blocked,
# 2 internal error) across the documented scenarios. Run from anywhere:
#   pwsh .github/scripts/test-large-file-guard.ps1
# Exits non-zero if any scenario fails (CI-friendly).
$ErrorActionPreference = 'Continue'

$scriptDir  = Split-Path -Parent $PSCommandPath
$repoRootAF = (Resolve-Path (Join-Path $scriptDir '..' | Join-Path -ChildPath '..')).Path
$checker    = Join-Path $scriptDir '..' | Join-Path -ChildPath 'hooks/scripts/check-large-files.py'
$checker    = (Resolve-Path $checker).Path

# Resolve a real Python interpreter (mirror the shim's order; skip the Windows
# Store alias by probing --version output).
function Resolve-Python {
    $candidates = @(
        (Join-Path $repoRootAF '.venv/Scripts/python.exe'),
        (Join-Path $repoRootAF '.venv/bin/python')
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return @($c) } }
    foreach ($name in @('python3', 'python')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) {
            $v = & $cmd.Source --version 2>&1
            if ($LASTEXITCODE -eq 0 -and $v -match 'Python 3') { return @($cmd.Source) }
        }
    }
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) { return @($py.Source, '-3') }
    return $null
}

$python = Resolve-Python
if (-not $python) {
    Write-Host 'SKIP: no Python 3 interpreter found; cannot run large-file guard tests.'
    exit 0
}

function New-BigFile([string]$path, [int]$extra = 1024) {
    $bytes = New-Object byte[] (1048576 + $extra)
    (New-Object Random).NextBytes($bytes)
    [IO.File]::WriteAllBytes($path, $bytes)
}

# Runs the checker with cwd=$repo and returns its exit code.
function Invoke-Checker([string]$repo) {
    Push-Location $repo
    try { & $python $checker *> $null; return $LASTEXITCODE }
    finally { Pop-Location }
}

function New-GuardRepo([string]$allowlist = '') {
    $repo = Join-Path ([IO.Path]::GetTempPath()) ("lfg-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    Push-Location $repo
    try {
        git init -q
        git config user.email t@example.com; git config user.name tester
        New-Item -ItemType Directory -Path '.github' -Force | Out-Null
        "LARGE_FILE_MAX_BYTES=1048576`nLARGE_FILE_ALLOWLIST=$allowlist" |
            Set-Content '.github/af-env.conf' -NoNewline
    } finally { Pop-Location }
    return $repo
}

$results = [ordered]@{}
$repos = @()
try {
    # B: small file allowed -> 0
    $repo = New-GuardRepo; $repos += $repo
    'hello' | Set-Content (Join-Path $repo 'small.txt')
    git -C $repo add small.txt | Out-Null
    $results['B_small_allowed'] = (Invoke-Checker $repo) -eq 0

    # A: large file blocked -> 1
    $repo = New-GuardRepo; $repos += $repo
    New-BigFile (Join-Path $repo 'big.bin')
    git -C $repo add -- ':(literal)big.bin' | Out-Null
    $results['A_large_blocked'] = (Invoke-Checker $repo) -eq 1

    # C: override -> 0
    $env:ALLOW_LARGE_FILES = '1'
    $results['C_override_allowed'] = (Invoke-Checker $repo) -eq 0
    Remove-Item Env:ALLOW_LARGE_FILES

    # D: allowlist glob -> 0
    $repo = New-GuardRepo -allowlist 'assets/*.bin'; $repos += $repo
    New-Item -ItemType Directory -Path (Join-Path $repo 'assets') -Force | Out-Null
    New-BigFile (Join-Path $repo 'assets/big.bin')
    git -C $repo add -- ':(literal)assets/big.bin' | Out-Null
    $results['D_allowlist_allowed'] = (Invoke-Checker $repo) -eq 0

    # E: large file via rename -> 1 (ACMR includes renames)
    $repo = New-GuardRepo; $repos += $repo
    New-BigFile (Join-Path $repo 'orig.bin')
    $env:ALLOW_LARGE_FILES = '1'
    git -C $repo add -- ':(literal)orig.bin' | Out-Null
    git -C $repo commit -qm seed | Out-Null
    Remove-Item Env:ALLOW_LARGE_FILES
    git -C $repo mv orig.bin renamed.bin | Out-Null
    $results['E_rename_blocked'] = (Invoke-Checker $repo) -eq 1

    # F: glob-metachar filename still blocked -> 1 (literal pathspec)
    $repo = New-GuardRepo; $repos += $repo
    New-BigFile (Join-Path $repo 'report[final].bin')
    git -C $repo add -- ':(literal)report[final].bin' | Out-Null
    $results['F_bracket_name_blocked'] = (Invoke-Checker $repo) -eq 1

    # G: non-ASCII filename still blocked -> 1 (utf-8 decoding)
    $repo = New-GuardRepo; $repos += $repo
    $uni = 'rapport_' + [char]0x00e9 + '_' + [char]0x00fc + '.bin'
    New-BigFile (Join-Path $repo $uni)
    git -C $repo add -- ":(literal)$uni" | Out-Null
    $results['G_unicode_name_blocked'] = (Invoke-Checker $repo) -eq 1

    # Fail-closed: outside any git repo -> git error -> exit 2
    $noRepo = Join-Path ([IO.Path]::GetTempPath()) ("nogit-" + [guid]::NewGuid().ToString('N').Substring(0, 6))
    New-Item -ItemType Directory -Path $noRepo -Force | Out-Null; $repos += $noRepo
    $results['failclosed_git_error_exit2'] = (Invoke-Checker $noRepo) -eq 2
}
finally {
    foreach ($r in $repos) { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host '===== large-file guard tests ====='
$allPass = $true
foreach ($k in $results.Keys) {
    if (-not $results[$k]) { $allPass = $false }
    Write-Host ("  {0,-30} {1}" -f $k, $(if ($results[$k]) { 'PASS' } else { 'FAIL' }))
}
Write-Host '=================================='
if ($allPass) { Write-Host 'RESULT: ALL GREEN'; exit 0 }
else { Write-Host 'RESULT: FAILURES PRESENT'; exit 1 }
