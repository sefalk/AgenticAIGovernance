# Regression tests for the plan budget commit guard (check-plan-budget.py).
#
# Portable + deterministic: drives the checker directly (no shim/venv coupling)
# inside throwaway git repos, asserting the exit-code contract (0 ok, 1 blocked,
# 2 internal error) and the message content that tells a committer what to do.
# Run from anywhere:
#   pwsh .github/scripts/test-plan-budget.ps1
# Exits non-zero if any scenario fails (CI-friendly).
$ErrorActionPreference = 'Continue'

$scriptDir  = Split-Path -Parent $PSCommandPath
$repoRootAF = (Resolve-Path (Join-Path $scriptDir '..' | Join-Path -ChildPath '..')).Path
$checker    = Join-Path $scriptDir '..' | Join-Path -ChildPath 'hooks/scripts/check-plan-budget.py'
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
    Write-Host 'SKIP: no Python 3 interpreter found; cannot run plan budget tests.'
    exit 0
}

# A plan of a given tier and character count. The filler is prose, not padding
# characters, because the guard measures what a reader would have to read.
function New-PlanText([string]$tier, [int]$chars) {
    $head = "# Implementation Plan`n`n**Status:** IN_PROGRESS`n`n## Scope Assessment`n`n- **Complexity tier:** **$tier**`n`n## Subtasks`n`n"
    if ($tier -eq '') {
        $head = "# Implementation Plan`n`n**Status:** IN_PROGRESS`n`n## Subtasks`n`n"
    }
    $line = "- **Action:** extract the alignment status mapping into a pure function.`n"
    $body = ''
    while (($head.Length + $body.Length) -lt $chars) { $body += $line }
    return $head + $body
}

# Runs the checker with cwd=$repo; returns exit code and combined output.
function Invoke-Checker([string]$repo) {
    Push-Location $repo
    try {
        $out = & $python $checker 2>&1 | Out-String
        return [pscustomobject]@{ Code = $LASTEXITCODE; Output = $out }
    } finally { Pop-Location }
}

function New-PlanRepo([switch]$NoConf) {
    $repo = Join-Path ([IO.Path]::GetTempPath()) ("pbg-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    Push-Location $repo
    try {
        git init -q
        git config user.email t@example.com; git config user.name tester
        git config core.autocrlf false  # keep line-ending warnings out of the assertions
        New-Item -ItemType Directory -Path '.github' -Force | Out-Null
        if (-not $NoConf) {
            "PLAN_BUDGET_TRIVIAL_TOKENS=0`nPLAN_BUDGET_STANDARD_TOKENS=3000`nPLAN_BUDGET_DEEP_TOKENS=12000" |
                Set-Content '.github/af-env.conf' -NoNewline
        }
        New-Item -ItemType Directory -Path 'docs/plans' -Force | Out-Null
    } finally { Pop-Location }
    return $repo
}

# Writes a plan into the fixture and stages it.
function Add-Plan([string]$repo, [string]$relative, [string]$text) {
    $full = Join-Path $repo $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
    [IO.File]::WriteAllText($full, $text)
    git -C $repo add -- ":(literal)$relative" | Out-Null
}

$results = [ordered]@{}
$repos = @()
try {
    # A: a Standard plan over its ceiling is blocked.
    $repo = New-PlanRepo; $repos += $repo
    Add-Plan $repo 'docs/plans/feat-2026-08-18-big.md' (New-PlanText 'Standard' 16000)
    $r = Invoke-Checker $repo
    $results['A_standard_over_blocked']   = $r.Code -eq 1
    $results['A_message_names_budget']    = $r.Output -match 'over 3,000'
    $results['A_message_names_the_file']  = $r.Output -match 'feat-2026-08-18-big\.md'

    # B: the same repo with a plan inside the ceiling stays silent.
    $repo = New-PlanRepo; $repos += $repo
    Add-Plan $repo 'docs/plans/fix-2026-08-18-small.md' (New-PlanText 'Standard' 4000)
    $r = Invoke-Checker $repo
    $results['B_standard_under_allowed']  = $r.Code -eq 0
    $results['B_passing_commit_is_quiet'] = $r.Output.Trim() -eq ''

    # C: the tier is read, not assumed -- the same text as Deep passes.
    $repo = New-PlanRepo; $repos += $repo
    Add-Plan $repo 'docs/plans/feat-2026-08-18-deep.md' (New-PlanText 'Deep' 16000)
    $results['C_deep_gets_deep_budget'] = (Invoke-Checker $repo).Code -eq 0

    # D: a Deep plan is still bounded -- the tail is what the ceiling is for.
    $repo = New-PlanRepo; $repos += $repo
    Add-Plan $repo 'docs/plans/feat-2026-08-18-huge.md' (New-PlanText 'Deep' 60000)
    $results['D_deep_tail_blocked'] = (Invoke-Checker $repo).Code -eq 1

    # E: a Trivial fix is chartered to have no plan file at all.
    $repo = New-PlanRepo; $repos += $repo
    Add-Plan $repo 'docs/plans/fix-2026-08-18-trivial.md' (New-PlanText 'Trivial' 800)
    $r = Invoke-Checker $repo
    $results['E_trivial_plan_blocked']   = $r.Code -eq 1
    $results['E_message_names_the_rule'] = $r.Output -match 'no plan file'

    # F: an unstated tier is charged Standard -- silence buys nothing.
    $repo = New-PlanRepo; $repos += $repo
    Add-Plan $repo 'docs/plans/fix-2026-08-18-untiered.md' (New-PlanText '' 16000)
    $r = Invoke-Checker $repo
    $results['F_unstated_tier_blocked']    = $r.Code -eq 1
    $results['F_unstated_tier_is_named']   = $r.Output -match 'unstated'

    # G: the template's own placeholder is a comment, not a tier declaration.
    $repo = New-PlanRepo; $repos += $repo
    $placeholder = (New-PlanText '' 16000) -replace '## Subtasks',
        "- **Complexity tier:** <!-- Trivial / Standard / Deep -->`n`n## Subtasks"
    Add-Plan $repo 'docs/plans/fix-2026-08-18-placeholder.md' $placeholder
    $r = Invoke-Checker $repo
    $results['G_placeholder_not_a_tier'] = $r.Code -eq 1 -and $r.Output -match 'unstated'

    # H: WIP.md is a recovery checkpoint, not a plan.
    $repo = New-PlanRepo; $repos += $repo
    Add-Plan $repo 'docs/plans/WIP.md' (New-PlanText 'Standard' 16000)
    $results['H_wip_exempt'] = (Invoke-Checker $repo).Code -eq 0

    # I: markdown outside a plans directory is none of this guard's business.
    $repo = New-PlanRepo; $repos += $repo
    Add-Plan $repo 'docs/notes.md' (New-PlanText 'Standard' 16000)
    $results['I_non_plan_ignored'] = (Invoke-Checker $repo).Code -eq 0

    # J: a project that names its directory differently is still covered.
    $repo = New-PlanRepo; $repos += $repo
    Add-Plan $repo 'planning/plans/feat-2026-08-18-nested.md' (New-PlanText 'Standard' 16000)
    $results['J_nested_plans_dir_covered'] = (Invoke-Checker $repo).Code -eq 1

    # K: the override releases the commit.
    $repo = New-PlanRepo; $repos += $repo
    Add-Plan $repo 'docs/plans/feat-2026-08-18-over.md' (New-PlanText 'Standard' 16000)
    $env:ALLOW_PLAN_BUDGET = '1'
    $results['K_override_allowed'] = (Invoke-Checker $repo).Code -eq 0
    Remove-Item Env:ALLOW_PLAN_BUDGET

    # L: without af-env.conf the built-in defaults still hold a line.
    $repo = New-PlanRepo -NoConf; $repos += $repo
    Add-Plan $repo 'docs/plans/feat-2026-08-18-noconf.md' (New-PlanText 'Standard' 16000)
    $results['L_defaults_without_conf'] = (Invoke-Checker $repo).Code -eq 1

    # Fail-closed: outside any git repo -> git error -> exit 2.
    $noRepo = Join-Path ([IO.Path]::GetTempPath()) ("nogit-" + [guid]::NewGuid().ToString('N').Substring(0, 6))
    New-Item -ItemType Directory -Path $noRepo -Force | Out-Null; $repos += $noRepo
    $results['failclosed_git_error_exit2'] = (Invoke-Checker $noRepo).Code -eq 2
}
finally {
    foreach ($r in $repos) { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host '===== plan budget guard tests ====='
$allPass = $true
foreach ($k in $results.Keys) {
    if (-not $results[$k]) { $allPass = $false }
    Write-Host ("  {0,-32} {1}" -f $k, $(if ($results[$k]) { 'PASS' } else { 'FAIL' }))
}
Write-Host '==================================='
if ($allPass) { Write-Host 'RESULT: ALL GREEN'; exit 0 }
else { Write-Host 'RESULT: FAILURES PRESENT'; exit 1 }
