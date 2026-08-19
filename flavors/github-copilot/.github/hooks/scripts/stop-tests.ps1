# Stop hook: Workflow artifact checks before session end.
#
# Gate 1: RETIRED -- test suite enforcement moved to agent-scoped SubagentStop hooks
#         (implementer-stop.ps1/.sh). VS Code has a bug where Stop hooks in
#         .agent.md frontmatter crash subagent invocation; SubagentStop works.
# Gate 2: Workflow artifacts exist (ADVISORY -- warns but does not block)
#
# See Idea 39 for rationale.

$ErrorActionPreference = 'SilentlyContinue'

# Shares the lifecycle reader with documenter-stop so both hooks judge the
# same condition (issue #72). They differ in force, not in what they consider
# wrong: this one is advisory and fires at session end, where a workflow may
# legitimately still be running.
. "$PSScriptRoot/_common.ps1"

# ---------- Gate 2: Workflow Artifact Compliance (advisory) ----------

# Detect the current branch to derive workflow-id
$branch = & git branch --show-current 2>$null
if ($branch -and $branch -match '^agent/(.+)$') {
    $workflowId = $Matches[1]
    $missing = @()

    $plan = Get-AfPlanLifecycle -WorkflowId $workflowId -Root $AfCodeRoot

    if (-not $plan.Found) {
        Write-Output "{`"gate`": `"workflow-artifacts`", `"status`": `"WARNING`", `"missing`": `"plan file naming agent/$workflowId`", `"message`": `"No plan file names this branch, so whether the workflow finished cannot be told. Run compliance-checker post-flight before ending the session.`"}"
        exit 0
    }

    if ($plan.Status -ne 'COMPLETED') {
        # The workflow has not claimed to be finished, so its closing artifacts
        # are not due yet. Reporting them as missing here is what taught agents
        # to write them early (issue #72).
        $seen = if ($plan.Status) { $plan.Status } else { 'unset' }
        Write-Output "{`"gate`": `"workflow-artifacts`", `"status`": `"PENDING`", `"plan_status`": `"$seen`", `"message`": `"Workflow still open; closing artifacts are due at finalisation, not now.`"}"
        exit 0
    }

    # Plan says COMPLETED. From here the condition is exactly the one
    # documenter-stop blocks finalisation on.

    # Check for workflow log YAML
    $logPattern = ".github/logs/$workflowId.yaml"
    if (-not (Test-Path $logPattern)) {
        $logPatternAlt = ".github/logs/$workflowId.yml"
        if (-not (Test-Path $logPatternAlt)) {
            $missing += "workflow log (.github/logs/$workflowId.yaml)"
        }
    }

    # Retro snippet: one destination -- the one `RETRO_DIR` names (issue #117)
    # -- and only when the log shows there was something to learn (issues #98,
    # #27). Same condition documenter-stop blocks on, asserted with less force.
    $retroDir = Get-AfRetroDir
    $retroPattern = "$retroDir/$workflowId.md"
    $legacyRetro = "retros/auto/$workflowId.md"
    if (-not (Test-Path $retroPattern)) {
        $retro = Get-AfRetroRequirement -WorkflowId $workflowId
        if ($retro.Required) {
            if ($legacyRetro -ne $retroPattern -and (Test-Path $legacyRetro)) {
                $missing += "retro snippet at its configured path (found '$legacyRetro', no longer accepted)"
            } else {
                $missing += "retro snippet ($retroPattern)"
            }
        }
    }

    if ($missing.Count -gt 0) {
        $list = $missing -join '; '
        Write-Output "{`"gate`": `"workflow-artifacts`", `"status`": `"WARNING`", `"missing`": `"$list`", `"message`": `"Plan is marked COMPLETED but its closing artifacts are missing. Was the documenter invoked? Run compliance-checker post-flight before ending the session.`"}"
    } else {
        Write-Output '{"gate": "workflow-artifacts", "status": "PASS"}'
    }
}

exit 0
