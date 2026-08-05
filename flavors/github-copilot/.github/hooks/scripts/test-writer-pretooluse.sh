#!/usr/bin/env bash
# Agent-scoped PreToolUse hook for the test-writer agent.
#
# TDD PHASE ISOLATION (HARD — blocks test-writer from editing production code)
# BRANCH CONTEXT PROOF (HARD — blocks file edits if not on agent/* branch)
#
# The Red phase must only create/edit test files. If the test-writer modifies
# production code under SRC_DIR/, the tests may pass immediately and the
# Green phase becomes a no-op — violating the most fundamental TDD invariant.
#
# Fires only when the test-writer agent is active.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

set -uo pipefail

# Root, config and interpreter come from this script's location, never from
# the cwd the agent happens to run in (issue #54). Bare cwd-relative lookups
# silently read nothing whenever the agent process is not sitting at the repo
# root.
. "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
MAIN_ROOT="$AF_MAIN_ROOT"
CODE_ROOT="$AF_CODE_ROOT"
SRC_DIR=$(af_conf_get SRC_DIR src)
PYTHON="$AF_PYTHON"

raw=$(cat)

if [ -z "$PYTHON" ]; then
    echo '{}'
    exit 0
fi

# Extract tool name
tool_name=$(echo "$raw" | "$PYTHON" -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

# Only inspect file-modifying tools
case "$tool_name" in
    *edit*|*create*|*write*|*file*|*Edit*|*Create*|*Write*|*File*) ;;
    *) echo '{}'; exit 0 ;;
esac

# Branch context proof -- block file edits if not on agent/* branch
current_branch=$(git -C "$CODE_ROOT" branch --show-current 2>/dev/null || true)
if [ -z "$current_branch" ] && [ "$(git -C "$CODE_ROOT" rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ]; then
    current_branch="(detached HEAD)"
fi
if [ -n "$current_branch" ] && ! echo "$current_branch" | grep -qE '^agent/'; then
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Branch context violation: test-writer is running on branch '${current_branch}', not on an agent/* branch. Ensure the coordinator created a worktree for this task (Step 0d). Expected branch: agent/{workflow-id}.\"}}"
    exit 0
fi

# Extract file path
file_path=$(echo "$raw" | "$PYTHON" -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', {})
print(ti.get('filePath', ti.get('path', '')))
" 2>/dev/null)

if [ -z "$file_path" ]; then
    echo '{}'
    exit 0
fi

# Resolve and check against production source directory
resolved=$(realpath -m "$file_path" 2>/dev/null || echo "$file_path")
prod_root=$(realpath -m "${SRC_DIR}" 2>/dev/null || echo "${SRC_DIR}")

if [[ "$resolved" == "$prod_root"* ]]; then
    echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "TDD phase isolation: test-writer cannot modify production code under '"${SRC_DIR}"'/. Only test files should be created or edited during the Red phase."}}'
    exit 0
fi

# Not a production file — allow
echo '{}'
