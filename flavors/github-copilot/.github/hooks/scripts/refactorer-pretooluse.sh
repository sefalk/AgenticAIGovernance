#!/usr/bin/env bash
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

# Root, config and interpreter come from this script's location, never from
# the cwd the agent happens to run in (issue #54). A bare `git` call resolves
# against the agent process's cwd, which silently reports no branch whenever
# that cwd is not the repo.
. "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
MAIN_ROOT="$AF_MAIN_ROOT"
CODE_ROOT="$AF_CODE_ROOT"
PYTHON="$AF_PYTHON"

raw=$(cat)

# No interpreter means neither the branch-context proof nor the creation ban
# can be evaluated, so writes are refused rather than waved through
# (issue #251). Reads stay allowed.
af_require_python "$raw" af_is_write_tool "refactorer branch-context"

# Extract tool name
tool_name=$(echo "$raw" | "$PYTHON" -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

# Branch context proof -- block file edits if not on agent/* branch
if af_is_write_tool "$tool_name"; then
    current_branch=$(git -C "$CODE_ROOT" branch --show-current 2>/dev/null || true)
    if [ -z "$current_branch" ] && [ "$(git -C "$CODE_ROOT" rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ]; then
        current_branch="(detached HEAD)"
    fi
    if [ -n "$current_branch" ] && ! echo "$current_branch" | grep -qE '^agent/'; then
        echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Branch context violation: refactorer is running on branch '${current_branch}', not on an agent/* branch. Ensure the coordinator created a worktree for this task (Step 0d). Expected branch: agent/{workflow-id}.\"}}"
        exit 0
    fi
fi

# Block file and directory creation. Editing an existing file is the whole
# point of the Refactor phase, so only the creating tools are refused --
# matched by name rather than by a substring, which used to put
# `create_and_run_task` in the same branch as `create_file`.
case "$tool_name" in
    create_file|create_directory|create_new_jupyter_notebook|createFile|createDirectory|createDir)
        echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Refactor phase prohibits creating new files or directories. Refactoring must only modify existing files. Use the implementer phase for new file creation."}}'
        exit 0
        ;;
esac

echo '{}'
exit 0
