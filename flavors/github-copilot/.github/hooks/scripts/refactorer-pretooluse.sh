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
CODE_ROOT="$AF_CODE_ROOT"
PYTHON="$AF_PYTHON"

raw=$(cat)

# No interpreter means neither the branch-context proof nor the creation ban
# can be evaluated, so writes are refused rather than waved through
# (issue #251). Reads stay allowed.
af_require_python "$raw" af_is_write_tool "refactorer branch-context"

# Extract tool name
tool_name=$(echo "$raw" | "$PYTHON" -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

# Branch context proof -- block file edits unless each repository written to is
# on an agent/* branch. In a multi-root workspace the edited file need not live
# in the repository this hook is deployed in, so the file names the repository
# to ask (issue #456); a call naming no path is judged by the deploying one.
if af_is_write_tool "$tool_name"; then
    check_roots=()
    while IFS= read -r file_path; do
        [ -n "$file_path" ] || continue
        repo=$(af_file_repo "$file_path")
        if [ -n "$repo" ]; then
            check_roots+=("${repo%%$'\t'*}")
        else
            check_roots+=("$CODE_ROOT")
        fi
    done <<< "$(printf '%s' "$raw" | af_write_paths)"
    [ "${#check_roots[@]}" -gt 0 ] || check_roots=("$CODE_ROOT")
    for root in "${check_roots[@]}"; do
        current_branch=$(af_branch_label "$root")
        if [ -n "$current_branch" ] && ! grep -qE '^agent/' <<< "$current_branch"; then
            root_json=$(af_json_escape "$root")
            echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Branch context violation: refactorer is running on branch '${current_branch}' in ${root_json}, not on an agent/* branch. Ensure the coordinator created a worktree for this task (Step 0d). Expected branch: agent/{workflow-id}.\"}}"
            exit 0
        fi
    done
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
