#!/usr/bin/env bash
# Agent-scoped PreToolUse hook for the refactorer agent.
#
# NO NEW FILES GATE (HARD — blocks refactorer from creating files/directories)
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
