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
New-Item -ItemType Directory -Path (Join-Path $root 'skills/demo-skill') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $root 'skills/_available/parked') -Force | Out-Null
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
# #354: an active skill restating a MANIFEST rule, and a parked skill that is not loaded anywhere.
Write-Fixture 'skills/demo-skill/SKILL.md' @(
    '---',
    'name: demo-skill',
    "description: 'Every commit message must name the agent that wrote it.'",
    '---',
    '# Demo skill',
    '',
    'Every commit message must name the agent that wrote it.'
)
Write-Fixture 'skills/_available/parked/SKILL.md' @(
    '# Parked skill',
    '',
    'Workers never run git commands.'
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

    Add-Result 'R18_an_active_skill_restating_a_rule_joins_its_cluster' `
        (($allLocs -contains 'MANIFEST.md:5') -and ($allLocs -contains 'skills/demo-skill/SKILL.md:7')) "locations=$($allLocs -join ', ')"

    Add-Result 'R19_a_skill_under__available_is_not_in_the_corpus' (-not ($allLocs -match '^skills/_available/')) "locations=$($allLocs -join ', ')"

    $a = (Invoke-Detector @()).Out
    $b = (Invoke-Detector @()).Out
    Add-Result 'R7_two_runs_produce_identical_output' ($a.Length -gt 0 -and $a -ceq $b) "len a=$($a.Length) b=$($b.Length)"

    Add-Result 'R8_the_text_report_names_file_line_and_verdict' `
        ($a -match 'MANIFEST\.md:3' -and $a -match '(?i)\bagree\b' -and $a -match '(?i)\bdiverge\b') 'text report'

    # The gate (#305): every cluster carries a recorded decision, keyed by file
    # and wording rather than line, so a moved rule stays decided and a new or
    # reworded duplicate does not.
    $bl = Join-Path ([IO.Path]::GetTempPath()) ((Split-Path $root -Leaf) + '-baseline.json')
    $null = Invoke-Detector @('--write-baseline', $bl)
    $g = Invoke-Detector @('--baseline', $bl)
    Add-Result 'R10_an_undecided_cluster_fails_the_gate' ($g.Exit -eq 1 -and $g.Out -match 'UNDECIDED') "exit=$($g.Exit) out=$($g.Out.Trim())"

    $j = $null
    try { $j = [IO.File]::ReadAllText($bl) | ConvertFrom-Json } catch { $j = $null }
    if ($j -and $j.PSObject.Properties['clusters']) {
        foreach ($c in $j.clusters) {
            $c | Add-Member -NotePropertyName decision -NotePropertyValue 'keep' -Force
            $c | Add-Member -NotePropertyName reason -NotePropertyValue 'fixture: each agent needs the rule in its own file' -Force
        }
        [IO.File]::WriteAllText($bl, ($j | ConvertTo-Json -Depth 10))
    }
    $g = Invoke-Detector @('--baseline', $bl)
    Add-Result 'R11_the_gate_passes_when_every_cluster_is_decided' ($g.Exit -eq 0) "exit=$($g.Exit) out=$($g.Out.Trim())"

    $null = Invoke-Detector @('--write-baseline', $bl)
    $kept = $null
    try { $kept = @(([IO.File]::ReadAllText($bl) | ConvertFrom-Json).clusters | Where-Object { $_.decision -eq 'keep' }) } catch { $kept = $null }
    Add-Result 'R12_rewriting_the_baseline_keeps_its_decisions' ($kept -and $kept.Count -eq $clusters.Count -and $kept.Count -gt 0) "kept=$(if ($kept) { $kept.Count } else { 'none' }) of $($clusters.Count)"

    Write-Fixture 'agents/extra.agent.md' @('# Extra', '', 'Tests must always pass before a commit.')
    $g = Invoke-Detector @('--baseline', $bl)
    Add-Result 'R13_a_new_duplicate_fails_the_gate' ($g.Exit -eq 1 -and $g.Out -match 'NEW' -and $g.Out -match 'agents/extra\.agent\.md') "exit=$($g.Exit) out=$($g.Out.Trim())"
    Remove-Item (Join-Path $root 'agents/extra.agent.md')

    Write-Fixture 'copilot-instructions.md' @('# Project', '', '- **Workers never run any git command themselves.**')
    $g = Invoke-Detector @('--baseline', $bl)
    Add-Result 'R14_a_reworded_member_fails_the_gate' ($g.Exit -eq 1 -and $g.Out -match 'NEW' -and $g.Out -match 'copilot-instructions\.md') "exit=$($g.Exit) out=$($g.Out.Trim())"

    Write-Fixture 'copilot-instructions.md' @('# Project', '', 'The weather is irrelevant to any rule here.')
    $g = Invoke-Detector @('--baseline', $bl)
    Add-Result 'R15_a_resolved_cluster_passes_the_gate' ($g.Exit -eq 0) "exit=$($g.Exit) out=$($g.Out.Trim())"
    Remove-Item $bl -ErrorAction SilentlyContinue

    if (Test-AfSourceTree $scriptDir) {
        $baseline = Join-Path $repoRoot 'docs/metrics/rule-drift-baseline.json'
        $bl = $null
        try { $bl = Get-Content $baseline -Raw | ConvertFrom-Json } catch { $bl = $null }
        Add-Result 'R9_a_baseline_of_the_shipped_payload_is_committed' `
            ($bl -and $bl.PSObject.Properties['clusters'] -and $bl.PSObject.Properties['corpus']) "baseline=$baseline"

        $ErrorActionPreference = 'Continue'
        $shippedOut = & $python $detector --root (Split-Path $scriptDir) --baseline $baseline 2>&1 | Out-String
        $shippedExit = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        Add-Result 'R16_the_shipped_payload_passes_its_committed_baseline' ($shippedExit -eq 0) "exit=$shippedExit out=$($shippedOut.Trim())"

        # Written once through a PowerShell pipe, the baseline stored every dash as cp437 mojibake.
        $blText = [IO.File]::ReadAllText($baseline)
        Add-Result 'R17_the_committed_baseline_is_not_mojibake' (-not $blText.Contains([string][char]0x0393 + [char]0x00C7)) 'baseline contains U+0393 U+00C7'
    } else {
        $notes += 'R9_a_baseline_of_the_shipped_payload_is_committed -- the baseline lives in the framework repo'
    }
} finally {
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
}

# #295: prose clustering cannot see a permission that one source enumerates and
# another never names. The three machine-readable ends can be compared: every
# git subcommand block-dangerous auto-approves under GIT_FEATURE / GIT_MERGE
# must be named by af-env.conf's category text AND by the git-workflow skill's
# autonomy table. Measured 2026-10-19: one gap -- `git restore`, auto-approved
# in both dialects and named in neither document.
$payload = Split-Path $scriptDir
function Get-AutoGitOps([string]$Text, [string]$Start, [string]$End) {
    $i = $Text.IndexOf($Start); $j = $Text.IndexOf($End, [Math]::Max($i, 0))
    if ($i -lt 0 -or $j -lt 0) { return @() }
    $block = $Text.Substring($i, $j - $i)
    $ops = @()
    foreach ($m in [regex]::Matches($block, 'git(?:\\s\+|\[\[:space:\]\]\+)\(?([a-z|-]+(?:\\s\+agent/)?)')) {
        foreach ($t in ($m.Groups[1].Value -split '\|')) {
            $op = ($t -replace '\\s\+agent/', '').Trim()
            if ($op -match '^[a-z][a-z-]+$') { $ops += $op }
        }
    }
    return @($ops | Sort-Object -Unique)
}
$ps1 = Get-Content (Join-Path $payload 'hooks/scripts/block-dangerous.ps1') -Raw
$sh = Get-Content (Join-Path $payload 'hooks/scripts/block-dangerous.sh') -Raw
$hookOps = @(
    (Get-AutoGitOps $ps1 "if (`$catGitFeature -eq 'auto')" '# tests / lint')
    (Get-AutoGitOps $sh 'if [ "$cat_git_feature" = "auto" ]' 'if [ "$cat_tests" = "auto" ]')
) | Sort-Object -Unique
$confText = Get-Content (Join-Path $payload 'af-env.conf') -Raw
$confDesc = [regex]::Match($confText, '(?s)# GIT_FEATURE.*?AUTONOMY_CAT_GIT_MERGE=').Value
$skillText = Get-Content (Join-Path $payload 'skills/git-workflow/SKILL.md') -Raw
$skillTable = (([regex]::Matches($skillText, '(?m)^\| `git [^\n]*') | ForEach-Object { $_.Value }) -join "`n")
$missing = @()
foreach ($op in $hookOps) {
    if ($confDesc -notmatch "\b$op\b") { $missing += "$op (af-env.conf)" }
    if ($skillTable -notmatch "\b$op\b") { $missing += "$op (git-workflow skill)" }
}
Add-Result 'R20_found_the_hook_s_auto_approved_git_operations' ($hookOps.Count -ge 8) "ops=$($hookOps -join ', ')"
Add-Result 'R21_every_auto_approved_git_operation_is_named_in_config_and_skill' ($missing.Count -eq 0) "unnamed: $($missing -join '; ')"

# #369: a threshold the gatekeeper may not have loaded is advisory in practice.
# Measured 2026-10-19 over MP: 7 of 7 workflows with a code-critic step record
# no read of the metrics skill. So the minimal table lives where it is enforced
# -- and since the skill keeps it too, the two copies must be identical, or the
# fix becomes the next drift.
function Get-ThresholdRows([string]$Text) {
    @([regex]::Matches($Text, '(?m)^\| (Domain core|Ports|Adapters|Utilities) \|[^\n]*') |
        ForEach-Object { ($_.Value -replace '\s+', ' ').Trim() })
}
$skillRows = @(Get-ThresholdRows (Get-Content (Join-Path $payload 'skills/metrics/SKILL.md') -Raw -Encoding UTF8))
$criticRows = @(Get-ThresholdRows (Get-Content (Join-Path $payload 'agents/code-critic.agent.md') -Raw -Encoding UTF8))
Add-Result 'R22_code_critic_carries_the_threshold_table_it_enforces' ($criticRows.Count -eq 4) "rows in code-critic: $($criticRows.Count)"
Add-Result 'R23_the_carried_table_equals_the_metrics_skill' `
    ($skillRows.Count -eq 4 -and (($criticRows -join "`n") -ceq ($skillRows -join "`n"))) `
    "skill=$($skillRows -join ' / ') critic=$($criticRows -join ' / ')"

# #284: a tool missing from an agent's set cannot be reached however the payload
# is spelled, which a gate cannot promise. The sets below were decided from the
# measured use (comment on #284, 2026-10-20); a widened set fails here rather
# than changing silently, and so does a new agent that gains an execution tool.
$execTool = '(?i)^(execute/|af-command/run_script$|pylance-mcp-server/pylanceRunCodeSnippet$)'
$declaredExec = @{
    'code-critic'  = 'execute/createAndRunTask execute/runNotebookCell execute/runTask execute/runTests execute/testFailure'
    'coordinator'  = 'af-command/run_script execute/createAndRunTask execute/getTerminalOutput execute/runInTerminal execute/runTask execute/runTests execute/testFailure'
    'documenter'   = 'execute/runTask'
    'implementer'  = 'af-command/run_script execute/createAndRunTask execute/runNotebookCell execute/runTask execute/runTests execute/testFailure pylance-mcp-server/pylanceRunCodeSnippet'
    'planner'      = 'execute/runTask'
    'refactorer'   = 'af-command/run_script execute/createAndRunTask execute/runNotebookCell execute/runTask execute/runTests execute/testFailure pylance-mcp-server/pylanceRunCodeSnippet'
    'test-critic'  = 'execute/runTask execute/runTests execute/testFailure'
    'test-writer'  = 'af-command/run_script execute/runTask execute/runTests execute/testFailure pylance-mcp-server/pylanceRunCodeSnippet'
}
$toolsetDrift = @()
foreach ($agentFile in Get-ChildItem (Join-Path $payload 'agents') -Filter '*.agent.md') {
    $name = $agentFile.Name -replace '\.agent\.md$', ''
    $front = ((Get-Content $agentFile.FullName -Raw -Encoding UTF8) -split '(?m)^---\s*$')[1]
    $toolsBlock = if ($front -match '(?s)\ntools:\s*\n(.*?)(\n\S|$)') { $Matches[1] } else { '' }
    $exec = @([regex]::Matches($toolsBlock, '(?m)^\s*-\s*[''"]?([^''"\s#]+)') |
        ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -match $execTool } | Sort-Object -Unique)
    $want = if ($declaredExec.ContainsKey($name)) { $declaredExec[$name] } else { '' }
    if (($exec -join ' ') -cne $want) { $toolsetDrift += "$name has [$($exec -join ' ')] want [$want]" }
}
Add-Result 'R28_every_agent_s_execution_tools_are_the_declared_set' ($toolsetDrift.Count -eq 0) ($toolsetDrift -join '; ')

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
