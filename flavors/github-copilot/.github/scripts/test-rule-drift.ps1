# Regression suite: the rule-drift detector derives the duplication inventory (#304).
#
# A hand-written inventory of duplicated rules was out of date before anyone
# acted on it: the corpus grew by a third to double while #30 sat open. So the
# inventory is derived, and this suite pins what the derivation must do --
# deterministically, offline, and without failing CI while it only reports.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$detector = Join-Path $scriptDir 'check-rule-drift.py'
$repoRoot = Split-Path (Split-Path (Split-Path (Split-Path $scriptDir)))

. (Join-Path $scriptDir '_suite_env.ps1')
$python = Get-AfSuitePython $scriptDir
if (-not $python) {
    Write-Host 'SKIP: no Python 3 interpreter found; cannot run the rule-drift detector.'
    exit 0
}

$results = [ordered]@{}
$details = [ordered]@{}
$notes = @()
function Add-Result([string]$Name, [bool]$Ok, [string]$Detail) {
    $script:results[$Name] = $Ok
    $script:details[$Name] = $Detail
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("af304-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $root 'agents') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $root 'instructions') -Force | Out-Null
function Write-Fixture([string]$Rel, [string[]]$Lines) {
    [IO.File]::WriteAllText((Join-Path $root $Rel), (($Lines -join "`n") + "`n"))
}

Write-Fixture 'MANIFEST.md' @(
    '# Manifest',
    '',
    'Workers never run git commands. The coordinator stages every commit.',
    'Agents must never push to a protected branch.',
    'Every commit message must name the agent that wrote it.'
)
Write-Fixture 'copilot-instructions.md' @(
    '# Project',
    '',
    '- **Workers never run git commands.**',
    'The weather is irrelevant to any rule here.'
)
Write-Fixture 'instructions/git.instructions.md' @(
    '---',
    "description: 'Agents must never push to a protected branch.'",
    '---',
    '# Git',
    '',
    'An agent must not push directly to any protected branch.',
    '',
    '```',
    'Every commit message must name the agent that wrote it.',
    '```',
    '',
    '| Gate | Rule |',
    '|---|---|',
    '| G1 | Every commit message must name the agent that wrote it. |'
)
Write-Fixture 'agents/demo.agent.md' @(
    '---',
    'name: demo',
    '---',
    '# Demo',
    '',
    'Tests must always pass before a commit.'
)

function Invoke-Detector([string[]]$Extra) {
    $ErrorActionPreference = 'Continue'
    $out = & $python $detector --root $root @Extra 2>&1 | Out-String
    return [pscustomobject]@{ Exit = $LASTEXITCODE; Out = $out }
}

try {
    $r = Invoke-Detector @('--json')
    $inv = $null
    try { $inv = $r.Out | ConvertFrom-Json } catch { $inv = $null }
    $clusters = @(if ($inv -and $inv.PSObject.Properties['clusters']) { $inv.clusters })

    Add-Result 'R1_it_reports_and_exits_zero_even_with_findings' ($r.Exit -eq 0 -and $clusters.Count -gt 0) "exit=$($r.Exit) clusters=$($clusters.Count) out=$($r.Out.Substring(0, [Math]::Min(300, $r.Out.Length)))"

    $git = @($clusters | Where-Object { @($_.locations | ForEach-Object { $_.text }) -match 'never run git' })
    $gitLocs = @(if ($git.Count -eq 1) { $git[0].locations | ForEach-Object { "$($_.file):$($_.line)" } })
    Add-Result 'R2_an_identical_rule_in_two_files_clusters_and_agrees' `
        ($git.Count -eq 1 -and $git[0].verdict -eq 'agree' -and ($gitLocs -contains 'MANIFEST.md:3') -and ($gitLocs -contains 'copilot-instructions.md:3')) `
        "clusters=$($git.Count) locs=$($gitLocs -join ', ')"

    $push = @($clusters | Where-Object { @($_.locations | ForEach-Object { $_.text }) -match 'protected branch' })
    Add-Result 'R3_a_reworded_rule_clusters_and_diverges' `
        ($push.Count -eq 1 -and $push[0].verdict -eq 'diverge' -and (@($push[0].locations | ForEach-Object { "$($_.file):$($_.line)" }) -contains 'instructions/git.instructions.md:6')) `
        "clusters=$($push.Count)"

    $allLocs = @($clusters | ForEach-Object { $_.locations } | ForEach-Object { "$($_.file):$($_.line)" })
    Add-Result 'R4_code_fences_tables_and_frontmatter_are_not_rules' `
        (-not ($allLocs -match 'git\.instructions\.md:(2|9|14)$')) "locations=$($allLocs -join ', ')"

    Add-Result 'R5_a_statement_without_a_modal_is_not_a_rule' (-not ($allLocs -match 'copilot-instructions\.md:4$')) "locations=$($allLocs -join ', ')"

    Add-Result 'R6_a_rule_found_only_once_forms_no_cluster' (-not ($allLocs -match 'demo\.agent\.md')) "locations=$($allLocs -join ', ')"

    $a = (Invoke-Detector @()).Out
    $b = (Invoke-Detector @()).Out
    Add-Result 'R7_two_runs_produce_identical_output' ($a.Length -gt 0 -and $a -ceq $b) "len a=$($a.Length) b=$($b.Length)"

    Add-Result 'R8_the_text_report_names_file_line_and_verdict' `
        ($a -match 'MANIFEST\.md:3' -and $a -match '(?i)\bagree\b' -and $a -match '(?i)\bdiverge\b') 'text report'

    if (Test-AfSourceTree $scriptDir) {
        $baseline = Join-Path $repoRoot 'docs/metrics/rule-drift-baseline.json'
        $bl = $null
        try { $bl = Get-Content $baseline -Raw | ConvertFrom-Json } catch { $bl = $null }
        Add-Result 'R9_a_baseline_of_the_shipped_payload_is_committed' `
            ($bl -and $bl.PSObject.Properties['clusters'] -and $bl.PSObject.Properties['corpus']) "baseline=$baseline"
    } else {
        $notes += 'R9_a_baseline_of_the_shipped_payload_is_committed -- the baseline lives in the framework repo'
    }
} finally {
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output '===== rule-drift detector tests (issue #304) ====='
foreach ($n in $notes) { Write-Output "  SKIP  $n" }
$failed = 0
foreach ($k in $results.Keys) {
    if ($results[$k]) {
        Write-Output "PASS  $k"
    } else {
        $failed++
        Write-Output "FAIL  $k"
        Write-Output "      $($details[$k])"
    }
}
Write-Output "----- $($results.Count - $failed)/$($results.Count) passed -----"
if ($failed -gt 0) { exit 1 }
exit 0
