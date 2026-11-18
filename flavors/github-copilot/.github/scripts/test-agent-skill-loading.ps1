<#
Regression tests for agent skill preloads and conditional skill declarations.
Run by run-all-tests.ps1.
#>
$ErrorActionPreference = 'Continue'

$scriptDir = Split-Path -Parent $PSCommandPath
$validator = (Resolve-Path (Join-Path $scriptDir 'validate-skills.py')).Path
. (Join-Path $scriptDir '_suite_env.ps1')

$python = @(Get-AfSuitePython $scriptDir)
if (-not $python -or -not $python[0]) {
    Write-Host 'SKIP: no Python 3 interpreter found; cannot run agent skill loading tests.'
    exit 0
}
$pythonExe = $python[0]
$pythonArgs = @()
if ($python.Count -gt 1) { $pythonArgs = @($python[1..($python.Count - 1)]) }
$encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false

$passed = 0
$failed = 0

function Write-Utf8([string]$Path, [string]$Content) {
    [System.IO.File]::WriteAllText($Path, $Content, $script:encoding)
}

function New-Fixture {
    param(
        [hashtable]$Skills = @{},
        [hashtable]$Agents = @{}
    )

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("af549_skills_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $githubDir = Join-Path $root '.github'
    $skillsDir = Join-Path $githubDir 'skills'
    $agentsDir = Join-Path $githubDir 'agents'
    New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null
    New-Item -ItemType Directory -Path $agentsDir -Force | Out-Null

    $index = @('# Skills', '', '| # | Skill | Description | Agents |', '|---|---|---|---|')
    $number = 1
    foreach ($skillName in $Skills.Keys) {
        $skill = $Skills[$skillName]
        $frontmatter = @('---', "name: $skillName", "description: Fixture skill $skillName.")
        if ($skill.DisableModelInvocation) { $frontmatter += 'disable-model-invocation: true' }
        if ($skill.RequiredAgents) {
            $priority = if ($skill.Priority) { $skill.Priority } else { 'required' }
            $frontmatter += @(
                'metadata:',
                '  activation:',
                "    agents: [$($skill.RequiredAgents -join ', ')]",
                "    priority: $priority"
            )
        }
        $frontmatter += @('---', '', "# $skillName")
        $skillDir = Join-Path $skillsDir $skillName
        New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
        Write-Utf8 (Join-Path $skillDir 'SKILL.md') ($frontmatter -join "`n")
        $index += "| $number | ``$skillName`` | Fixture | test-agent |"
        $number++
    }
    Write-Utf8 (Join-Path $skillsDir 'INDEX.md') ($index -join "`n")

    foreach ($agentName in $Agents.Keys) {
        $agent = $Agents[$agentName]
        $lines = @('---', "name: $agentName")
        if ($agent.ContainsKey('Tools')) {
            $lines += 'tools:'
            foreach ($tool in $agent.Tools) { $lines += "  - $tool" }
        }
        if ($agent.ContainsKey('Preloads')) {
            $lines += 'skills:'
            foreach ($skillName in $agent.Preloads) { $lines += "  - $skillName" }
        }
        $lines += @('---', '', "# $agentName")
        if ($agent.Body) { $lines += $agent.Body }
        if ($agent.ContainsKey('Conditional')) {
            $lines += @('', '## Conditional Skills')
            foreach ($skillName in $agent.Conditional) { $lines += "- $skillName" }
        }
        Write-Utf8 (Join-Path $agentsDir "$agentName.agent.md") ($lines -join "`n")
    }
    return $githubDir
}

function Invoke-Validator([string]$GithubDir) {
    $output = & $pythonExe @($pythonArgs + @($validator, '--root', $GithubDir)) 2>&1 | Out-String
    return @{ Output = $output; Code = $LASTEXITCODE }
}

function Test-Scenario {
    param(
        [string]$Label,
        [hashtable]$Skills,
        [hashtable]$Agents,
        [int]$ExpectedCode,
        [string]$ExpectedText = ''
    )

    $githubDir = New-Fixture -Skills $Skills -Agents $Agents
    $result = Invoke-Validator $githubDir
    Remove-Item -LiteralPath (Split-Path -Parent $githubDir) -Recurse -Force -ErrorAction SilentlyContinue

    if ($result.Code -ne $ExpectedCode) {
        Write-Host "  FAIL: $Label (expected exit $ExpectedCode, got $($result.Code))"
        Write-Host "        $($result.Output.Trim())"
        $script:failed++
        return
    }
    if ($ExpectedText -and $result.Output -notmatch [regex]::Escape($ExpectedText)) {
        Write-Host "  FAIL: $Label (output did not include '$ExpectedText')"
        Write-Host "        $($result.Output.Trim())"
        $script:failed++
        return
    }
    Write-Host "  PASS: $Label"
    $script:passed++
}

Write-Host '== agent skill loading validation =='

$validSkills = @{
    'core-skill' = @{}
    'on-demand-skill' = @{}
}
Test-Scenario -Label 'Valid preload and conditional skill pass' -Skills $validSkills -Agents @{
    'test-agent' = @{
        Tools = @('read/readFile', 'skill')
        Preloads = @('core-skill')
        Conditional = @('on-demand-skill')
    }
} -ExpectedCode 0

Test-Scenario -Label 'Unknown preloaded skill is reported' -Skills $validSkills -Agents @{
    'test-agent' = @{ Preloads = @('missing-skill') }
} -ExpectedCode 1 -ExpectedText 'missing-skill'

Test-Scenario -Label 'Unknown conditional skill is reported' -Skills $validSkills -Agents @{
    'test-agent' = @{ Tools = @('skill'); Conditional = @('missing-skill') }
} -ExpectedCode 1 -ExpectedText 'missing-skill'

Test-Scenario -Label 'Conditional skill cannot disable model invocation' -Skills @{
    'on-demand-skill' = @{ DisableModelInvocation = $true }
} -Agents @{
    'test-agent' = @{ Tools = @('skill'); Conditional = @('on-demand-skill') }
} -ExpectedCode 1 -ExpectedText 'disable-model-invocation'

Test-Scenario -Label 'Preloaded skill may disable model invocation' -Skills @{
    'core-skill' = @{ DisableModelInvocation = $true }
} -Agents @{
    'test-agent' = @{ Preloads = @('core-skill') }
} -ExpectedCode 0

Test-Scenario -Label 'Conditional skills require the skill tool' -Skills $validSkills -Agents @{
    'test-agent' = @{ Conditional = @('on-demand-skill') }
} -ExpectedCode 1 -ExpectedText 'skill'

Test-Scenario -Label 'Required activation skills must be preloaded' -Skills @{
    'required-skill' = @{ RequiredAgents = @('test-agent') }
} -Agents @{
    'test-agent' = @{ Tools = @('skill'); Conditional = @('required-skill') }
} -ExpectedCode 1 -ExpectedText "required skill 'required-skill' from activation metadata must be preloaded"

Test-Scenario -Label 'Preloaded required activation skill passes' -Skills @{
    'required-skill' = @{ RequiredAgents = @('test-agent') }
} -Agents @{
    'test-agent' = @{ Preloads = @('required-skill') }
} -ExpectedCode 0

Test-Scenario -Label 'Recommended activation skill may be conditional' -Skills @{
    'recommended-skill' = @{ RequiredAgents = @('test-agent'); Priority = 'recommended' }
} -Agents @{
    'test-agent' = @{ Tools = @('skill'); Conditional = @('recommended-skill') }
} -ExpectedCode 0

Test-Scenario -Label 'Skill tool is rejected without conditional skills' -Skills $validSkills -Agents @{
    'test-agent' = @{ Tools = @('skill') }
} -ExpectedCode 1 -ExpectedText 'Conditional Skills'

Test-Scenario -Label 'Preloaded and conditional skill overlap is reported' -Skills $validSkills -Agents @{
    'test-agent' = @{ Tools = @('skill'); Preloads = @('core-skill'); Conditional = @('core-skill') }
} -ExpectedCode 1 -ExpectedText 'both preloaded and conditional'

Test-Scenario -Label 'Stale relative skill path is reported' -Skills $validSkills -Agents @{
    'test-agent' = @{ Body = @('', 'See `skills/core-skill/SKILL.md`.') }
} -ExpectedCode 1 -ExpectedText 'skills/core-skill/SKILL.md'

Test-Scenario -Label 'Repository-root skill path is accepted' -Skills $validSkills -Agents @{
    'test-agent' = @{ Body = @('', 'See `.github/skills/core-skill/SKILL.md`.') }
} -ExpectedCode 0

Test-Scenario -Label 'Agent-relative skill path is accepted' -Skills $validSkills -Agents @{
    'test-agent' = @{ Body = @('', 'See `../skills/core-skill/SKILL.md`.') }
} -ExpectedCode 0

Test-Scenario -Label 'Managed-region skill paths are excluded from framework validation' -Skills $validSkills -Agents @{
    'test-agent' = @{
        Body = @(
            '',
            '<!-- AF:MANAGED:curated-skills:START -->',
            'See `skills/project-skill/SKILL.md`.',
            '<!-- AF:MANAGED:curated-skills:END -->'
        )
    }
} -ExpectedCode 0

Write-Host ''
Write-Host '=== Summary ==='
Write-Host "  Passed: $passed"
Write-Host "  Failed: $failed"
if ($failed -gt 0) { exit 1 }
Write-Host '  All agent skill loading tests passed.'
exit 0
