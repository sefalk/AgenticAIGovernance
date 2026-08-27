# test-cost-source.ps1 -- regression suite for check-cost-source.ps1.
#
# Guards the two properties that make the advisory trustworthy: it must never
# fail a run (the setting is vendor-controlled, so nothing may gate on it), and
# when it does fire it must say enough for a consumer to act without reading
# framework source.

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SCRIPT = Join-Path $scriptDir 'check-cost-source.ps1'
$SETTING = 'github.copilot.chat.agentDebugLog.fileLogging.enabled'

$results = [ordered]@{}
$fixtures = New-Object System.Collections.ArrayList

$psExe = (Get-Process -Id $PID).Path
if (-not $psExe) { $psExe = 'powershell' }

function Invoke-Probe {
    param([string[]]$Arguments = @())
    $out = & $psExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $SCRIPT @Arguments 2>&1 | Out-String
    return [pscustomobject]@{ Output = $out; Code = $LASTEXITCODE }
}

function New-Fixture {
    param([int]$Sessions = 0, [switch]$NoMainLog)
    $root = Join-Path ([IO.Path]::GetTempPath()) ('afcs-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    $user = Join-Path $root 'User'
    New-Item -ItemType Directory -Path $user -Force | Out-Null
    for ($i = 0; $i -lt $Sessions; $i++) {
        $dir = Join-Path $user "workspaceStorage/ws$i/GitHub.copilot-chat/debug-logs/sess$i"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        if (-not $NoMainLog) { Set-Content -LiteralPath (Join-Path $dir 'main.jsonl') -Value '{}' }
    }
    [void]$fixtures.Add($root)
    return $user
}

try {
    # A -- source switched off: advisory fires, run still succeeds.
    $empty = New-Fixture -Sessions 0
    $a = Invoke-Probe @('-UserDir', $empty)

    $results['A_exit_zero'] = ($a.Code -eq 0)
    $results['A_advisory_raised'] = ($a.Output -match 'ADVISORY')
    $results['A_names_setting'] = ($a.Output -match [regex]::Escape($SETTING))
    $results['A_names_search_path'] = ($a.Output -match [regex]::Escape($empty))
    $results['A_states_what_is_lost'] = ($a.Output -match 'available:\s*false')
    $results['A_states_vendor_caveat'] = ($a.Output -match 'vendor-controlled')
    $results['A_declares_no_gating'] = ($a.Output -match 'advisory only')
    $results['A_not_reported_ok'] = ($a.Output -notmatch '\bOK:')

    # B -- source live: no advisory, sessions counted.
    $live = New-Fixture -Sessions 3
    $b = Invoke-Probe @('-UserDir', $live)

    $results['B_exit_zero'] = ($b.Code -eq 0)
    $results['B_reports_ok'] = ($b.Output -match '\bOK:')
    $results['B_counts_sessions'] = ($b.Output -match '\(3 found\)')
    $results['B_no_advisory'] = ($b.Output -notmatch 'ADVISORY')

    # C -- a session directory without a main log is not evidence of a source.
    $hollow = New-Fixture -Sessions 2 -NoMainLog
    $c = Invoke-Probe @('-UserDir', $hollow)

    $results['C_hollow_dir_not_counted'] = ($c.Output -match 'ADVISORY')
    $results['C_hollow_exit_zero'] = ($c.Code -eq 0)

    # D -- a directory that does not exist must not throw.
    $missing = Join-Path ([IO.Path]::GetTempPath()) ('afcs-absent-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    $d = Invoke-Probe @('-UserDir', $missing)

    $results['D_absent_dir_exit_zero'] = ($d.Code -eq 0)
    $results['D_absent_dir_advisory'] = ($d.Output -match 'ADVISORY')
    $results['D_no_exception_text'] = ($d.Output -notmatch 'Exception|CategoryInfo')

    # E -- header framing, and -Brief for embedding in another summary.
    $e = Invoke-Probe @('-UserDir', $live)
    $f = Invoke-Probe @('-UserDir', $live, '-Brief')

    $results['E_header_printed'] = ($e.Output -match '=== Cost Tracking Source ===')
    $results['E_brief_suppresses_header'] = ($f.Output -notmatch '=== Cost Tracking Source ===')
    $results['E_brief_keeps_verdict'] = ($f.Output -match '\bOK:')

    # F -- the deploy summary captures the lines to indent and colour them.
    # Write-Host would render on the console and hand back nothing, so the
    # advisory must travel the pipeline. Measured: it did not, at first.
    $piped = @(& $SCRIPT -UserDir $live -Brief)
    $results['F_output_is_pipeable'] = ($piped.Count -gt 0 -and ($piped -join ' ') -match '\bOK:')

    $pipedAdvisory = @(& $SCRIPT -UserDir $empty -Brief)
    $results['F_advisory_is_pipeable'] = ($pipedAdvisory.Count -ge 6 -and ($pipedAdvisory -join ' ') -match 'ADVISORY')
}
finally {
    foreach ($root in $fixtures) {
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Write-Host ''
Write-Host '=== Cost Source Advisory ==='
$failed = 0
foreach ($name in $results.Keys) {
    if ($results[$name]) { Write-Host "  PASS: $name" }
    else { Write-Host "  FAIL: $name"; $failed++ }
}

# Check inventory (#224 pattern). The probes run inside a try/finally, so a
# throw part-way through would leave the later checks unassigned and the suite
# would still report zero failures. Pin the count so a check cannot go missing
# in silence.
$EXPECTED_CHECK_TOTAL = 22
if ($results.Count -ne $EXPECTED_CHECK_TOTAL) {
    Write-Host "  FAIL: check inventory is $($results.Count), expected $EXPECTED_CHECK_TOTAL"
    $failed++
}

Write-Host ''
Write-Host "  Checks passed: $($results.Count - $failed)"
Write-Host "  Checks failed: $failed"
if ($failed -gt 0) { Write-Host '  RESULT: COST SOURCE ADVISORY IS BROKEN'; exit 1 }
Write-Host '  RESULT: COST SOURCE ADVISORY IS WORKING'
exit 0
