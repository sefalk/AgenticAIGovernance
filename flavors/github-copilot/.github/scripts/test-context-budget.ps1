# Regression tests for the context budget gate: the measurement
# (check-context-budget.py) and the commit guard that invokes it
# (hooks/scripts/check-context-budget-staged.py).
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
# estimates characters/4, so a token count is written as 4x that many ASCII
# characters (for which bytes and characters coincide).
#
# -RootBytes writes copilot-instructions.md byte-for-byte instead, so a test can
# control line endings, encoding and BOM -- the things the estimator must be
# blind to (issue #59).
function New-Fixture {
    param(
        [int]$RootTokens = 100,
        [byte[]]$RootBytes = $null,
        [hashtable]$Instructions = @{},   # name -> @{ Tokens; ApplyTo }  (ApplyTo $null = omit)
        [hashtable]$Agents = @{},         # name -> tokens
        [hashtable]$Skills = @{},         # dir -> @{ Description; Block } (omit Description = none)
        [string]$Conf = $null,
        [byte[]]$ConfBytes = $null,
        [string[]]$Customizable = @(),    # manifest paths marked [customizable]
        [string[]]$Hashes = $null,        # write .af-hashes listing these paths
        [switch]$NoManifest,
        [switch]$NoInstructionsDir,
        [switch]$NoRootInstructions,
        [switch]$NoAgentsDir
    )
    $base = Join-Path ([IO.Path]::GetTempPath()) ("ctxb-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $gh = Join-Path $base '.github'
    New-Item -ItemType Directory -Path $gh -Force | Out-Null

    if (-not $NoRootInstructions) {
        if ($null -ne $RootBytes) {
            [IO.File]::WriteAllBytes((Join-Path $gh 'copilot-instructions.md'), $RootBytes)
        } else {
            [IO.File]::WriteAllText((Join-Path $gh 'copilot-instructions.md'), ('x' * ($RootTokens * 4)))
        }
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
    if ($Skills.Count -gt 0) {
        $skillRoot = Join-Path $gh 'skills'
        foreach ($dir in $Skills.Keys) {
            $spec = $Skills[$dir]
            $skillDir = Join-Path $skillRoot $dir
            New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
            $front = "---`nname: $dir`n"
            if ($spec.ContainsKey('Description')) {
                $front += if ($spec.Block) { "description: >-`n  $($spec.Description)`n" }
                          else { "description: $($spec.Description)`n" }
            }
            $front += "---`n"
            [IO.File]::WriteAllText((Join-Path $skillDir 'SKILL.md'), $front + ('x' * 400))
        }
    }
    if ($null -ne $ConfBytes) {
        [IO.File]::WriteAllBytes((Join-Path $gh 'af-env.conf'), $ConfBytes)
    } elseif ($null -ne $Conf) {
        [IO.File]::WriteAllText((Join-Path $gh 'af-env.conf'), $Conf)
    }
    # Ownership inputs. Default: a manifest with no [customizable] entries and
    # no .af-hashes, so every file is AF-owned and the pre-split cases keep
    # measuring exactly what they measured before.
    if (-not $NoManifest) {
        $lines = @('# fixture manifest', 'af-env.conf', 'copilot-instructions.md', 'instructions/', 'agents/')
        foreach ($path in $Customizable) { $lines += "$path  [customizable]" }
        [IO.File]::WriteAllText((Join-Path $gh '.af-manifest'), ($lines -join "`n") + "`n")
    }
    if ($null -ne $Hashes) {
        $lines = @('# AF deployment baseline hashes')
        foreach ($path in $Hashes) { $lines += "$path=0000" }
        [IO.File]::WriteAllText((Join-Path $gh '.af-hashes'), ($lines -join "`n") + "`n")
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
    #    own 3,000 + always-on 300 = 3,300 unconditional (passes 5,000);
    #    + 1,900 conditional = 5,200 worst case (over 5,000, marked only).
    $gh = New-Fixture -RootTokens 100 -Conf $condConf -Agents @{ 'solo' = 3000 } -Instructions @{
        'wide.instructions.md'   = @{ Tokens = 200; ApplyTo = '**' }
        'narrow.instructions.md' = @{ Tokens = 1900; ApplyTo = 'src/**/*.py' }
    }
    $fixtures += $gh
    $r = Invoke-Checker $gh @('--verbose')
    $results['N_worst_case_over_marked'] = ($r.Output -match 'worst case .* exceeds')
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

    # --- Estimator invariance (issue #59) --------------------------------
    # A drift gate must be blind to transformations that leave the content the
    # model reads identical. The old estimator was bytes-on-disk/4, so it moved
    # when `core.autocrlf` flipped, when an author typed an em dash, or when an
    # editor added a BOM -- none of which change a single character of content.
    $invConf = "AF_CONTEXT_BUDGET_TOKENS=1000`nAF_AGENT_CONTEXT_BUDGET_TOKENS=5000`nAF_CONDITIONAL_BUDGET_TOKENS=2000`n"

    # Pulls the always-on total off the PASS line, so a case asserts a number
    # rather than the presence of a substring.
    function Get-AlwaysOn([string]$out) {
        if ($out -match 'always-on ([\d,]+)/') { return [int](($Matches[1]) -replace ',', '') }
        return -1
    }

    # 100 lines of 19 characters + newline = 2,000 characters = 500 tok.
    # As CRLF the same content is 2,100 bytes on disk = 525 tok by the old rule.
    $line = ('x' * 19)
    $lfText   = ((@($line) * 100) -join "`n") + "`n"
    $crlfText = ((@($line) * 100) -join "`r`n") + "`r`n"
    $utf8 = [Text.UTF8Encoding]::new($false)

    $ghLf = New-Fixture -RootBytes ($utf8.GetBytes($lfText)) -Conf $invConf
    $fixtures += $ghLf
    $ghCrlf = New-Fixture -RootBytes ($utf8.GetBytes($crlfText)) -Conf $invConf
    $fixtures += $ghCrlf
    $lfTotal   = Get-AlwaysOn (Invoke-Checker $ghLf).Output
    $crlfTotal = Get-AlwaysOn (Invoke-Checker $ghCrlf).Output
    $results['S_crlf_matches_lf'] = ($lfTotal -eq $crlfTotal -and $lfTotal -gt 0)
    # Guards against "equal because both are wrong": 2,000 characters / 4.
    $results['S_line_endings_counted_as_characters'] = ($lfTotal -eq 500)

    # Typographic punctuation costs three bytes and one character. AF
    # instruction files are full of it, so this was a standing 20% inflation.
    $asciiText = ('-' * 400)
    $emDashText = ([string][char]0x2014) * 400
    $ghAscii = New-Fixture -RootBytes ($utf8.GetBytes($asciiText)) -Conf $invConf
    $fixtures += $ghAscii
    $ghEmDash = New-Fixture -RootBytes ($utf8.GetBytes($emDashText)) -Conf $invConf
    $fixtures += $ghEmDash
    $asciiTotal  = Get-AlwaysOn (Invoke-Checker $ghAscii).Output
    $emDashTotal = Get-AlwaysOn (Invoke-Checker $ghEmDash).Output
    $results['T_typographic_punctuation_matches_ascii'] = ($asciiTotal -eq $emDashTotal -and $asciiTotal -gt 0)
    $results['T_punctuation_counted_as_characters'] = ($asciiTotal -eq 100)

    # A BOM is bytes the model never sees. 2,003 characters is chosen so that
    # one extra character crosses a token boundary (2,003/4 = 500, 2,004/4 =
    # 501): at a round length integer division swallows the BOM and the case
    # would pass without ever exercising anything.
    $bom = [byte[]](0xEF, 0xBB, 0xBF)
    $bomBase = $utf8.GetBytes('x' * 2003)
    $ghNoBom = New-Fixture -RootBytes $bomBase -Conf $invConf
    $fixtures += $ghNoBom
    $ghBom = New-Fixture -RootBytes ($bom + $bomBase) -Conf $invConf
    $fixtures += $ghBom
    $noBomTotal = Get-AlwaysOn (Invoke-Checker $ghNoBom).Output
    $results['U_bom_does_not_change_total'] = ((Get-AlwaysOn (Invoke-Checker $ghBom).Output) -eq $noBomTotal -and $noBomTotal -eq 500)

    # ...and a BOM on af-env.conf must not make the first budget unreadable.
    # Budget 1 fails a 100-token payload; a swallowed budget falls back to the
    # documented default and passes, so the exit code separates the two outright.
    $ghBomConf = New-Fixture -RootTokens 100 -ConfBytes ($bom + $utf8.GetBytes("AF_CONTEXT_BUDGET_TOKENS=1`n"))
    $fixtures += $ghBomConf
    $results['U_bom_in_conf_still_read'] = ((Invoke-Checker $ghBomConf).Code -eq 1)

    # Invariance is not blindness: content that really differs must still move
    # the number. Without this, `return 0` would pass every case above.
    $ghMore = New-Fixture -RootBytes ($utf8.GetBytes($lfText + ('y' * 400))) -Conf $invConf
    $fixtures += $ghMore
    $results['V_added_text_still_counts'] = ((Get-AlwaysOn (Invoke-Checker $ghMore).Output) -eq ($lfTotal + 100))

    # Counting characters means decoding, and decoding can fail. A file that is
    # not valid UTF-8 must BLOCK: letting the decode error escape would exit 1,
    # which reads as "over budget" -- a wrong verdict dressed as a real one.
    $ghBad = New-Fixture -RootBytes ([byte[]](0x80, 0x81, 0x82, 0x83)) -Conf $invConf
    $fixtures += $ghBad
    $results['W_invalid_utf8_blocked'] = ((Invoke-Checker $ghBad).Code -eq 2)

    # --- Tokenizer verification (issue #59) ------------------------------
    # The divisor is a measured constant now, not a rule of thumb, so it has
    # to stay falsifiable: a number nobody can re-derive decays back into
    # folklore as soon as the payload's character mix drifts.
    #
    # This runs against the real payload, not a fixture. Fixture text is a run
    # of filler characters, which BPE collapses to a handful of tokens -- a
    # synthetic case here would measure the fixture generator and fail an
    # entirely correct divisor.
    & $python -c 'import tiktoken' 2>&1 | Out-Null
    $hasTiktoken = ($LASTEXITCODE -eq 0)
    $rVerify = Invoke-Checker $realGh @('--verify-tokenizer')
    if ($hasTiktoken) {
        $results['JJ_divisor_still_matches_real_payload'] =
            ($rVerify.Code -eq 0 -and $rVerify.Output -match 'measured ratio')
    }
    else {
        # A verification that could not run is an unknown result. Exiting 0
        # would report "calibration fine" on the strength of a missing import.
        $results['JJ_verify_tokenizer_blocked_without_tiktoken'] = ($rVerify.Code -eq 2)
    }

    # KK: whichever branch ran above, the gate itself must still work where
    #     tiktoken does not exist. Only the source can assert that -- an import
    #     test passes for the wrong reason on a host that has the package. The
    #     pattern is anchored at column zero on purpose: the flag's own import
    #     is indented inside its handler, which is exactly the difference.
    $checkerSrc = Get-Content $checker -Raw
    $results['KK_gate_has_no_toplevel_tokenizer_import'] =
        ($checkerSrc -notmatch '(?m)^import tiktoken' -and $checkerSrc -notmatch '(?m)^from tiktoken')

    # --- Framework share vs project share (issue #107) --------------------
    # One ceiling over both shares meant AF's own files spent most of it and the
    # project inherited the remainder as its allowance. Every consumer failed on
    # arrival, and the only ways out were to raise the ceiling until it passed
    # or to shrink the project's own self-description to fit the leftovers.
    $splitConf = "AF_CONTEXT_BUDGET_TOKENS=1000`nAF_AGENT_CONTEXT_BUDGET_TOKENS=5000`nAF_CONDITIONAL_BUDGET_TOKENS=2000`n"

    # LL: a [customizable] file is the project's, and is not charged to AF.
    $gh = New-Fixture -RootTokens 100 -Conf $splitConf -Customizable @('copilot-instructions.md') `
        -Instructions @{ 'wide.instructions.md' = @{ Tokens = 200; ApplyTo = '**' } }
    $fixtures += $gh
    $r = Invoke-Checker $gh @('--verbose')
    $results['LL_customizable_charged_to_project'] =
        ($r.Output -match '200 tok\s+AF-owned' -and $r.Output -match '100 tok\s+project-owned')

    # MM: a project share with no stated ceiling is measured and named, not
    #     failed. A project that never declared a baseline has not drifted from
    #     one, and inventing one on its behalf is the arrival failure itself.
    $gh = New-Fixture -RootTokens 5000 -Conf $splitConf -Customizable @('copilot-instructions.md') `
        -Instructions @{ 'wide.instructions.md' = @{ Tokens = 200; ApplyTo = '**' } }
    $fixtures += $gh
    $r = Invoke-Checker $gh
    $results['MM_unseeded_project_share_does_not_fail'] = ($r.Code -eq 0)
    $results['MM_unseeded_project_share_is_named'] = ($r.Output -match 'UNBUDGETED')

    # NN: once seeded, the project ceiling has teeth of its own, and says so in
    #     the project's own terms rather than the framework's.
    $seededConf = $splitConf + "AF_PROJECT_CONTEXT_BUDGET_TOKENS=1000`n"
    $gh = New-Fixture -RootTokens 5000 -Conf $seededConf -Customizable @('copilot-instructions.md') `
        -Instructions @{ 'wide.instructions.md' = @{ Tokens = 200; ApplyTo = '**' } }
    $fixtures += $gh
    $r = Invoke-Checker $gh
    $results['NN_seeded_project_over_budget_fails'] = ($r.Code -eq 1)
    $results['NN_project_failure_is_distinct'] = ($r.Output -match 'over its own budget')

    # OO: a project's own instruction file sits in the same directory as AF's
    #     and carries no annotation. The deployment record is what distinguishes
    #     them: AF never shipped it, so it is not AF's to budget.
    $gh = New-Fixture -RootTokens 100 -Conf $splitConf -Instructions @{
        'wide.instructions.md'  = @{ Tokens = 200; ApplyTo = '**' }
        'local.instructions.md' = @{ Tokens = 300; ApplyTo = '**' }
    } -Hashes @('copilot-instructions.md', 'instructions/wide.instructions.md', 'agents/stub.agent.md')
    $fixtures += $gh
    $r = Invoke-Checker $gh @('--verbose')
    $results['OO_undeployed_file_is_project_owned'] = ($r.Output -match '300 tok\s+project\s+local\.instructions\.md')

    # PP: without the manifest neither share can be attributed. Charging the
    #     project's files to AF reproduces the defect; charging AF's files to the
    #     project makes the framework ceiling vacuous. Result unknown, not pass.
    $gh = New-Fixture -RootTokens 100 -Conf $splitConf -NoManifest `
        -Instructions @{ 'wide.instructions.md' = @{ Tokens = 200; ApplyTo = '**' } }
    $fixtures += $gh
    $r = Invoke-Checker $gh
    $results['PP_missing_manifest_blocked'] = ($r.Code -eq 2 -and $r.Output -match 'af-manifest')

    # QQ: the regression #107 describes. An agent that fits must not stop
    #     fitting because the consuming project wrote itself a longer overview.
    #     own 4,000 + AF always-on 200 = 4,200 against 5,000; the project's
    #     2,000 is real cost, reported as worst case, but not AF's to budget.
    $gh = New-Fixture -RootTokens 2000 -Conf $splitConf -Agents @{ 'solo' = 4000 } `
        -Customizable @('copilot-instructions.md') `
        -Instructions @{ 'wide.instructions.md' = @{ Tokens = 200; ApplyTo = '**' } }
    $fixtures += $gh
    $r = Invoke-Checker $gh
    $results['QQ_agent_not_failed_by_project_share'] = ($r.Code -eq 0)

    # RR: seeding records what the project has, so the ceiling is the project's
    #     own baseline rather than a number the framework invented for someone
    #     else's repository.
    $gh = New-Fixture -RootTokens 100 -Conf $splitConf -Customizable @('copilot-instructions.md') `
        -Instructions @{ 'wide.instructions.md' = @{ Tokens = 200; ApplyTo = '**' } }
    $fixtures += $gh
    $confPath = Join-Path $gh 'af-env.conf'
    $r = Invoke-Checker $gh @('--seed-project-budget')
    $seeded = Get-Content $confPath -Raw
    $results['RR_seed_writes_context_key'] = ($r.Code -eq 0 -and $seeded -match 'AF_PROJECT_CONTEXT_BUDGET_TOKENS=150')
    $results['RR_seed_writes_conditional_key'] = ($seeded -match 'AF_PROJECT_CONDITIONAL_BUDGET_TOKENS=\d')
    $results['RR_seeded_project_no_longer_unbudgeted'] =
        ((Invoke-Checker $gh).Output -notmatch 'UNBUDGETED')
    # A seeded budget is a decision someone made. Re-running deploy must not
    # quietly replace it with today's measurement -- that would erase exactly
    # the drift the ceiling exists to detect.
    $r = Invoke-Checker $gh @('--seed-project-budget')
    $results['RR_seed_refuses_silent_overwrite'] = ($r.Code -eq 1 -and $r.Output -match 'refusing to overwrite')
    $results['RR_seed_force_overwrites'] = ((Invoke-Checker $gh @('--seed-project-budget', '--force')).Code -eq 0)

    # XX: the catalogue set. Every skill, agent and instruction file announces
    #     itself by name and description on every request, before anything is
    #     invoked. That payload is always-on and, until issue #206, gated by
    #     nothing -- which is what made adding a skill feel free.
    $catConf = $conf + "AF_CATALOGUE_BUDGET_TOKENS=1000`n"
    $long = 'y' * 600
    $gh = New-Fixture -RootTokens 100 -Conf $catConf -Skills @{
        'alpha' = @{ Description = 'does alpha things' }
        'beta'  = @{ Description = 'does beta things' }
    } -Instructions @{ 'wide.instructions.md' = @{ Tokens = 200; ApplyTo = '**' } }
    $fixtures += $gh
    $r = Invoke-Checker $gh @('--verbose')
    $results['XX_catalogue_reported'] = ($r.Code -eq 0 -and $r.Output -match 'catalogue set')
    $results['XX_catalogue_counts_skills'] = ($r.Output -match 'skills\s+2 entries')
    $results['XX_catalogue_counts_instructions'] = ($r.Output -match 'instructions\s+1 entries')

    # A description is paid for even though the body it advertises is not. Make
    # one long enough to breach and the gate must say so, and say whose it is.
    $gh = New-Fixture -RootTokens 100 -Conf $catConf -Skills @{
        'windbag' = @{ Description = $long + $long + $long + $long + $long + $long + $long }
    }
    $fixtures += $gh
    $r = Invoke-Checker $gh
    $results['XX_catalogue_over_budget_fails'] = ($r.Code -eq 1)
    $results['XX_catalogue_fail_is_distinct'] = ($r.Output -match 'AF catalogue set is')
    $results['XX_catalogue_names_offender'] = ($r.Output -match 'windbag')

    # A skill body is not part of the announcement. Growing it must not move the
    # catalogue total, or the gate would be measuring the wrong payload.
    $gh = New-Fixture -RootTokens 100 -Conf $catConf -Skills @{ 'alpha' = @{ Description = 'does alpha things' } }
    $fixtures += $gh
    $before = (Invoke-Checker $gh @('--verbose')).Output
    Add-Content (Join-Path $gh 'skills/alpha/SKILL.md') ('z' * 40000)
    $after = (Invoke-Checker $gh @('--verbose')).Output
    $catLine = { param($t) if ($t -match '(?m)^\s+([\d,]+) tok\s+skills') { $matches[1] } else { 'nomatch' } }
    $results['XX_skill_body_not_in_catalogue'] =
        ((& $catLine $before) -eq (& $catLine $after) -and (& $catLine $before) -ne 'nomatch')

    # A YAML block scalar is how a long description is normally written. Reading
    # only the first line would score it as two characters -- an undercount that
    # grows with exactly the descriptions worth catching.
    $text = 'a description long enough that someone would reasonably fold it'
    $gh = New-Fixture -RootTokens 100 -Conf $catConf -Skills @{ 'inline' = @{ Description = $text } }
    $fixtures += $gh
    $flat = (Invoke-Checker $gh @('--verbose')).Output
    $gh = New-Fixture -RootTokens 100 -Conf $catConf -Skills @{ 'inline' = @{ Description = $text; Block = $true } }
    $fixtures += $gh
    $folded = (Invoke-Checker $gh @('--verbose')).Output
    $results['XX_block_scalar_matches_inline'] =
        ((& $catLine $flat) -eq (& $catLine $folded) -and (& $catLine $flat) -ne 'nomatch')

    # Dormant skills are not announced, so they cost nothing here. That is also
    # why they are invisible -- see issue #222.
    $gh = New-Fixture -RootTokens 100 -Conf $catConf -Skills @{
        'alpha'   = @{ Description = 'does alpha things' }
        '_parked' = @{ Description = $long }
    }
    $fixtures += $gh
    $r = Invoke-Checker $gh @('--verbose')
    $results['XX_dormant_skill_excluded'] = ($r.Code -eq 0 -and $r.Output -match 'skills\s+1 entries')

    # Announced without a description is the worst of both: it is paid for and
    # it tells the model nothing.
    $gh = New-Fixture -RootTokens 100 -Conf $catConf -Skills @{ 'mute' = @{} }
    $fixtures += $gh
    $results['XX_missing_description_warns'] =
        ((Invoke-Checker $gh).Output -match 'mute.*announced but not discoverable')

    # The project's own catalogue entries are charged to the project, and an
    # unseeded project share is named rather than silently ignored.
    $gh = New-Fixture -RootTokens 100 -Conf $splitConf -Customizable @('instructions/wide.instructions.md') `
        -Instructions @{ 'wide.instructions.md' = @{ Tokens = 200; ApplyTo = '**' } }
    $fixtures += $gh
    $results['XX_unseeded_project_catalogue_named'] =
        ((Invoke-Checker $gh).Output -match 'UNBUDGETED.*catalogue')

    $r = Invoke-Checker $gh @('--seed-project-budget')
    $results['XX_seed_writes_catalogue_key'] =
        ($r.Code -eq 0 -and (Get-Content (Join-Path $gh 'af-env.conf') -Raw) -match 'AF_PROJECT_CATALOGUE_BUDGET_TOKENS=\d')

    # The upgrade path: a project that seeded before this ceiling existed must
    # get the new one without being made to choose between re-baselining the
    # ceilings it already tuned and leaving the new one ungated forever.
    $oldConf = $splitConf + "AF_PROJECT_CONTEXT_BUDGET_TOKENS=150`nAF_PROJECT_CONDITIONAL_BUDGET_TOKENS=150`n"
    $gh = New-Fixture -RootTokens 100 -Conf $oldConf -Customizable @('instructions/wide.instructions.md') `
        -Instructions @{ 'wide.instructions.md' = @{ Tokens = 200; ApplyTo = '**' } }
    $fixtures += $gh
    $r = Invoke-Checker $gh @('--seed-project-budget')
    $written = Get-Content (Join-Path $gh 'af-env.conf') -Raw
    $results['XX_seed_fills_only_the_missing_ceiling'] =
        ($r.Code -eq 0 -and $written -match 'AF_PROJECT_CATALOGUE_BUDGET_TOKENS=\d')
    $results['XX_seed_leaves_tuned_ceilings_alone'] =
        (([regex]::Matches($written, 'AF_PROJECT_CONTEXT_BUDGET_TOKENS=')).Count -eq 1 -and
         $written -match 'AF_PROJECT_CONTEXT_BUDGET_TOKENS=150')

    # SS: deploy is where a consumer gets its baseline. A fresh install that
    #     silently kept the framework's own numbers would ship the arrival
    #     failure again, so both dialects must carry the seeding step. Only
    #     checked where the deploy scripts live -- a consumer has no copy.
    $deployPs1 = Join-Path $repoRootAF 'deploy.ps1'
    $deploySh = Join-Path $repoRootAF 'deploy.sh'
    if ((Test-Path $deployPs1) -and (Test-Path $deploySh)) {
        $results['SS_deploy_ps1_seeds_project_budget'] =
            ((Get-Content $deployPs1 -Raw) -match '--seed-project-budget')
        $results['SS_deploy_sh_seeds_project_budget'] =
            ((Get-Content $deploySh -Raw) -match '--seed-project-budget')
    }

    # --- The commit guard (issue #85) ------------------------------------
    # Everything above measures a directory on request. For months nothing
    # made the request, so the payload drifted 273 tokens over its own
    # ceiling and case J sat red on dev unobserved. These cases pin the
    # guard that asks without being asked.
    $guard = Join-Path $scriptDir '..' | Join-Path -ChildPath 'hooks/scripts/check-context-budget-staged.py'
    $guardConf = "AF_CONTEXT_BUDGET_TOKENS=1000`nAF_AGENT_CONTEXT_BUDGET_TOKENS=5000`nAF_CONDITIONAL_BUDGET_TOKENS=2000`n"

    # Turns a fixture into a git repo with the payload staged. -Prefix nests
    # the payload the way the AF source repo nests its own
    # (flavors/github-copilot/.github), which is not where a consumer keeps it.
    function New-StagedRepo {
        param([string]$GithubDir, [string]$Prefix = '')
        $base = Split-Path -Parent $GithubDir
        $rel = '.github'
        if ($Prefix) {
            $rel = "$Prefix/.github"
            New-Item -ItemType Directory -Path (Join-Path $base $Prefix) -Force | Out-Null
            Move-Item -LiteralPath $GithubDir -Destination (Join-Path $base $rel)
        }
        Push-Location $base
        try {
            git init -q
            git config user.email t@example.com
            git config user.name tester
            # Never inherit the ambient hook path into a throwaway fixture.
            git config core.hooksPath .nohooks
            git add -- ":(literal)$rel" 2>&1 | Out-Null
        } finally { Pop-Location }
        return $base
    }

    function Invoke-Guard([string]$repo) {
        Push-Location $repo
        try {
            $out = & $python $guard 2>&1 | Out-String
            return @{ Code = $LASTEXITCODE; Output = $out }
        } finally { Pop-Location }
    }

    function New-OverBudgetFixture {
        return New-Fixture -RootTokens 100 -Conf $guardConf -Instructions @{
            'huge.instructions.md' = @{ Tokens = 2000; ApplyTo = '**' }
        }
    }

    # X: a staged payload over budget blocks the commit, naming the offender.
    $gh = New-OverBudgetFixture; $fixtures += $gh
    $repoOver = New-StagedRepo $gh
    $r = Invoke-Guard $repoOver
    $results['X_staged_over_budget_blocked'] = ($r.Code -eq 1)
    $results['X_staged_names_offender'] = ($r.Output -match 'huge\.instructions\.md')

    # Y: a commit that stages nothing the budget depends on pays nothing and
    #    says nothing -- even with an over-budget payload in the index (AC2).
    #    The file sits inside .github, which is where scoping is actually decided.
    #    This used to stage a SKILL.md, which stopped being an honest example
    #    when skill descriptions entered the catalogue budget (#206). A prompt
    #    file is loaded only when someone runs it, so it still costs nothing.
    git -C $repoOver commit -qm seed 2>&1 | Out-Null
    $promptDir = Join-Path $repoOver '.github/prompts'
    New-Item -ItemType Directory -Path $promptDir -Force | Out-Null
    'prompt' | Set-Content (Join-Path $promptDir 'demo.prompt.md')
    git -C $repoOver add -- ':(literal).github/prompts/demo.prompt.md' 2>&1 | Out-Null
    $results['Y_unmeasured_file_not_checked'] = ((Invoke-Guard $repoOver).Code -eq 0)

    # Y2: the ceiling is part of what the payload must satisfy. Lowering it puts
    #     an untouched payload over budget, so a budget edit is itself a trigger
    #     -- a ceiling that binds only the next edit does not bind.
    $gh = New-Fixture -RootTokens 300 -Conf "AF_CONTEXT_BUDGET_TOKENS=100000`n" -Instructions @{
        'a.instructions.md' = @{ Tokens = 10; ApplyTo = '**' }
    }
    $fixtures += $gh
    $repoConf = New-StagedRepo $gh
    git -C $repoConf commit -qm seed 2>&1 | Out-Null
    "AF_CONTEXT_BUDGET_TOKENS=200`n" | Set-Content (Join-Path $repoConf '.github/af-env.conf') -NoNewline
    git -C $repoConf add -- ':(literal).github/af-env.conf' 2>&1 | Out-Null
    $results['Y_budget_edit_rechecked'] = ((Invoke-Guard $repoConf).Code -eq 1)

    # Z: an agent edit is a measured edit, and it measures the whole payload --
    #    not merely the file that happened to be staged.
    $agentFile = Join-Path $repoOver '.github/agents/stub.agent.md'
    Add-Content -LiteralPath $agentFile -Value 'zzzz'
    git -C $repoOver add -- ':(literal).github/agents/stub.agent.md' 2>&1 | Out-Null
    $results['Z_agent_edit_measures_payload'] = ((Invoke-Guard $repoOver).Code -eq 1)

    # AA: the escape hatch exists and is per-commit, like the sibling guards.
    $env:ALLOW_CONTEXT_BUDGET = '1'
    $results['AA_override_allows'] = ((Invoke-Guard $repoOver).Code -eq 0)
    Remove-Item Env:ALLOW_CONTEXT_BUDGET

    # BB: the guard measures the index, not the working tree. A fat unstaged
    #     edit is not being committed and must not block the commit.
    $gh = New-Fixture -RootTokens 100 -Conf $guardConf -Instructions @{
        'ok.instructions.md' = @{ Tokens = 200; ApplyTo = '**' }
    }
    $fixtures += $gh
    $repo = New-StagedRepo $gh
    Add-Content -LiteralPath (Join-Path $repo '.github/instructions/ok.instructions.md') -Value ('y' * 40000)
    $results['BB_unstaged_bloat_ignored'] = ((Invoke-Guard $repo).Code -eq 0)

    # CC: ... and the converse. Shrinking the file on disk after staging it
    #     does not un-commit the breach.
    $gh = New-OverBudgetFixture; $fixtures += $gh
    $repo = New-StagedRepo $gh
    'tiny' | Set-Content (Join-Path $repo '.github/instructions/huge.instructions.md')
    $results['CC_unstaged_shrink_ignored'] = ((Invoke-Guard $repo).Code -eq 1)

    # DD: the ceiling is the one in the staged af-env.conf -- a consumer's
    #     budget, not the framework's.
    $gh = New-Fixture -RootTokens 300 -Conf "AF_CONTEXT_BUDGET_TOKENS=200`n" -Instructions @{
        'a.instructions.md' = @{ Tokens = 10; ApplyTo = '**' }
    }
    $fixtures += $gh
    $results['DD_tight_consumer_budget_blocks'] = ((Invoke-Guard (New-StagedRepo $gh)).Code -eq 1)
    $gh = New-Fixture -RootTokens 300 -Conf "AF_CONTEXT_BUDGET_TOKENS=100000`n" -Instructions @{
        'a.instructions.md' = @{ Tokens = 10; ApplyTo = '**' }
    }
    $fixtures += $gh
    $results['DD_loose_consumer_budget_passes'] = ((Invoke-Guard (New-StagedRepo $gh)).Code -eq 0)

    # EE: a payload the guard cannot measure must not read as a payload within
    #     budget. BLOCKED propagates; it does not collapse into consent.
    $gh = New-Fixture -RootTokens 100 -Conf "AF_CONTEXT_BUDGET_TOKENS=abc`n" -Instructions @{
        'a.instructions.md' = @{ Tokens = 10; ApplyTo = '**' }
    }
    $fixtures += $gh
    $results['EE_inner_blocked_propagates'] = ((Invoke-Guard (New-StagedRepo $gh)).Code -eq 2)

    # FF: the AF source repo nests its payload under flavors/github-copilot/.
    #     A guard that only knows the deployed layout would protect every
    #     consumer and not the repo that authors the budgets (AC3).
    $gh = New-OverBudgetFixture; $fixtures += $gh
    $results['FF_nested_payload_measured'] =
        ((Invoke-Guard (New-StagedRepo $gh -Prefix 'flavors/github-copilot')).Code -eq 1)

    # GG: a git failure is an unknown verdict, not a pass.
    $noRepo = Join-Path ([IO.Path]::GetTempPath()) ("ctxg-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $noRepo -Force | Out-Null
    $fixtures += (Join-Path $noRepo 'x')
    $results['GG_outside_repo_blocked'] = ((Invoke-Guard $noRepo).Code -eq 2)

    # HH: wiring. A checker nobody calls is the defect this issue is about, so
    #     the dispatch line is asserted -- not the comment that names it.
    $shim = Get-Content (Join-Path $scriptDir '..' | Join-Path -ChildPath 'hooks/git/pre-commit') -Raw
    $results['HH_shim_registers_guard'] =
        ($shim -match 'for checker in [^\r\n]*check-context-budget-staged\.py')

    # II: the AF source repo's own hook path is .githooks/, which never
    #     dispatched the shipped guards -- so they protected every consumer
    #     project and not the repo that writes them.
    $afHook = Join-Path $repoRootAF '../../.githooks/pre-commit'
    if (Test-Path $afHook) {
        $results['II_af_repo_dispatches_guards'] =
            ((Get-Content $afHook -Raw) -match '(^|\n)\s*sh\s+"\$PAYLOAD_HOOK"')
    } else {
        Write-Host '  (II_af_repo_dispatches_guards skipped: not an AF source tree)'
    }

    # YY: the commit gate must see the catalogue kind that dominates it. Skills
    #     are the largest share of the catalogue payload, and the guard exported
    #     everything except them -- so a description could be grown to any size
    #     and the pre-commit check would report a total that did not contain it.
    #     Caught by reading the guard's own output on the commit that added the
    #     catalogue ceiling: it reported 1,416 tok where the checker said 3,322.
    $catGuardConf = $guardConf + "AF_CATALOGUE_BUDGET_TOKENS=200`n"
    $gh = New-Fixture -RootTokens 100 -Conf $catGuardConf -Skills @{
        'windbag' = @{ Description = ('y' * 4000) }
    } -Instructions @{ 'ok.instructions.md' = @{ Tokens = 100; ApplyTo = '**' } }
    $fixtures += $gh
    $r = Invoke-Guard (New-StagedRepo $gh)
    $results['YY_staged_skill_description_measured'] = ($r.Code -eq 1)
    $results['YY_staged_skill_named'] = ($r.Output -match 'windbag')

    # A skill's reference files are loaded on demand and cost the budget
    # nothing. Staging a large one must not block a commit, or the guard would
    # be charging for the level of loading it is not measuring.
    $gh = New-Fixture -RootTokens 100 -Conf $catGuardConf -Skills @{
        'alpha' = @{ Description = 'does alpha things' }
    } -Instructions @{ 'ok.instructions.md' = @{ Tokens = 100; ApplyTo = '**' } }
    $fixtures += $gh
    [IO.File]::WriteAllText((Join-Path $gh 'skills/alpha/REFERENCE.md'), ('z' * 60000))
    $results['YY_skill_reference_file_not_charged'] = ((Invoke-Guard (New-StagedRepo $gh)).Code -eq 0)

    # --- The guard's own blind spot (issue #125) --------------------------
    # The guard measures the index, so a project that gitignores .github/ can
    # never stage a budget input and the guard can never fire. It emitted
    # nothing, which is exactly what a passing guard emits -- and read as a
    # pass for months. These cases pin the difference between "measured
    # nothing" and "measured everything, all within budget".

    # Copies guard and checker into a fixture, so the guard can locate its own
    # payload from where it is installed -- as it does in a real deployment.
    function Install-Guard([string]$GithubDir) {
        foreach ($pair in @(@('hooks/scripts', $guard), @('scripts', $checker))) {
            $dst = Join-Path $GithubDir $pair[0]
            New-Item -ItemType Directory -Path $dst -Force | Out-Null
            Copy-Item -LiteralPath $pair[1] -Destination $dst
        }
    }

    function Invoke-DeployedGuard([string]$repo) {
        Push-Location $repo
        try {
            $out = & $python '.github/hooks/scripts/check-context-budget-staged.py' 2>&1 | Out-String
            return @{ Code = $LASTEXITCODE; Output = $out }
        } finally { Pop-Location }
    }

    # TT: a payload git refuses to hold cannot be staged, so no commit will
    #     ever reach the measurement. Saying so is the whole fix.
    $gh = New-OverBudgetFixture; $fixtures += $gh
    Install-Guard $gh
    $repoBlind = Split-Path -Parent $gh
    Push-Location $repoBlind
    try {
        git init -q
        git config user.email t@example.com
        git config user.name tester
        git config core.hooksPath .nohooks
        '.github/' | Set-Content .gitignore
        'x' | Set-Content readme.md
        git add -- ':(literal).gitignore' ':(literal)readme.md' 2>&1 | Out-Null
    } finally { Pop-Location }
    $r = Invoke-DeployedGuard $repoBlind
    $results['TT_untracked_payload_named'] = ($r.Output -match 'NOT GATED')
    $results['TT_untracked_payload_not_blocked'] = ($r.Code -eq 0)
    $results['TT_gitignore_named_as_cause'] = ($r.Output -match 'gitignore rule')
    # ... and it carries a number. Copilot loads these files from disk whether
    # or not git holds them, so disk is the honest basis for the reading --
    # the index is the honest basis only for a verdict.
    $results['TT_untracked_payload_measured'] = ($r.Output -match 'FAIL')
    $results['TT_reading_marked_advisory'] = ($r.Output -match 'advisory')

    # UU: the ordinary commit must stay silent. A guard that speaks on every
    #     commit becomes a banner, and a banner is the next form of silence.
    $gh = New-OverBudgetFixture; $fixtures += $gh
    Install-Guard $gh
    $repo = New-StagedRepo $gh
    git -C $repo commit -qm seed 2>&1 | Out-Null
    'x' | Set-Content (Join-Path $repo 'readme.md')
    git -C $repo add -- ':(literal)readme.md' 2>&1 | Out-Null
    $r = Invoke-DeployedGuard $repo
    $results['UU_tracked_payload_stays_silent'] = (($r.Code -eq 0) -and ($r.Output.Trim() -eq ''))

    # VV: partial tracking is the same defect wearing a passing verdict. Half
    #     an unignored .github/ is not half a gate; it is a gate that measures
    #     a subset and reports it as the total.
    $gh = New-Fixture -RootTokens 100 -Conf $guardConf -Instructions @{
        'shared.instructions.md' = @{ Tokens = 100; ApplyTo = '**' }
    }
    $fixtures += $gh
    Install-Guard $gh
    $repo = New-StagedRepo $gh
    git -C $repo commit -qm seed 2>&1 | Out-Null
    $local = Join-Path $repo '.github/instructions/local.instructions.md'
    [IO.File]::WriteAllText($local, ('x' * 400))
    'x' | Set-Content (Join-Path $repo 'readme.md')
    git -C $repo add -- ':(literal)readme.md' 2>&1 | Out-Null
    $r = Invoke-DeployedGuard $repo
    $results['VV_partial_tracking_reported'] = ($r.Output -match 'PARTIALLY GATED')
    $results['VV_partial_tracking_names_file'] = ($r.Output -match 'local\.instructions\.md')
    $results['VV_partial_tracking_measured'] = ($r.Output -match 'PASS --')

    # WW: and on a payload commit the same blindness makes the reading a
    #     floor. The staged verdict still stands -- an exit code is a statement
    #     about the commit, untracked files a statement about the repository.
    Add-Content -LiteralPath (Join-Path $repo '.github/instructions/shared.instructions.md') -Value 'xxxx'
    git -C $repo add -- ':(literal).github/instructions/shared.instructions.md' 2>&1 | Out-Null
    $r = Invoke-DeployedGuard $repo
    $results['WW_floor_reported_on_payload_commit'] = ($r.Output -match 'is a floor')
    $results['WW_floor_does_not_block'] = ($r.Code -eq 0)
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
