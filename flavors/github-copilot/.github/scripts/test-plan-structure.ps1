# Regression tests for the plan structure commit guard (check-plan-structure.py).
#
# Portable + deterministic: drives the checker directly (no shim/venv coupling)
# inside throwaway git repos, asserting the exit-code contract (0 ok, 1 blocked,
# 2 internal error) and the message content that tells a committer what to fix.
# Run from anywhere:
#   pwsh .github/scripts/test-plan-structure.ps1
# Exits non-zero if any scenario fails (CI-friendly).
$ErrorActionPreference = 'Continue'

$scriptDir  = Split-Path -Parent $PSCommandPath
$repoRootAF = (Resolve-Path (Join-Path $scriptDir '..' | Join-Path -ChildPath '..')).Path
$checker    = Join-Path $scriptDir '..' | Join-Path -ChildPath 'hooks/scripts/check-plan-structure.py'
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
    Write-Host 'SKIP: no Python 3 interpreter found; cannot run plan structure tests.'
    exit 0
}

# A plan that satisfies every rule. Every negative case is this text with one
# thing taken away, so a failure names the rule that removed it.
$conforming = @'
# Implementation Plan

**Status:** IN_PROGRESS

## Context

Issue #132. The plan is the only artifact no agent reviews.

## Scope Assessment

- **Files affected:** 3
- **Layers touched:** adapters
- **Complexity tier:** Standard
- **Estimated size:** M
- **Risks:** a structural rule can be satisfied with noise

## Subtasks

### 1. Extract the mapping

- **Action:** move the status mapping into a pure function
- **Files:** `mpusage/helper.py`
- **Acceptance criteria:**
  - an unknown status maps to UNKNOWN rather than raising
- **Exit criterion:** domain tests green

## Quality Gates

- ruff clean
'@

$investigation = @'
# Investigation

**Status:** IN_PROGRESS

## Trigger

The guard blocked a commit nobody expected it to block.

## Root Cause Analysis

The heading allowlist knew one template and the directory holds two.

## Fix Description

Detect the kind from the title.

## Validation Approach

A fixture per kind.

## Quality Gates

- ruff clean
'@

# Runs the checker with cwd=$repo; returns exit code and combined output.
function Invoke-Checker([string]$repo) {
    Push-Location $repo
    try {
        $out = & $python $checker 2>&1 | Out-String
        return [pscustomobject]@{ Code = $LASTEXITCODE; Output = $out }
    } finally { Pop-Location }
}

function New-PlanRepo {
    $repo = Join-Path ([IO.Path]::GetTempPath()) ("psg-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    Push-Location $repo
    try {
        git init -q
        git config user.email t@example.com; git config user.name tester
        git config core.autocrlf false  # keep line-ending warnings out of the assertions
        New-Item -ItemType Directory -Path 'docs/plans' -Force | Out-Null
    } finally { Pop-Location }
    return $repo
}

# Writes a document into the fixture and stages it.
function Add-Plan([string]$repo, [string]$relative, [string]$text) {
    $full = Join-Path $repo $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
    [IO.File]::WriteAllText($full, $text)
    git -C $repo add -- ":(literal)$relative" | Out-Null
}

# One fixture repo per case, staged under the default plan path.
function Test-Plan([string]$text, [string]$relative = 'docs/plans/feat-2026-08-18-case.md') {
    $repo = New-PlanRepo
    $script:repos += $repo
    Add-Plan $repo $relative $text
    return Invoke-Checker $repo
}

$results = [ordered]@{}
$repos = @()
try {
    # A: the conforming plan passes, and says nothing while doing so.
    $r = Test-Plan $conforming
    $results['A_conforming_passes']       = $r.Code -eq 0
    $results['A_passing_commit_is_quiet'] = $r.Output.Trim() -eq ''

    # B: a field still holding the template's comment is an unanswered question.
    $r = Test-Plan ($conforming -replace '(?m)^- \*\*Estimated size:\*\* M\r?$',
                                         '- **Estimated size:** <!-- S / M / L -->')
    $results['B_placeholder_blocked'] = $r.Code -eq 1
    $results['B_placeholder_named']   = $r.Output -match 'Estimated size'

    # C: a heading the template does not define -- 45% of the corpus, measured (#26).
    $r = Test-Plan ($conforming -replace '## Quality Gates', "## Root Cause Deep Dive`n`nProse.`n`n## Quality Gates")
    $results['C_invented_section_blocked'] = $r.Code -eq 1
    $results['C_invented_section_named']   = $r.Output -match 'Root Cause Deep Dive'

    # D: a subtask with nothing to verify hands the decision to whoever reads it next.
    $r = Test-Plan ($conforming -replace '(?ms)- \*\*Acceptance criteria:\*\*\r?\n  - [^\r\n]+\r?\n', '')
    $results['D_missing_criteria_blocked'] = $r.Code -eq 1
    $results['D_missing_criteria_named']   = $r.Output -match 'acceptance criteria'

    # E: the label alone is not the criteria.
    $r = Test-Plan ($conforming -replace '(?m)^  - an unknown status maps to UNKNOWN rather than raising\r?$', '')
    $results['E_empty_criteria_blocked'] = $r.Code -eq 1
    $results['E_empty_criteria_named']   = $r.Output -match 'lists none'

    # F: the scope fields the tier and the layer-override rule are read from.
    $r = Test-Plan ($conforming -replace '(?m)^- \*\*Layers touched:\*\* adapters\r?$', '')
    $results['F_scope_field_blocked'] = $r.Code -eq 1
    $results['F_scope_field_named']   = $r.Output -match 'layers touched'

    # G: no tier means no budget and no gate strictness.
    $r = Test-Plan ($conforming -replace '(?m)^- \*\*Complexity tier:\*\* Standard\r?$', '')
    $results['G_missing_tier_blocked'] = $r.Code -eq 1

    # H: a plan with no subtasks plans nothing.
    $r = Test-Plan ($conforming -replace '(?ms)## Subtasks.*?## Quality Gates', '## Quality Gates')
    $results['H_no_subtasks_blocked'] = $r.Code -eq 1

    # I: two subtasks numbered `1.` are two subtasks; the second is not swallowed.
    $duplicate = $conforming -replace '## Quality Gates', @'
### 1. Rename the mapping

- **Action:** rename
- **Acceptance criteria:**
  - the old name is gone
- **Exit criterion:** tests green

## Quality Gates
'@
    $r = Test-Plan $duplicate
    $results['I_duplicate_number_checked'] = $r.Code -eq 1 -and $r.Output -match 'is missing: files'

    # J: Deep plans may group subtasks into phases; a phase is not a subtask.
    $phased = $conforming -replace '(?ms)### 1\..*?## Quality Gates', @'
### Phase 1 -- Extraction

Prose about the phase.

## Quality Gates
'@
    $results['J_phase_heading_allowed'] = (Test-Plan $phased).Code -eq 0

    # K: the plans directory holds two kinds of document; only one has subtasks.
    $results['K_investigation_passes'] = (Test-Plan $investigation).Code -eq 0

    # L: an investigation is checked against its own template, not waved through.
    $r = Test-Plan ($investigation -replace '(?ms)## Fix Description.*?## Validation Approach', '## Validation Approach')
    $results['L_investigation_required_section'] = $r.Code -eq 1 -and $r.Output -match 'fix description'

    # M: DRAFT stands the guard down, but the file is named -- silence would make
    # DRAFT the way out.
    $r = Test-Plan (($conforming -replace '\*\*Status:\*\* IN_PROGRESS', '**Status:** DRAFT') `
                    -replace '(?m)^- \*\*Complexity tier:\*\* Standard\r?$', '')
    $results['M_draft_skipped']    = $r.Code -eq 0
    $results['M_draft_is_named']   = $r.Output -match 'DRAFT'

    # N: WIP.md is a recovery checkpoint, not a plan.
    $results['N_wip_exempt'] =
        (Test-Plan ($conforming -replace '## Subtasks', '## Notes') 'docs/plans/WIP.md').Code -eq 0

    # O: markdown outside a plans directory is none of this guard's business.
    $broken = $conforming -replace '(?ms)## Subtasks.*?## Quality Gates', '## Quality Gates'
    $results['O_non_plan_ignored'] = (Test-Plan $broken 'docs/notes.md').Code -eq 0

    # P: a project that names its directory differently is still covered.
    $results['P_nested_plans_dir_covered'] =
        (Test-Plan $broken 'planning/plans/feat-2026-08-18-nested.md').Code -eq 1

    # Q: the override releases the commit.
    $env:ALLOW_PLAN_STRUCTURE = '1'
    $results['Q_override_allowed'] = (Test-Plan $broken).Code -eq 0
    Remove-Item Env:ALLOW_PLAN_STRUCTURE

    # Fail-closed: outside any git repo -> git error -> exit 2.
    $noRepo = Join-Path ([IO.Path]::GetTempPath()) ("nogit-" + [guid]::NewGuid().ToString('N').Substring(0, 6))
    New-Item -ItemType Directory -Path $noRepo -Force | Out-Null; $repos += $noRepo
    $results['failclosed_git_error_exit2'] = (Invoke-Checker $noRepo).Code -eq 2
}
finally {
    foreach ($r in $repos) { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host '===== plan structure guard tests ====='
$allPass = $true
foreach ($k in $results.Keys) {
    if (-not $results[$k]) { $allPass = $false }
    Write-Host ("  {0,-34} {1}" -f $k, $(if ($results[$k]) { 'PASS' } else { 'FAIL' }))
}
Write-Host '======================================'
if ($allPass) { Write-Host 'RESULT: ALL GREEN'; exit 0 }
else { Write-Host 'RESULT: FAILURES PRESENT'; exit 1 }
