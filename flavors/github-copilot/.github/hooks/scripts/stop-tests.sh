#!/usr/bin/env bash
# Stop hook: Workflow artifact checks before session end.
#
# Gate 1: RETIRED — test suite enforcement moved to agent-scoped SubagentStop hooks
#         (implementer-stop.sh). VS Code has a bug where Stop hooks in
#         .agent.md frontmatter crash subagent invocation; SubagentStop works.
# Gate 2: Workflow artifacts exist (ADVISORY — warns but does not block)
#
# See Idea 39 for rationale.

set -uo pipefail

# Shares the lifecycle reader with documenter-stop so both hooks judge the
# same condition (issue #72). They differ in force, not in what they consider
# wrong: this one is advisory and fires at session end, where a workflow may
# legitimately still be running.
. "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# ---------- Gate 2: Workflow Artifact Compliance (advisory) ----------

branch=$(git branch --show-current 2>/dev/null || echo "")
if [[ "$branch" =~ ^agent/(.+)$ ]]; then
    workflow_id="${BASH_REMATCH[1]}"
    missing=()

    plan_info=$(af_plan_lifecycle "$workflow_id" "$AF_CODE_ROOT")
    plan_found="${plan_info%%|*}"
    plan_rest="${plan_info#*|}"
    plan_status="${plan_rest%%|*}"

    if [ "$plan_found" != "1" ]; then
        echo "{\"gate\": \"workflow-artifacts\", \"status\": \"WARNING\", \"missing\": \"plan file naming agent/${workflow_id}\", \"message\": \"No plan file names this branch, so whether the workflow finished cannot be told. Run compliance-checker post-flight before ending the session.\"}"
        exit 0
    fi

    if [ "$plan_status" != "COMPLETED" ]; then
        # The workflow has not claimed to be finished, so its closing artifacts
        # are not due yet. Reporting them as missing here is what taught agents
        # to write them early (issue #72).
        echo "{\"gate\": \"workflow-artifacts\", \"status\": \"PENDING\", \"plan_status\": \"${plan_status:-unset}\", \"message\": \"Workflow still open; closing artifacts are due at finalisation, not now.\"}"
        exit 0
    fi

    # Plan says COMPLETED. From here the condition is exactly the one
    # documenter-stop blocks finalisation on.

    # Check for workflow log YAML
    if [ ! -f ".github/logs/${workflow_id}.yaml" ] && [ ! -f ".github/logs/${workflow_id}.yml" ]; then
        missing+=("workflow log (.github/logs/${workflow_id}.yaml)")
    fi

    # Retro snippet: one destination -- the one `RETRO_DIR` names (issue #117)
    # -- and only when the log shows there was something to learn (issues #98,
    # #27).
    retro_dir=$(af_retro_dir)
    if [ ! -f "${retro_dir}/${workflow_id}.md" ]; then
        retro_verdict=$(af_retro_required "$workflow_id")
        if [ "${retro_verdict%%|*}" = "1" ]; then
            if [ "$retro_dir" != "retros/auto" ] && [ -f "retros/auto/${workflow_id}.md" ]; then
                missing+=("retro snippet at its configured path (found 'retros/auto/${workflow_id}.md', no longer accepted)")
            else
                missing+=("retro snippet (${retro_dir}/${workflow_id}.md)")
            fi
        fi
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        list=$(IFS='; '; echo "${missing[*]}")
        echo "{\"gate\": \"workflow-artifacts\", \"status\": \"WARNING\", \"missing\": \"$list\", \"message\": \"Plan is marked COMPLETED but its closing artifacts are missing. Was the documenter invoked? Run compliance-checker post-flight before ending the session.\"}"
    else
        echo '{"gate": "workflow-artifacts", "status": "PASS"}'
    fi
fi

exit 0
