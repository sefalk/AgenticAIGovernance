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
CODE_ROOT="$AF_CODE_ROOT"
PYTHON="$AF_PYTHON"

raw=$(cat)

# No interpreter means the confinement cannot be evaluated, so writes are
# refused rather than waved through (issue #251). Reads stay allowed.
af_require_python "$raw" af_is_write_tool "test-writer write confinement"

# Extract tool name
tool_name=$(echo "$raw" | "$PYTHON" -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

# Only inspect file-modifying tools
if ! af_is_write_tool "$tool_name"; then
    echo '{}'
    exit 0
fi

# Every file the call refers to, with the repository it lands in (issue #456).
# A batched edit names several, and one production path among them is still a
# production edit. In a multi-root workspace they need not share a repository.
paths=()
roots=()
rels=()
while IFS= read -r file_path; do
    [ -n "$file_path" ] || continue
    repo=$(af_file_repo "$file_path")
    paths+=("$file_path")
    if [ -n "$repo" ]; then
        roots+=("${repo%%$'\t'*}")
        rels+=("${repo#*$'\t'}")
    else
        roots+=("$CODE_ROOT")
        rels+=("")
    fi
done <<< "$(printf '%s' "$raw" | af_write_paths)"

# Branch context proof -- block file edits unless each repository written to is
# on an agent/* branch. A call naming no path is judged by the deploying
# repository, as before.
if [ "${#paths[@]}" -eq 0 ]; then
    check_roots=("$CODE_ROOT")
else
    check_roots=("${roots[@]}")
fi
for root in "${check_roots[@]}"; do
    current_branch=$(af_branch_label "$root")
    if [ -n "$current_branch" ] && ! grep -qE '^agent/' <<< "$current_branch"; then
        root_json=$(af_json_escape "$root")
        echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Branch context violation: test-writer is running on branch '${current_branch}' in ${root_json}, not on an agent/* branch. Ensure the coordinator created a worktree for this task (Step 0d). Expected branch: agent/{workflow-id}.\"}}"
        exit 0
    fi
done

if [ "${#paths[@]}" -eq 0 ]; then
    echo '{}'
    exit 0
fi

# Check each path against the production source directory of its repository
for i in "${!paths[@]}"; do
    file_path="${paths[$i]}"
    SRC_DIR=$(af_repo_conf_get "${roots[$i]}" SRC_DIR src)
    rel="${rels[$i]}"
    is_prod=0
    if [ -n "$rel" ]; then
        src="${SRC_DIR//\\//}"
        src="${src#./}"
        while [ "${src%/}" != "$src" ]; do src=${src%/}; done
        if [ -z "$src" ] || [ "$src" = "." ] || [ "$rel" = "$src" ] || [[ "$rel" == "$src/"* ]]; then
            is_prod=1
        fi
    else
        # Outside any repository: the comparison every release before #456 made.
        prod_root=$(realpath -m "${SRC_DIR}" 2>/dev/null || echo "${SRC_DIR}")
        resolved=$(realpath -m "$file_path" 2>/dev/null || echo "$file_path")
        [[ "$resolved" == "$prod_root"* ]] && is_prod=1
    fi
    if [ "$is_prod" -eq 1 ]; then
        echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "TDD phase isolation: test-writer cannot modify production code under '"${SRC_DIR}"'/ (offending path: '"${file_path}"'). Only test files should be created or edited during the Red phase."}}'
        exit 0
    fi
done

# Not a production file — allow
echo '{}'
