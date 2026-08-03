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

# ---------- Gate 2: Workflow Artifact Compliance (advisory) ----------

branch=$(git branch --show-current 2>/dev/null || echo "")
if [[ "$branch" =~ ^agent/(.+)$ ]]; then
    workflow_id="${BASH_REMATCH[1]}"
    missing=()

    # Check for workflow log YAML
    if [ ! -f ".github/logs/${workflow_id}.yaml" ] && [ ! -f ".github/logs/${workflow_id}.yml" ]; then
        missing+=("workflow log (.github/logs/${workflow_id}.yaml)")
    fi

    # Check for retro snippet (canonical first, legacy root path still accepted)
    if [ ! -f ".github/retros/auto/${workflow_id}.md" ] && [ ! -f "retros/auto/${workflow_id}.md" ]; then
        missing+=("retro snippet (.github/retros/auto/${workflow_id}.md)")
    fi

    # Check for plan file marked COMPLETED
    plan_dir="docs/plans"
    if [ -d "$plan_dir" ]; then
        plan_updated=false
        for f in "$plan_dir"/*.md; do
            [ -f "$f" ] || continue
            [[ "$(basename "$f")" == "WIP.md" ]] && continue
            if grep -qi "COMPLETED" "$f" 2>/dev/null; then
                plan_updated=true
                break
            fi
        done
        plan_count=$(find "$plan_dir" -maxdepth 1 -name "*.md" ! -name "WIP.md" 2>/dev/null | wc -l)
        if [ "$plan_updated" = false ] && [ "$plan_count" -gt 0 ]; then
            missing+=("plan file not marked COMPLETED")
        fi
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        list=$(IFS='; '; echo "${missing[*]}")
        echo "{\"gate\": \"workflow-artifacts\", \"status\": \"WARNING\", \"missing\": \"$list\", \"message\": \"Workflow artifacts missing. Was the documenter invoked? Run compliance-checker post-flight or invoke the documenter before ending the session.\"}"
    else
        echo '{"gate": "workflow-artifacts", "status": "PASS"}'
    fi
fi

exit 0
