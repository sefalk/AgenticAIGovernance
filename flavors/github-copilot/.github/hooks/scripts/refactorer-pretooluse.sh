#!/usr/bin/env bash
# copilot:modified  | implementer | 2026-04-14 | add branch context proof gate
# Agent-scoped PreToolUse hook for the refactorer agent.
#
# NO NEW FILES GATE (HARD — blocks refactorer from creating files/directories)
# BRANCH CONTEXT PROOF (HARD — blocks file edits if not on agent/* branch)
#
# Refactoring must only modify existing files. This preventative hook fires
# before createFile/createDirectory calls. Defence-in-depth with the
# refactorer:Stop detective check (git status for untracked files).
#
# Fires only when the refactorer agent is active.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

set -uo pipefail

PYTHON=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "")

raw=$(cat)

if [ -z "$PYTHON" ]; then
    echo '{}'
    exit 0
fi

# Extract tool name
tool_name=$(echo "$raw" | "$PYTHON" -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

# Branch context proof -- block file edits if not on agent/* branch
case "$tool_name" in
    *edit*|*create*|*write*|*file*|*Edit*|*Create*|*Write*|*File*)
        current_branch=$(git branch --show-current 2>/dev/null || true)
        if [ -n "$current_branch" ] && ! echo "$current_branch" | grep -qE '^agent/'; then
            echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Branch context violation: refactorer is running on branch '${current_branch}', not on an agent/* branch. Ensure the coordinator created a worktree for this task (Step 0d). Expected branch: agent/{workflow-id}.\"}}"
            exit 0
        fi
        ;;
esac

# Only inspect creation tools
case "$tool_name" in
    *create*|*Create*) ;;
    *) echo '{}'; exit 0 ;;
esac

# Block file/directory creation
case "$tool_name" in
    *[Ff]ile*|*[Dd]irectory*)
        echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Refactor phase prohibits creating new files or directories. Refactoring must only modify existing files. Use the implementer phase for new file creation."}}'
        exit 0
        ;;
    *)
        echo '{}'
        exit 0
        ;;
esac
