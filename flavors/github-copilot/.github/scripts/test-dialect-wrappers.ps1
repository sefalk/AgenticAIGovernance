# Regression tests for the dialect-wrapper architecture (issue #287).
#
# #287 measured the real cost of maintaining PowerShell/Bash twins: it is not
# line count, it is that every gate must be written, tested and reviewed twice
# and demonstrably drifts. The answer AF already uses elsewhere is one Python
# core with wrappers too thin to hold logic.
#
# This suite covers three things:
#
#   A. The watchdog (check-dialect-wrappers.py). A documented rule does not
#      stop the next hook from being written the old way -- that is exactly
#      how the twins drifted in the first place. The checker turns the rule
#      into a test failure, and rule DW003 is the ratchet: a NEW dialect pair
#      with no Python core fails, so the defect class cannot come back.
#
#   B. The reference migration (scan-secrets.py). The detection cases live
#      here, once, instead of once per dialect.
#
#   C. Dialect parity for the migrated pair. Measured on 2026-09-22 before the
#      migration, the two scan-secrets twins disagreed on three of four
#      payloads -- in both directions:
#
#        connection string      ps1 exit 1 / sh exit 0   (sh lacked the rule)
#        apikey (no underscore) ps1 exit 1 / sh exit 0   (sh lacked the alias)
#        AWS key in a .conf     ps1 exit 0 / sh exit 1   (ps1 skipped the ext)
#
#      Case C1 states that as an invariant rather than as three fixes.
#
# Run from anywhere:
#   powershell -File .github/scripts/test-dialect-wrappers.ps1
# Exits non-zero if any scenario fails (CI-friendly).
$ErrorActionPreference = 'Continue'

$scriptDir = Split-Path -Parent $PSCommandPath
$repoRootAF = (Resolve-Path (Join-Path $scriptDir '..' | Join-Path -ChildPath '..')).Path
$hookDir = Join-Path $repoRootAF '.github/hooks/scripts'
$checker = Join-Path $scriptDir 'check-dialect-wrappers.py'

# Resolve a real Python 3 interpreter (skip the Windows Store alias by probing).
function Resolve-Python {
    foreach ($c in @((Join-Path $repoRootAF '.venv/Scripts/python.exe'),
                     (Join-Path $repoRootAF '.venv/bin/python'))) {
        if (Test-Path $c) { return @($c) }
    }
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

# @(...) is required: PowerShell unwraps a single-element array on return, so
# a bare assignment would yield a string and $python[0] would be a character.
$python = @(Resolve-Python)
if ($python.Count -eq 0 -or -not $python[0]) {
    Write-Host 'SKIP: no Python 3 interpreter found; cannot run dialect-wrapper tests.'
    exit 0
}
$pyExe = $python[0]
$pyPre = if ($python.Count -gt 1) { $python[1..($python.Count - 1)] } else { @() }

function Invoke-Py([string[]]$ArgList) { & $pyExe @pyPre @ArgList }

$results = [ordered]@{}
$details = [ordered]@{}
$fixtures = @()

function New-Fixture([string]$tag) {
    $p = Join-Path ([IO.Path]::GetTempPath()) ("af 287 $tag " + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $p -Force | Out-Null
    $script:fixtures += $p
    return $p
}

# Writes without a BOM and without CRLF: the checker counts effective lines and
# the bash wrapper must stay executable under Git Bash.
function Write-Text([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, ($Text -replace "`r", ''))
}

# Runs the checker over a directory and returns exit code plus stdout.
function Invoke-Checker([string]$Target) {
    $out = & $pyExe @pyPre $checker $Target 2>&1 | Out-String
    return [pscustomobject]@{ Exit = $LASTEXITCODE; Out = $out }
}

# Feeds a PostToolUse payload to a script and returns its exit code.
function Invoke-Hook([string]$Runner, [string]$Target, [string]$Payload) {
    switch ($Runner) {
        'py' { $Payload | & $pyExe @pyPre $Target *> $null }
        'ps' { $Payload | & powershell -NoProfile -ExecutionPolicy Bypass -File $Target *> $null }
        'sh' { $Payload | & $script:bashExe ($Target -replace '\\', '/') *> $null }
    }
    return $LASTEXITCODE
}

# Captures stdout too, for the cases that assert on the verdict rather than
# only on the exit code.
function Invoke-HookOut([string]$Target, [string]$Payload) {
    $out = $Payload | & $pyExe @pyPre $Target 2>&1 | Out-String
    return [pscustomobject]@{ Exit = $LASTEXITCODE; Out = $out }
}

function New-Payload([string]$FilePath) {
    return (@{ tool_name = 'replace_string_in_file'; tool_input = @{ filePath = $FilePath; oldString = 'a'; newString = 'b' } } | ConvertTo-Json -Compress)
}

$script:bashExe = $null
foreach ($b in @('C:\Program Files\Git\bin\bash.exe', '/bin/bash')) {
    if (Test-Path $b) { $script:bashExe = $b; break }
}
if (-not $script:bashExe) {
    $cmd = Get-Command bash -ErrorAction SilentlyContinue
    if ($cmd) { $script:bashExe = $cmd.Source }
}

$core = Join-Path $hookDir 'scan-secrets.py'
$wrapPs = Join-Path $hookDir 'scan-secrets.ps1'
$wrapSh = Join-Path $hookDir 'scan-secrets.sh'

try {
    # ── A. The watchdog ────────────────────────────────────────────────

    $results['A1_checker_ships_with_the_suite'] = (Test-Path $checker)
    $details['A1_checker_ships_with_the_suite'] = "expected $checker"

    if (Test-Path $checker) {

        # A delegating pair: both wrappers are short and both name the core.
        $okDir = New-Fixture 'ok'
        Write-Text (Join-Path $okDir 'demo-gate.py') "import sys`nsys.exit(0)`n"
        Write-Text (Join-Path $okDir 'demo-gate.ps1') @'
. "$PSScriptRoot/_common.ps1"
$raw = [Console]::In.ReadToEnd()
$raw | & $AfPython "$PSScriptRoot/demo-gate.py"
exit $LASTEXITCODE
'@
        Write-Text (Join-Path $okDir 'demo-gate.sh') @'
#!/usr/bin/env bash
. "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"
exec "$AF_PYTHON" "$(dirname -- "${BASH_SOURCE[0]}")/demo-gate.py"
'@
        $r = Invoke-Checker $okDir
        $results['A2_delegating_pair_passes'] = ($r.Exit -eq 0)
        $details['A2_delegating_pair_passes'] = "exit=$($r.Exit) out=$($r.Out.Trim())"

        # The same pair, but the PowerShell wrapper has grown logic back.
        $fatDir = New-Fixture 'fat'
        Write-Text (Join-Path $fatDir 'demo-gate.py') "import sys`nsys.exit(0)`n"
        $fatBody = @('. "$PSScriptRoot/_common.ps1"', '$raw = [Console]::In.ReadToEnd()')
        1..40 | ForEach-Object { $fatBody += ('if ($raw -match ''p{0}'') {{ exit 1 }}' -f $_) }
        $fatBody += '& $AfPython "$PSScriptRoot/demo-gate.py"'
        Write-Text (Join-Path $fatDir 'demo-gate.ps1') ($fatBody -join "`n")
        Write-Text (Join-Path $fatDir 'demo-gate.sh') @'
#!/usr/bin/env bash
exec "$AF_PYTHON" "$(dirname -- "${BASH_SOURCE[0]}")/demo-gate.py"
'@
        $r = Invoke-Checker $fatDir
        $results['A3_wrapper_carrying_logic_is_rejected'] = ($r.Exit -ne 0 -and $r.Out -match 'demo-gate\.ps1')
        $details['A3_wrapper_carrying_logic_is_rejected'] = "exit=$($r.Exit) out=$($r.Out.Trim())"

        # A wrapper that is short but never names its core is not delegating
        # either -- it is simply a stub that silently does nothing.
        $mutedir = New-Fixture 'mute'
        Write-Text (Join-Path $mutedir 'demo-gate.py') "import sys`nsys.exit(0)`n"
        Write-Text (Join-Path $mutedir 'demo-gate.ps1') "Write-Output '{}'`nexit 0`n"
        Write-Text (Join-Path $mutedir 'demo-gate.sh') "#!/usr/bin/env bash`necho '{}'`nexit 0`n"
        $r = Invoke-Checker $mutedir
        $results['A4_wrapper_that_never_names_its_core_is_rejected'] = ($r.Exit -ne 0)
        $details['A4_wrapper_that_never_names_its_core_is_rejected'] = "exit=$($r.Exit) out=$($r.Out.Trim())"

        # THE RATCHET. A brand-new dialect pair with no Python core at all.
        # Nothing about this fixture is wrong line by line -- the point is
        # that writing the next gate as twins has to fail by construction,
        # otherwise the rule is advice and advice is what already failed.
        $newDir = New-Fixture 'new'
        Write-Text (Join-Path $newDir 'brand-new-gate.ps1') "Write-Output '{}'`nexit 0`n"
        Write-Text (Join-Path $newDir 'brand-new-gate.sh') "#!/usr/bin/env bash`necho '{}'`nexit 0`n"
        $r = Invoke-Checker $newDir
        $results['A5_new_twin_pair_without_a_python_core_is_rejected'] = ($r.Exit -ne 0 -and $r.Out -match 'brand-new-gate')
        $details['A5_new_twin_pair_without_a_python_core_is_rejected'] = "exit=$($r.Exit) out=$($r.Out.Trim())"

        # A deliberate exception must be visible and must carry a reason.
        $hatchDir = New-Fixture 'hatch'
        Write-Text (Join-Path $hatchDir 'brand-new-gate.ps1') "# af-dialect-ok: PowerShell-only host API, no portable equivalent`nWrite-Output '{}'`nexit 0`n"
        Write-Text (Join-Path $hatchDir 'brand-new-gate.sh') "#!/usr/bin/env bash`n# af-dialect-ok: PowerShell-only host API, no portable equivalent`necho '{}'`nexit 0`n"
        $r = Invoke-Checker $hatchDir
        $results['A6_escape_hatch_with_a_reason_is_accepted'] = ($r.Exit -eq 0)
        $details['A6_escape_hatch_with_a_reason_is_accepted'] = "exit=$($r.Exit) out=$($r.Out.Trim())"

        $bareDir = New-Fixture 'bare'
        Write-Text (Join-Path $bareDir 'brand-new-gate.ps1') "# af-dialect-ok`nWrite-Output '{}'`nexit 0`n"
        Write-Text (Join-Path $bareDir 'brand-new-gate.sh') "#!/usr/bin/env bash`n# af-dialect-ok`necho '{}'`nexit 0`n"
        $r = Invoke-Checker $bareDir
        $results['A7_escape_hatch_without_a_reason_is_rejected'] = ($r.Exit -ne 0)
        $details['A7_escape_hatch_without_a_reason_is_rejected'] = "exit=$($r.Exit) out=$($r.Out.Trim())"

        # The shipped hook directory must pass its own checker. Legacy pairs
        # are carried in an explicit baseline inside the checker; this case is
        # what makes that baseline honest.
        $r = Invoke-Checker $hookDir
        $results['A8_shipped_hook_directory_passes_the_checker'] = ($r.Exit -eq 0)
        $details['A8_shipped_hook_directory_passes_the_checker'] = "exit=$($r.Exit) out=$($r.Out.Trim())"

        # The baseline may only shrink. The ceiling is written here rather
        # than in the checker on purpose: growing it means editing a test,
        # which a reviewer sees, instead of appending a name to a list.
        # 16 twin pairs ship in hooks/scripts; scan-secrets is migrated here.
        $baselineMax = 15
        $b = & $pyExe @pyPre $checker '--print-baseline' 2>&1
        $baseline = @($b | Where-Object { $_ -and $_.ToString().Trim() })
        $results['A9_legacy_baseline_never_grows'] = ($baseline.Count -gt 0 -and $baseline.Count -le $baselineMax)
        $details['A9_legacy_baseline_never_grows'] = "baseline=$($baseline.Count) max=$baselineMax"

        # A pair that has been migrated must not also sit in the baseline,
        # or the baseline would keep excusing a gate that no longer needs it.
        $results['A10_migrated_pair_is_not_in_the_baseline'] = ($baseline -notcontains 'scan-secrets')
        $details['A10_migrated_pair_is_not_in_the_baseline'] = "baseline=$($baseline -join ',')"
    }
    else {
        foreach ($k in @('A2_delegating_pair_passes', 'A3_wrapper_carrying_logic_is_rejected',
                'A4_wrapper_that_never_names_its_core_is_rejected',
                'A5_new_twin_pair_without_a_python_core_is_rejected',
                'A6_escape_hatch_with_a_reason_is_accepted',
                'A7_escape_hatch_without_a_reason_is_rejected',
                'A8_shipped_hook_directory_passes_the_checker',
                'A9_legacy_baseline_never_grows',
                'A10_migrated_pair_is_not_in_the_baseline')) {
            $results[$k] = $false
            $details[$k] = 'checker not present'
        }
    }

    # ── B. The reference migration: scan-secrets core ──────────────────

    $results['B0_core_ships_next_to_its_wrappers'] = (Test-Path $core)
    $details['B0_core_ships_next_to_its_wrappers'] = "expected $core"

    $caseDir = New-Fixture 'cases'
    $files = @{
        conn     = 'CONN = "Server=db01;User Id=sa;Password=hunter2xyz"'
        apikey   = 'apikey = "abcdef1234567890"'
        aws      = 'key=AKIAIOSFODNN7EXAMPLE'
        pw       = 'password = "SuperSecret123!"'
        privkey  = "-----BEGIN RSA PRIVATE KEY-----`nMIIBOgIBAAJBAK`n-----END RSA PRIVATE KEY-----"
        clean    = "# copilot:generated | test | 2026-09-22`nvalue = 1"
        unmarked = 'value = 1'
    }
    $paths = @{}
    $paths['conn'] = Join-Path $caseDir 'conn.py'
    $paths['apikey'] = Join-Path $caseDir 'apikey.py'
    $paths['aws'] = Join-Path $caseDir 'aws.conf'
    $paths['pw'] = Join-Path $caseDir 'pw.py'
    $paths['privkey'] = Join-Path $caseDir 'key.pem'
    $paths['clean'] = Join-Path $caseDir 'clean.py'
    $paths['unmarked'] = Join-Path $caseDir 'unmarked.py'
    foreach ($k in $files.Keys) { Write-Text $paths[$k] $files[$k] }

    if (Test-Path $core) {
        $results['B1_connection_string_is_detected'] = ((Invoke-Hook 'py' $core (New-Payload $paths['conn'])) -eq 1)
        $results['B2_apikey_without_underscore_is_detected'] = ((Invoke-Hook 'py' $core (New-Payload $paths['apikey'])) -eq 1)

        # The PowerShell twin filtered by an extension allowlist that did not
        # contain .conf, so a key in a config file walked straight through it.
        $results['B3_secret_in_a_config_extension_is_detected'] = ((Invoke-Hook 'py' $core (New-Payload $paths['aws'])) -eq 1)

        $results['B4_generic_password_is_detected'] = ((Invoke-Hook 'py' $core (New-Payload $paths['pw'])) -eq 1)
        $results['B5_private_key_is_detected'] = ((Invoke-Hook 'py' $core (New-Payload $paths['privkey'])) -eq 1)
        $results['B6_clean_file_passes'] = ((Invoke-Hook 'py' $core (New-Payload $paths['clean'])) -eq 0)

        $results['B7_non_write_tool_is_ignored'] = ((Invoke-Hook 'py' $core '{"tool_name":"read_file","tool_input":{"filePath":"src/main.py"}}') -eq 0)

        $batch = @{
            tool_name  = 'multi_replace_string_in_file'
            tool_input = @{ explanation = 'batch'; replacements = @(@{ filePath = $paths['pw']; oldString = 'a'; newString = 'b' }) }
        } | ConvertTo-Json -Depth 5 -Compress
        $results['B8_batched_edit_is_scanned'] = ((Invoke-Hook 'py' $core $batch) -eq 1)

        $r = Invoke-HookOut $core (New-Payload $paths['unmarked'])
        $results['B9_unmarked_python_file_gets_a_provenance_warning'] = ($r.Exit -eq 0 -and $r.Out -match 'provenance-check')
        $details['B9_unmarked_python_file_gets_a_provenance_warning'] = "exit=$($r.Exit) out=$($r.Out.Trim())"

        # Only one verdict can be emitted, and a secret outranks a missing
        # marker. pw.py carries a secret and no marker.
        $r = Invoke-HookOut $core (New-Payload $paths['pw'])
        $results['B10_secret_outranks_the_provenance_warning'] = ($r.Exit -eq 1 -and $r.Out -match 'secret-scan' -and $r.Out -notmatch 'provenance-check')
        $details['B10_secret_outranks_the_provenance_warning'] = "exit=$($r.Exit) out=$($r.Out.Trim())"

        $results['B11_missing_file_does_not_crash'] = ((Invoke-Hook 'py' $core (New-Payload (Join-Path $caseDir 'nope.py'))) -eq 0)
        $results['B12_malformed_payload_does_not_crash'] = ((Invoke-Hook 'py' $core 'not json at all') -eq 0)
    }
    else {
        foreach ($k in @('B1_connection_string_is_detected', 'B2_apikey_without_underscore_is_detected',
                'B3_secret_in_a_config_extension_is_detected', 'B4_generic_password_is_detected',
                'B5_private_key_is_detected', 'B6_clean_file_passes', 'B7_non_write_tool_is_ignored',
                'B8_batched_edit_is_scanned', 'B9_unmarked_python_file_gets_a_provenance_warning',
                'B10_secret_outranks_the_provenance_warning', 'B11_missing_file_does_not_crash',
                'B12_malformed_payload_does_not_crash')) {
            $results[$k] = $false
            $details[$k] = 'core not present'
        }
    }

    # ── C. Dialect parity ──────────────────────────────────────────────

    if ($script:bashExe -and (Test-Path $wrapPs) -and (Test-Path $wrapSh)) {
        $parity = @()
        foreach ($k in @('conn', 'apikey', 'aws', 'pw', 'privkey', 'clean')) {
            $payload = New-Payload $paths[$k]
            $a = Invoke-Hook 'ps' $wrapPs $payload
            $b = Invoke-Hook 'sh' $wrapSh $payload
            if ($a -ne $b) { $parity += ("{0}: ps1={1} sh={2}" -f $k, $a, $b) }
        }
        $results['C1_both_dialects_reach_the_same_verdict'] = ($parity.Count -eq 0)
        $details['C1_both_dialects_reach_the_same_verdict'] = ($parity -join '; ')
    }
    else {
        $results['C1_both_dialects_reach_the_same_verdict'] = $false
        $details['C1_both_dialects_reach_the_same_verdict'] = 'bash or a wrapper is missing'
    }

    # The wrappers are the thing that must stay thin; if they can grow, the
    # parity above is only true until someone edits one of them.
    if ((Test-Path $checker) -and (Test-Path $wrapPs)) {
        $r = Invoke-Checker $hookDir
        $results['C2_migrated_wrappers_satisfy_the_checker'] = ($r.Exit -eq 0 -and $r.Out -notmatch 'scan-secrets')
        $details['C2_migrated_wrappers_satisfy_the_checker'] = "exit=$($r.Exit) out=$($r.Out.Trim())"
    }
    else {
        $results['C2_migrated_wrappers_satisfy_the_checker'] = $false
        $details['C2_migrated_wrappers_satisfy_the_checker'] = 'checker or wrapper missing'
    }
}
finally {
    foreach ($f in $fixtures) { Remove-Item $f -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host '===== dialect-wrapper regression tests (issue #287) ====='
$allPass = $true
foreach ($k in $results.Keys) {
    if ($results[$k]) {
        Write-Host ("PASS  {0}" -f $k)
    } else {
        $allPass = $false
        Write-Host ("FAIL  {0}" -f $k)
        if ($details[$k]) { Write-Host ("      {0}" -f $details[$k]) }
    }
}
$passCount = @($results.Values | Where-Object { $_ }).Count
Write-Host ("----- {0}/{1} passed -----" -f $passCount, $results.Count)
if (-not $allPass) { exit 1 }
exit 0
