# Regression suite: a gate documented as blocking must emit a shape the
# harness actually acts on.
#
# #339: hooks/README.md called the secret scan a HARD gate that "exits with
# code 1 when secrets are detected", and it did exactly that -- for months,
# while blocking nothing. Both published contracts say a non-zero exit other
# than 2 is a warning:
#
#   VS Code Local   0 -> stdout processed | 2 -> blocking | other -> warning
#   GitHub Copilot  other non-zero -> logged, run continues (fail-open)
#
# So the exit code was not merely the wrong lever, it disabled the right one:
# a non-zero exit means stdout is never read as a decision.
#
# The defect was a documented guarantee with no test behind it. test-hooks.ps1
# asserted the verdict TEXT and the exit code; nothing compared either against
# the contract that makes a verdict binding. This suite closes that loop in
# both directions -- the prose must name the honoured mechanism, and the gate
# must emit it -- for every gate the README marks Blocking, not just this one.
#
# Adding a new blocking gate without a trigger fixture here fails C2 by
# construction. That is the point: a claim with nothing driving it is the bug.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$hookDir = Join-Path (Split-Path -Parent $scriptDir) 'hooks'
$readmePath = Join-Path $hookDir 'README.md'
$hookScripts = Join-Path $hookDir 'scripts'

$results = [ordered]@{}
$details = @{}

function Add-Result {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    $script:results[$Name] = $Ok
    $script:details[$Name] = $Detail
}

# A gate that omits the key entirely is the failure under test, so reading one
# must not throw under StrictMode.
function Get-Prop {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return '' }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return '' }
    return [string]$prop.Value
}

function Get-Nested {
    param($Object, [string]$Outer, [string]$Name)
    if ($null -eq $Object) { return '' }
    $prop = $Object.PSObject.Properties[$Outer]
    if ($null -eq $prop) { return '' }
    return (Get-Prop $prop.Value $Name)
}

# The stdout key each event is answered in. Stop and PostToolUse both say
# "block" but in different places, which is precisely the kind of detail a
# gate gets wrong once and nobody notices.
$decisionKey = @{
    'PreToolUse'  = { param($p) Get-Nested $p 'hookSpecificOutput' 'permissionDecision' }
    'PostToolUse' = { param($p) Get-Prop $p 'decision' }
    'Stop'        = { param($p) Get-Nested $p 'hookSpecificOutput' 'decision' }
}
$blockingVerdict = @{ 'PreToolUse' = 'deny'; 'PostToolUse' = 'block'; 'Stop' = 'block' }

$reasonKey = @{
    'PreToolUse'  = { param($p) Get-Nested $p 'hookSpecificOutput' 'permissionDecisionReason' }
    'PostToolUse' = { param($p) Get-Prop $p 'reason' }
    'Stop'        = { param($p) Get-Nested $p 'hookSpecificOutput' 'reason' }
}

$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ("af339-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null

# A payload that must trip the gate, and one that must not. Keyed by the
# script stem the README names, so a renamed gate surfaces as a missing
# fixture rather than as a silently skipped case.
function Get-TriggerFixture {
    param([string]$Stem)
    switch ($Stem) {
        'scan-secrets' {
            $bad = Join-Path $fixtureRoot 'secret.py'
            Set-Content -Path $bad -Value 'password = "SuperSecret123!"' -Encoding UTF8
            $good = Join-Path $fixtureRoot 'clean.py'
            Set-Content -Path $good -Value "# copilot:generated | test | 2026-09-23`nvalue = 1" -Encoding UTF8
            return @{
                Trigger = (@{ tool_name = 'replace_string_in_file'; tool_input = @{ filePath = $bad; oldString = 'a'; newString = 'b' } } | ConvertTo-Json -Compress)
                Clean   = (@{ tool_name = 'replace_string_in_file'; tool_input = @{ filePath = $good; oldString = 'a'; newString = 'b' } } | ConvertTo-Json -Compress)
                Names   = 'secret.py'
            }
        }
        default { return $null }
    }
}

function Invoke-HookScript {
    param([string]$Path, [string]$Payload)
    $ErrorActionPreference = 'Continue'
    $out = $Payload | & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Path 2>&1 | Out-String
    return @{ Output = $out.Trim(); ExitCode = $LASTEXITCODE }
}

# ── Parse the README's own claims ─────────────────────────────────────────

$sections = @()
if (Test-Path $readmePath) {
    $current = $null
    foreach ($line in (Get-Content -Path $readmePath)) {
        if ($line -match '^####\s+(?<event>[A-Za-z]+):\s*(?<title>.+)$') {
            if ($current) { $sections += $current }
            $current = [pscustomobject]@{
                Event = $Matches['event']
                Title = $Matches['title'].Trim()
                Body  = New-Object System.Collections.Generic.List[string]
            }
            continue
        }
        if ($line -match '^#{1,3}\s') {
            if ($current) { $sections += $current; $current = $null }
            continue
        }
        if ($current) { $current.Body.Add($line) }
    }
    if ($current) { $sections += $current }
}

$blocking = @()
foreach ($s in $sections) {
    $body = ($s.Body -join "`n")
    if ($body -match '\*\*Blocking\*\*') {
        $stems = [regex]::Matches($body, 'scripts/(?<name>[A-Za-z0-9_.-]+)\.ps1') |
            ForEach-Object { $_.Groups['name'].Value } | Select-Object -Unique
        $blocking += [pscustomobject]@{ Event = $s.Event; Title = $s.Title; Body = $body; Stems = @($stems) }
    }
}

# Every later case reads this list. An empty one would let them all pass by
# asserting nothing, which is how a guard quietly stops guarding.
Add-Result 'C1_the_readme_marks_at_least_one_gate_as_blocking' ($blocking.Count -ge 1) `
    ("parsed {0} '#### Event: Title' section(s), {1} marked Blocking" -f $sections.Count, $blocking.Count)

# ── Claim must have something driving it ──────────────────────────────────

$drivable = @()
$unfixtured = @()
foreach ($b in $blocking) {
    if ($b.Stems.Count -eq 0) { $unfixtured += "$($b.Title) (no scripts/<name>.ps1 named)"; continue }
    if (-not $decisionKey.ContainsKey($b.Event)) { $unfixtured += "$($b.Title) (unknown event $($b.Event))"; continue }
    foreach ($stem in $b.Stems) {
        $fx = Get-TriggerFixture $stem
        if (-not $fx) { $unfixtured += "$($b.Title) -> $stem (no trigger fixture)"; continue }
        $path = Join-Path $hookScripts "$stem.ps1"
        if (-not (Test-Path $path)) { $unfixtured += "$($b.Title) -> $path missing"; continue }
        $drivable += [pscustomobject]@{ Stem = $stem; Event = $b.Event; Path = $path; Fixture = $fx; Body = $b.Body }
    }
}

Add-Result 'C2_every_blocking_claim_has_a_trigger_fixture' ($unfixtured.Count -eq 0 -and $drivable.Count -ge 1) `
    ("drivable={0} unfixtured=[{1}]" -f $drivable.Count, ($unfixtured -join '; '))

# ── Drive each claimed gate ───────────────────────────────────────────────

$exitOk = @(); $jsonOk = @(); $keyOk = @(); $reasonOk = @(); $cleanOk = @()

try {
    foreach ($d in $drivable) {
        $r = Invoke-HookScript -Path $d.Path -Payload $d.Fixture.Trigger

        # A non-zero exit is not a stronger signal than zero, it is a weaker
        # one: the harness stops reading stdout, so the decision is discarded.
        $exitOk += "$($d.Stem): exit $($r.ExitCode)"
        if ($r.ExitCode -ne 0) { $exitOk[-1] += ' (stdout discarded by the harness)' }

        $parsed = $null
        try { $parsed = $r.Output | ConvertFrom-Json -ErrorAction Stop } catch { $parsed = $null }
        $jsonOk += "$($d.Stem): $(if ($parsed) { 'one object' } else { "unparsable: $($r.Output)" })"

        $verdict = if ($parsed) { & $decisionKey[$d.Event] $parsed } else { '' }
        $keyOk += "$($d.Stem)/$($d.Event): got '$verdict', want '$($blockingVerdict[$d.Event])'"

        $reason = if ($parsed) { & $reasonKey[$d.Event] $parsed } else { '' }
        $reasonOk += "$($d.Stem): reason '$reason'"

        $c = Invoke-HookScript -Path $d.Path -Payload $d.Fixture.Clean
        $cleanParsed = $null
        try { $cleanParsed = $c.Output | ConvertFrom-Json -ErrorAction Stop } catch { $cleanParsed = $null }
        $cleanVerdict = if ($cleanParsed) { & $decisionKey[$d.Event] $cleanParsed } else { '' }
        $cleanOk += "$($d.Stem): clean payload -> '$cleanVerdict' (exit $($c.ExitCode))"

        $d | Add-Member -NotePropertyName Result -NotePropertyValue @{
            Exit = $r.ExitCode; Parsed = $parsed; Verdict = $verdict; Reason = $reason
            CleanVerdict = $cleanVerdict
        }
    }
}
finally {
    Remove-Item $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$driven = @($drivable | Where-Object { $_.PSObject.Properties.Name -contains 'Result' })

Add-Result 'C3_a_triggered_blocking_gate_exits_zero' `
    ($driven.Count -ge 1 -and @($driven | Where-Object { $_.Result.Exit -ne 0 }).Count -eq 0) `
    ($exitOk -join '; ')

Add-Result 'C4_a_triggered_blocking_gate_emits_one_json_object' `
    ($driven.Count -ge 1 -and @($driven | Where-Object { -not $_.Result.Parsed }).Count -eq 0) `
    ($jsonOk -join '; ')

Add-Result 'C5_a_triggered_blocking_gate_uses_the_decision_key_for_its_event' `
    ($driven.Count -ge 1 -and @($driven | Where-Object { $_.Result.Verdict -ne $blockingVerdict[$_.Event] }).Count -eq 0) `
    ($keyOk -join '; ')

# A verdict the model cannot act on is a verdict it will argue with.
Add-Result 'C6_the_block_reason_names_the_offending_input' `
    ($driven.Count -ge 1 -and @($driven | Where-Object { $_.Result.Reason -notmatch [regex]::Escape($_.Fixture.Names) }).Count -eq 0) `
    ($reasonOk -join '; ')

# Without this, a gate that blocks everything would satisfy C3-C6.
Add-Result 'C7_a_clean_payload_does_not_block' `
    ($driven.Count -ge 1 -and @($driven | Where-Object { $_.Result.CleanVerdict -eq $blockingVerdict[$_.Event] }).Count -eq 0) `
    ($cleanOk -join '; ')

# ── The prose must name the mechanism the harness honours ─────────────────

$prose = @()
foreach ($b in $blocking) {
    $namesMechanism = ($b.Body -match '(?s)"decision"\s*:\s*"block"') -or
                      ($b.Body -match 'permissionDecision') -or
                      ($b.Body -match 'exit code 2')
    $claimsExitBlocks = $b.Body -match '(?i)exit(s|ing)?\s+(with\s+)?code\s+(0|1|3|4|5|6|7|8|9)\b'
    if (-not $namesMechanism -or $claimsExitBlocks) {
        $prose += "$($b.Title): namesMechanism=$namesMechanism claimsExitBlocks=$claimsExitBlocks"
    }
}

Add-Result 'C8_the_readme_names_the_mechanism_the_harness_honours' `
    ($blocking.Count -ge 1 -and $prose.Count -eq 0) ($prose -join '; ')

# ── Report ────────────────────────────────────────────────────────────────

Write-Host '===== hook decision contract tests (issue #339) ====='
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
