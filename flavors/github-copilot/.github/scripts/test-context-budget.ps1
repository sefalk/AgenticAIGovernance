# Regression tests for the context budget gate (check-context-budget.py).
#
# Portable + deterministic: drives the checker directly against synthetic
# .github fixtures in throwaway temp dirs, asserting the exit-code contract
# (0 pass, 1 over budget, 2 blocked) across the documented scenarios.
# Run from anywhere:
#   pwsh .github/scripts/test-context-budget.ps1
# Exits non-zero if any scenario fails (CI-friendly).
$ErrorActionPreference = 'Continue'

$scriptDir  = Split-Path -Parent $PSCommandPath
$repoRootAF = (Resolve-Path (Join-Path $scriptDir '..' | Join-Path -ChildPath '..')).Path
$checker    = (Resolve-Path (Join-Path $scriptDir 'check-context-budget.py')).Path

# Resolve a real Python interpreter (skip the Windows Store alias by probing
# --version output).
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
    Write-Host 'SKIP: no Python 3 interpreter found; cannot run context budget tests.'
    exit 0
}

# Builds a synthetic .github tree. Sizes are expressed in tokens; the checker
# estimates bytes/4, so a token count is written as 4x that many bytes.
function New-Fixture {
    param(
        [int]$RootTokens = 100,
        [hashtable]$Instructions = @{},   # name -> @{ Tokens; ApplyTo }  (ApplyTo $null = omit)
        [hashtable]$Agents = @{},         # name -> tokens
        [string]$Conf = $null,
        [switch]$NoInstructionsDir,
        [switch]$NoRootInstructions,
        [switch]$NoAgentsDir
    )
    $base = Join-Path ([IO.Path]::GetTempPath()) ("ctxb-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $gh = Join-Path $base '.github'
    New-Item -ItemType Directory -Path $gh -Force | Out-Null

    if (-not $NoRootInstructions) {
        [IO.File]::WriteAllText((Join-Path $gh 'copilot-instructions.md'), ('x' * ($RootTokens * 4)))
    }
    if (-not $NoInstructionsDir) {
        $instDir = Join-Path $gh 'instructions'
        New-Item -ItemType Directory -Path $instDir -Force | Out-Null
        foreach ($name in $Instructions.Keys) {
            $spec = $Instructions[$name]
            $front = if ($null -eq $spec.ApplyTo) { "---`nname: $name`n---`n" }
                     else { "---`nname: $name`napplyTo: '$($spec.ApplyTo)'`n---`n" }
            $pad = [Math]::Max(0, ($spec.Tokens * 4) - $front.Length)
            [IO.File]::WriteAllText((Join-Path $instDir $name), $front + ('x' * $pad))
        }
    }
    if (-not $NoAgentsDir) {
        $agentDir = Join-Path $gh 'agents'
        New-Item -ItemType Directory -Path $agentDir -Force | Out-Null
        if ($Agents.Count -eq 0) { $Agents = @{ 'stub' = 10 } }
        foreach ($name in $Agents.Keys) {
            [IO.File]::WriteAllText((Join-Path $agentDir "$name.agent.md"), ('x' * ($Agents[$name] * 4)))
        }
    }
    if ($null -ne $Conf) {
        [IO.File]::WriteAllText((Join-Path $gh 'af-env.conf'), $Conf)
    }
    return $gh
}

# Runs the checker against a fixture and returns @{ Code; Output }.
function Invoke-Checker([string]$githubDir, [string[]]$extraArgs = @()) {
    $out = & $python $checker '--github-dir' $githubDir @extraArgs 2>&1 | Out-String
    return @{ Code = $LASTEXITCODE; Output = $out }
}

$results = [ordered]@{}
$fixtures = @()

try {
    $conf = "AF_CONTEXT_BUDGET_TOKENS=1000`nAF_AGENT_CONTEXT_BUDGET_TOKENS=5000`n"

    # A: under budget -> 0
    $gh = New-Fixture -RootTokens 100 -Conf $conf -Instructions @{
        'wide.instructions.md'   = @{ Tokens = 200; ApplyTo = '**' }
        'narrow.instructions.md' = @{ Tokens = 900; ApplyTo = 'src/**/*.py' }
    }
    $fixtures += $gh
    $r = Invoke-Checker $gh
    $results['A_under_budget_passes'] = ($r.Code -eq 0)

    # B: the narrow file must NOT count toward the always-on total.
    #    300 always-on + 900 narrow would breach 1000 if globs were ignored.
    $results['B_narrow_applyTo_excluded'] = ($r.Output -match 'always-on 300')

    # C: over budget -> 1, with a per-file breakdown naming the offender
    $gh = New-Fixture -RootTokens 100 -Conf $conf -Instructions @{
        'huge.instructions.md' = @{ Tokens = 1200; ApplyTo = '**' }
    }
    $fixtures += $gh
    $r = Invoke-Checker $gh
    $results['C_over_budget_fails'] = ($r.Code -eq 1)
    $results['C_breakdown_names_offender'] = ($r.Output -match 'huge\.instructions\.md')

    # D: missing applyTo counts as always-on (conservative) and warns
    $gh = New-Fixture -RootTokens 100 -Conf $conf -Instructions @{
        'noapply.instructions.md' = @{ Tokens = 1200; ApplyTo = $null }
    }
    $fixtures += $gh
    $r = Invoke-Checker $gh
    $results['D_missing_applyTo_counted'] = ($r.Code -eq 1)
    $results['D_missing_applyTo_warns'] = ($r.Output -match 'WARNING.*no applyTo')

    # E: a fat agent breaches the per-agent budget even when always-on is fine
    $gh = New-Fixture -RootTokens 100 -Conf $conf -Agents @{ 'fat' = 6000; 'thin' = 50 } -Instructions @{
        'wide.instructions.md' = @{ Tokens = 200; ApplyTo = '**' }
    }
    $fixtures += $gh
    $r = Invoke-Checker $gh
    $results['E_fat_agent_fails'] = ($r.Code -eq 1)
    $results['E_fat_agent_named'] = ($r.Output -match 'fat')

    # F: BLOCKED (2), not pass, when required inputs are missing
    $gh = New-Fixture -Conf $conf -NoInstructionsDir
    $fixtures += $gh
    $results['F_no_instructions_dir_blocked'] = ((Invoke-Checker $gh).Code -eq 2)

    $gh = New-Fixture -Conf $conf -NoRootInstructions
    $fixtures += $gh
    $results['F_no_root_instructions_blocked'] = ((Invoke-Checker $gh).Code -eq 2)

    $gh = New-Fixture -Conf $conf -NoAgentsDir
    $fixtures += $gh
    $results['F_no_agents_dir_blocked'] = ((Invoke-Checker $gh).Code -eq 2)

    # G: a malformed budget must block, never silently fall back to a default
    $gh = New-Fixture -RootTokens 100 -Conf "AF_CONTEXT_BUDGET_TOKENS=lots`n" -Instructions @{
        'wide.instructions.md' = @{ Tokens = 100; ApplyTo = '**' }
    }
    $fixtures += $gh
    $results['G_malformed_budget_blocked'] = ((Invoke-Checker $gh).Code -eq 2)

    # H: absent af-env.conf falls back to documented defaults and still runs
    $gh = New-Fixture -RootTokens 100 -Instructions @{
        'wide.instructions.md' = @{ Tokens = 100; ApplyTo = '**' }
    }
    $fixtures += $gh
    $results['H_absent_conf_uses_defaults'] = ((Invoke-Checker $gh).Code -eq 0)

    # I: --verbose prints the breakdown on the pass path too
    $r = Invoke-Checker $gh @('--verbose')
    $results['I_verbose_prints_breakdown'] = ($r.Output -match 'always-on set')

    # J: the real payload must satisfy its own budgets
    $realGh = (Resolve-Path (Join-Path $scriptDir '..')).Path
    $results['J_real_payload_within_budget'] = ((Invoke-Checker $realGh).Code -eq 0)

    # --- Conditional set (issue #44) -------------------------------------
    # Before this, the gate measured only applyTo:'**' files -- the smaller
    # half. A narrow glob made a file invisible to the budget, not cheap.
    $condConf = "AF_CONTEXT_BUDGET_TOKENS=1000`nAF_AGENT_CONTEXT_BUDGET_TOKENS=5000`nAF_CONDITIONAL_BUDGET_TOKENS=2000`n"

    # K: the conditional set is reported with each file's own glob, so an
    #    over-broad applyTo is visible at the point the size is shown.
    $gh = New-Fixture -RootTokens 100 -Conf $condConf -Instructions @{
        'wide.instructions.md'   = @{ Tokens = 200; ApplyTo = '**' }
        'narrow.instructions.md' = @{ Tokens = 900; ApplyTo = 'src/**/*.py' }
    }
    $fixtures += $gh
    $r = Invoke-Checker $gh @('--verbose')
    $results['K_conditional_set_reported'] = ($r.Output -match 'conditional set')
    $results['K_conditional_names_file'] = ($r.Output -match 'narrow\.instructions\.md')
    $results['K_conditional_shows_glob'] = ($r.Output -match [regex]::Escape('src/**/*.py'))
    $results['K_conditional_total_correct'] = ($r.Output -match 'conditional 900')

    # L: an always-on file must not be double-counted into the conditional set.
    $results['L_always_on_excluded_from_conditional'] = ($r.Output -notmatch 'wide\.instructions\.md\s+\*\*\s*$')

    # M: the per-agent worst case adds the conditional set to the unconditional
    #    total -- the number the old gate reported as if it were the whole story.
    #    100 root + 200 wide = 300 always-on; agent 50; conditional 900 -> 1,250.
    $gh = New-Fixture -RootTokens 100 -Conf $condConf -Agents @{ 'solo' = 50 } -Instructions @{
        'wide.instructions.md'   = @{ Tokens = 200; ApplyTo = '**' }
        'narrow.instructions.md' = @{ Tokens = 900; ApplyTo = 'src/**/*.py' }
    }
    $fixtures += $gh
    $r = Invoke-Checker $gh @('--verbose')
    $results['M_worst_case_reported'] = ($r.Output -match 'worst case')
    $results['M_worst_case_value'] = ($r.Output -match '1,250')

    # N: an agent whose worst case breaches the agent budget is marked, but the
    #    exit code stays 0 -- gating it would fail every agent for one shared
    #    cause. The teeth are on the conditional total instead (see O).
    $gh = New-Fixture -RootTokens 100 -Conf $condConf -Agents @{ 'solo' = 50 } -Instructions @{
        'wide.instructions.md'   = @{ Tokens = 200; ApplyTo = '**' }
        'narrow.instructions.md' = @{ Tokens = 1900; ApplyTo = 'src/**/*.py' }
    }
    $fixtures += $gh
    $r = Invoke-Checker $gh @('--verbose')
    $results['N_worst_case_over_marked'] = ($r.Output -match 'exceeds agent budget')
    $results['N_worst_case_over_does_not_fail'] = ($r.Code -eq 0)

    # O: the conditional total is enforced, not merely displayed.
    $gh = New-Fixture -RootTokens 100 -Conf $condConf -Instructions @{
        'wide.instructions.md' = @{ Tokens = 200; ApplyTo = '**' }
        'fat.instructions.md'  = @{ Tokens = 2500; ApplyTo = 'tests/**/*.py' }
    }
    $fixtures += $gh
    $r = Invoke-Checker $gh
    $results['O_conditional_over_budget_fails'] = ($r.Code -eq 1)
    $results['O_conditional_names_offender'] = ($r.Output -match 'fat\.instructions\.md')
    $results['O_conditional_fail_is_distinct'] = ($r.Output -match 'conditional set is')

    # P: a malformed conditional budget blocks, exactly like the other budgets.
    #    A budget that silently falls back to a default is not a budget.
    $gh = New-Fixture -RootTokens 100 -Conf "AF_CONDITIONAL_BUDGET_TOKENS=plenty`n" -Instructions @{
        'wide.instructions.md' = @{ Tokens = 100; ApplyTo = '**' }
    }
    $fixtures += $gh
    $results['P_malformed_conditional_budget_blocked'] = ((Invoke-Checker $gh).Code -eq 2)

    # Q: absent conditional budget uses the documented default and still runs.
    $gh = New-Fixture -RootTokens 100 -Instructions @{
        'wide.instructions.md'   = @{ Tokens = 100; ApplyTo = '**' }
        'narrow.instructions.md' = @{ Tokens = 100; ApplyTo = 'src/**/*.py' }
    }
    $fixtures += $gh
    $results['Q_absent_conditional_budget_defaults'] = ((Invoke-Checker $gh).Code -eq 0)

    # R: a payload with no conditional files at all must not divide by zero or
    #    print an empty section.
    $gh = New-Fixture -RootTokens 100 -Conf $condConf -Instructions @{
        'wide.instructions.md' = @{ Tokens = 200; ApplyTo = '**' }
    }
    $fixtures += $gh
    $r = Invoke-Checker $gh @('--verbose')
    $results['R_no_conditional_files_passes'] = ($r.Code -eq 0)
    $results['R_no_conditional_files_reports_zero'] = ($r.Output -match 'conditional 0')
}
finally {
    foreach ($f in $fixtures) {
        $parent = Split-Path -Parent $f
        if ($parent -and (Test-Path $parent)) { Remove-Item $parent -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Write-Host ''
Write-Host '=== Context Budget Gate ==='
$failed = 0
foreach ($name in $results.Keys) {
    if ($results[$name]) { Write-Host "  PASS: $name" }
    else { Write-Host "  FAIL: $name"; $failed++ }
}
Write-Host ''
Write-Host "  Checks passed: $($results.Count - $failed)"
Write-Host "  Checks failed: $failed"
if ($failed -gt 0) { Write-Host '  RESULT: CONTEXT BUDGET GATE IS BROKEN'; exit 1 }
Write-Host '  RESULT: CONTEXT BUDGET GATE IS WORKING'
exit 0
