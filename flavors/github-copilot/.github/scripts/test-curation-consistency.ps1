# Regression tests for check-curation-consistency.py, the reconciliation that
# #257 asked for: three records of curated-skill state that nothing compared.
#
# Portable + deterministic: drives the checker against synthetic .github
# fixtures in throwaway temp dirs and asserts the exit-code contract
# (0 consistent, 1 drift). Run from anywhere:
#   powershell .github/scripts/test-curation-consistency.ps1
# Exits non-zero if any scenario fails (CI-friendly).
$ErrorActionPreference = 'Continue'

$scriptDir  = Split-Path -Parent $PSCommandPath
$repoRootAF = (Resolve-Path (Join-Path $scriptDir '..' | Join-Path -ChildPath '..')).Path
$checker    = (Resolve-Path (Join-Path $scriptDir 'check-curation-consistency.py')).Path

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

$python = @(Resolve-Python)
if (-not $python -or -not $python[0]) {
    Write-Host 'SKIP: no Python 3 interpreter found; cannot run curation consistency tests.'
    exit 0
}
$pythonExe = $python[0]
$pythonArgs = @()
if ($python.Count -gt 1) { $pythonArgs = @($python[1..($python.Count - 1)]) }

$passed = 0
$failed = 0

function Pass([string]$label) { Write-Host "  PASS: $label"; $script:passed++ }
function Fail([string]$label, [string]$detail) {
    Write-Host "  FAIL: $label"
    if ($detail) { Write-Host "        $detail" }
    $script:failed++
}

# Builds a synthetic consumer .github tree.
#   -Assignments  agent -> skill list, written to curated-assignments.json
#   -Regions      agent -> skill list, written inside the managed region
#   -BaseSkills   agent -> skill list, written as bullets OUTSIDE the region
#   -Sentinel     skill -> agent list, written to .af-skills-curated
#   -Matrix       agent -> skill list, written to INDEX.md
#   -NoRegion     agents whose file is written without the markers
function New-Fixture {
    param(
        [hashtable]$Assignments = @{},
        [hashtable]$Regions = @{},
        [hashtable]$BaseSkills = @{},
        [hashtable]$Sentinel = @{},
        [hashtable]$Matrix = @{},
        [string[]]$Activated = @(),
        [string[]]$NoRegion = @(),
        [switch]$OmitAssignmentsFile
    )

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("af257_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $gh = Join-Path $root '.github'
    New-Item -ItemType Directory -Path (Join-Path $gh 'skills') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $gh 'agents') -Force | Out-Null

    if (-not $OmitAssignmentsFile) {
        $payload = [ordered]@{
            version   = 1
            activated = @($Activated)
            assignments = [ordered]@{}
        }
        foreach ($agent in $Assignments.Keys) { $payload.assignments[$agent] = @($Assignments[$agent]) }
        ($payload | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath (Join-Path $gh 'skills/curated-assignments.json') -Encoding utf8
    }

    $agents = @($Assignments.Keys) + @($Regions.Keys) + @($BaseSkills.Keys) + @($Matrix.Keys)
    foreach ($skillAgents in $Sentinel.Values) { $agents += $skillAgents }
    foreach ($agent in ($agents | Sort-Object -Unique)) {
        $lines = @("# $agent", '', '## Skills', '')
        foreach ($base in @($BaseSkills[$agent])) {
            if ($base) { $lines += "- **$base** (``skills/$base/SKILL.md``) -- base skill" }
        }
        if ($NoRegion -notcontains $agent) {
            $lines += '<!-- AF:MANAGED:curated-skills:START -->'
            foreach ($skill in @($Regions[$agent])) {
                if ($skill) { $lines += "- **$skill** (``skills/$skill/SKILL.md``) -- curated" }
            }
            $lines += '<!-- AF:MANAGED:curated-skills:END -->'
        }
        $lines -join "`n" | Set-Content -LiteralPath (Join-Path $gh "agents/$agent.agent.md") -Encoding utf8
    }

    if ($Sentinel.Count -gt 0) {
        $sentinelLines = @('version: 1', 'activated:')
        foreach ($skill in $Sentinel.Keys) {
            $sentinelLines += "  - name: $skill"
            $sentinelLines += "    agents: [$(@($Sentinel[$skill]) -join ', ')]"
        }
        $sentinelLines += 'user_overrides: []'
        $sentinelLines -join "`n" | Set-Content -LiteralPath (Join-Path $gh '.af-skills-curated') -Encoding utf8
    }

    if ($Matrix.Count -gt 0) {
        $indexLines = @('# Skills', '', '| Agent | Skills |', '|---|---|')
        foreach ($agent in $Matrix.Keys) {
            $indexLines += "| **$agent** | $(@($Matrix[$agent]) -join ', ') |"
        }
        $indexLines -join "`n" | Set-Content -LiteralPath (Join-Path $gh 'skills/INDEX.md') -Encoding utf8
    }

    return $root
}

function Invoke-Checker([string]$Root, [switch]$Brief) {
    $checkerArgs = @($checker, '--project-dir', $Root)
    if ($Brief) { $checkerArgs += '--brief' }
    $out = & $pythonExe @($pythonArgs + $checkerArgs) 2>&1 | Out-String
    $code = $LASTEXITCODE
    # Outside --brief the checker always says something. Silence means it never
    # ran, and an unrun checker must not inherit a stale exit code as a pass.
    if (-not $Brief -and [string]::IsNullOrWhiteSpace($out)) {
        return @{ Output = 'the checker produced no output -- it did not run'; Code = -1 }
    }
    return @{ Output = $out; Code = $code }
}

function Test-Scenario {
    param([string]$Label, [string]$Root, [int]$ExpectCode, [string]$ExpectText, [string]$RejectText)

    $result = Invoke-Checker -Root $Root
    Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue

    if ($result.Code -ne $ExpectCode) {
        Fail $Label "expected exit $ExpectCode, got $($result.Code): $($result.Output.Trim())"
        return
    }
    if ($ExpectText -and $result.Output -notmatch [regex]::Escape($ExpectText)) {
        Fail $Label "output did not name the problem ('$ExpectText'): $($result.Output.Trim())"
        return
    }
    if ($RejectText -and $result.Output -match [regex]::Escape($RejectText)) {
        Fail $Label "output raised '$RejectText', which is not drift: $($result.Output.Trim())"
        return
    }
    Pass $Label
}

Write-Host '== check-curation-consistency =='

# The records agree -- the common case must stay silent.
$root = New-Fixture -Activated @('python-dev') `
    -Assignments @{ implementer = @('python-dev'); 'code-critic' = @('python-dev') } `
    -Regions     @{ implementer = @('python-dev'); 'code-critic' = @('python-dev') } `
    -Sentinel    @{ 'python-dev' = @('implementer', 'code-critic') } `
    -Matrix      @{ implementer = @('python-dev'); 'code-critic' = @('python-dev') }
Test-Scenario -Label 'Consistent records pass' -Root $root -ExpectCode 0

# The #257 instance: an agent the other two records claim, absent from assignments.
$root = New-Fixture -Activated @('python-dev') `
    -Assignments @{ implementer = @('python-dev') } `
    -Regions     @{ implementer = @('python-dev'); refactorer = @() } `
    -Sentinel    @{ 'python-dev' = @('implementer', 'refactorer') } `
    -Matrix      @{ implementer = @('python-dev'); refactorer = @('python-dev') }
Test-Scenario -Label 'An agent missing from assignments is reported' -Root $root -ExpectCode 1 -ExpectText 'refactorer'

# A region body that does not match its own assignment list.
$root = New-Fixture -Activated @('python-dev') `
    -Assignments @{ implementer = @('python-dev') } `
    -Regions     @{ implementer = @('python-dev', 'data-quality') }
Test-Scenario -Label 'A region holding an unassigned skill is reported' -Root $root -ExpectCode 1 -ExpectText 'data-quality'

# An assignment the reapply can never write, because the agent has no region.
$root = New-Fixture -Activated @('python-dev') `
    -Assignments @{ coordinator = @('python-dev') } `
    -NoRegion    @('coordinator')
Test-Scenario -Label 'An assignment to a region-less agent is reported' -Root $root -ExpectCode 1 -ExpectText 'no curated-skills region'

# Base dedup is deliberate, not drift: a promoted skill lives outside the region.
$root = New-Fixture -Activated @('python-dev') `
    -Assignments @{ researcher = @() } `
    -Regions     @{ researcher = @() } `
    -BaseSkills  @{ researcher = @('python-dev') } `
    -Sentinel    @{ 'python-dev' = @('researcher') } `
    -Matrix      @{ researcher = @('python-dev') }
Test-Scenario -Label 'A promoted base skill is not mistaken for drift' -Root $root -ExpectCode 0

# A base skill in the matrix says nothing about curation and must not be read as it.
$root = New-Fixture -Activated @('python-dev') `
    -Assignments @{ implementer = @('python-dev') } `
    -Regions     @{ implementer = @('python-dev') } `
    -Matrix      @{ implementer = @('python-dev', 'unit-testing') }
Test-Scenario -Label 'An uncurated skill in the matrix is ignored' -Root $root -ExpectCode 0 -RejectText 'unit-testing'

# No curation state at all is not a failure.
$root = New-Fixture -OmitAssignmentsFile
Test-Scenario -Label 'A project without curated skills passes' -Root $root -ExpectCode 0

# --brief is what the deploy calls: silent unless there is something to say.
$root = New-Fixture -Activated @('python-dev') `
    -Assignments @{ implementer = @('python-dev') } `
    -Regions     @{ implementer = @('python-dev') }
$brief = Invoke-Checker -Root $root -Brief
Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
if ($brief.Code -eq 0 -and [string]::IsNullOrWhiteSpace($brief.Output)) {
    Pass 'Brief mode stays silent when the records agree'
} else {
    Fail 'Brief mode stays silent when the records agree' "exit $($brief.Code), output '$($brief.Output.Trim())'"
}

Write-Host ''
Write-Host '=== Summary ==='
Write-Host "  Passed: $passed"
Write-Host "  Failed: $failed"

if ($failed -gt 0) { exit 1 }
Write-Host '  All curation consistency tests passed.'
exit 0
