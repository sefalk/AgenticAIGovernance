#!/usr/bin/env bash
# Agent-scoped Stop hook for the documenter agent.
#
# DOCUMENTATION ARTIFACT GATE (HARD — blocks documenter if required artifacts missing)
#
# Verifies the documenter has produced the required workflow artifacts:
#   1. YAML workflow log in .github/logs/{workflow-id}.yaml
#   2. Retro snippet in retros/auto/{workflow-id}.md or .github/retros/auto/
#
# Fires as SubagentStop when the documenter is invoked by the coordinator.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

set -uo pipefail

# Read stdin (hook input JSON — required by protocol)
cat > /dev/null

# Derive workflow-id from current branch
branch=$(git branch --show-current 2>/dev/null || echo "")
if [[ ! "$branch" =~ ^agent/(.+)$ ]]; then
    echo '{"systemMessage": "documenter:Stop — not on agent/ branch, artifact gate skipped"}'
    exit 0
fi

workflow_id="${BASH_REMATCH[1]}"
missing=()

# ---------- Gate 1: Workflow log YAML ----------

if [ ! -f ".github/logs/${workflow_id}.yaml" ] && [ ! -f ".github/logs/${workflow_id}.yml" ]; then
    missing+=("workflow log (.github/logs/${workflow_id}.yaml)")
fi

# ---------- Gate 2: Retro snippet ----------

# Canonical location is .github/retros/auto/; the bare path is accepted for
# projects that adopted it before the location was settled.
if [ ! -f ".github/retros/auto/${workflow_id}.md" ] && [ ! -f "retros/auto/${workflow_id}.md" ]; then
    missing+=("retro snippet (.github/retros/auto/${workflow_id}.md)")
fi

# ---------- Verdict ----------

if [ ${#missing[@]} -gt 0 ]; then
    list=$(IFS='; '; echo "${missing[*]}")
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"Stop\", \"decision\": \"block\", \"reason\": \"Documentation phase violation: required artifacts missing for workflow '${workflow_id}': ${list}. Create these files before completing.\"}}"
    exit 0
fi

echo "{\"systemMessage\": \"documenter:Stop — artifact gate PASS: workflow log and retro snippet exist for '${workflow_id}'\"}"
exit 0
