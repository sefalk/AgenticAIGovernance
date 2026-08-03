# Stop hook: Workflow artifact checks before session end.
#
# Gate 1: RETIRED -- test suite enforcement moved to agent-scoped SubagentStop hooks
#         (implementer-stop.ps1/.sh). VS Code has a bug where Stop hooks in
#         .agent.md frontmatter crash subagent invocation; SubagentStop works.
# Gate 2: Workflow artifacts exist (ADVISORY -- warns but does not block)
#
# See Idea 39 for rationale.

$ErrorActionPreference = 'SilentlyContinue'
# ---------- Gate 2: Workflow Artifact Compliance (advisory) ----------

# Detect the current branch to derive workflow-id
$branch = & git branch --show-current 2>$null
if ($branch -and $branch -match '^agent/(.+)$') {
    $workflowId = $Matches[1]
    $missing = @()

    # Check for workflow log YAML
    $logPattern = ".github/logs/$workflowId.yaml"
    if (-not (Test-Path $logPattern)) {
        $logPatternAlt = ".github/logs/$workflowId.yml"
        if (-not (Test-Path $logPatternAlt)) {
            $missing += "workflow log (.github/logs/$workflowId.yaml)"
        }
    }

    # Check for retro snippet (canonical first, legacy root path still accepted)
    $retroPattern = ".github/retros/auto/$workflowId.md"
    $retroPatternGH = "retros/auto/$workflowId.md"
    if (-not (Test-Path $retroPattern) -and -not (Test-Path $retroPatternGH)) {
        $missing += "retro snippet (.github/retros/auto/$workflowId.md)"
    }

    # Check for plan file in docs/plans/ (any file mentioning COMPLETED)
    $planDir = "docs/plans"
    $planUpdated = $false
    if (Test-Path $planDir) {
        $planFiles = Get-ChildItem "$planDir/*.md" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "WIP.md" }
        foreach ($f in $planFiles) {
            $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
            if ($content -match 'COMPLETED') {
                $planUpdated = $true
                break
            }
        }
        if (-not $planUpdated -and $planFiles.Count -gt 0) {
            $missing += "plan file not marked COMPLETED"
        }
    }

    if ($missing.Count -gt 0) {
        $list = $missing -join '; '
        Write-Output "{`"gate`": `"workflow-artifacts`", `"status`": `"WARNING`", `"missing`": `"$list`", `"message`": `"Workflow artifacts missing. Was the documenter invoked? Run compliance-checker post-flight or invoke the documenter before ending the session.`"}"
    } else {
        Write-Output '{"gate": "workflow-artifacts", "status": "PASS"}'
    }
}

exit 0
