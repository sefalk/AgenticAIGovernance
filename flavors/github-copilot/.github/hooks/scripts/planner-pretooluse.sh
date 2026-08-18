#!/usr/bin/env bash
# Agent-scoped PreToolUse hook for the planner agent.
#
# PLAN DIRECTORY CONFINEMENT (HARD — blocks every write outside a plans/ dir)
#
# The planner produces the plan and, since issue #130, persists it, so the
# document reaches disk in one emission instead of three: the planner used to
# return the text, the coordinator repeated it verbatim into the documenter's
# prompt, and the documenter emitted it a third time as the `createFile`
# argument. Measured over 66 plans, the relayed document is a median 1,747
# tokens, so two of those three emissions were pure relay.
#
# That trade widens the write surface of an agent that was incapable of
# touching the repository, and the tool list alone is not what holds it: this
# gate is. It is an ALLOWLIST, not a denylist — anything a denylist forgot to
# name would be permitted, and the planner may write in exactly one place.
#
# `plans` as a path segment is the same definition check-plan-budget.py uses.
#
# Fires only when the planner agent is active.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

set -uo pipefail

# Root, config and interpreter come from this script's location, never from
# the cwd the agent happens to run in (issue #54).
. "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
CODE_ROOT="$AF_CODE_ROOT"
PYTHON="$AF_PYTHON"

raw=$(cat)

if [ -z "$PYTHON" ]; then
    echo '{}'
    exit 0
fi

tool_name=$(echo "$raw" | "$PYTHON" -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

if ! af_is_write_tool "$tool_name"; then
    echo '{}'
    exit 0
fi

file_paths=$(printf '%s' "$raw" | af_write_paths)

# A write tool whose payload names no path is not a write this gate can clear.
# Failing open here would let an unrecognised payload shape carry the very
# edit the gate exists to prevent (the #64 defect).
if [ -z "$file_paths" ]; then
    echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Plan directory confinement: planner called a write tool with no readable file path, so the target cannot be checked against the plan directory. The planner may only create the plan document."}}'
    exit 0
fi

root_full=$(realpath -m "$CODE_ROOT" 2>/dev/null || echo "$CODE_ROOT")

while IFS= read -r file_path; do
    [ -n "$file_path" ] || continue

    case "$file_path" in
        /*) resolved=$(realpath -m "$file_path" 2>/dev/null || echo "$file_path") ;;
        *)  resolved=$(realpath -m "${root_full}/${file_path}" 2>/dev/null || echo "${root_full}/${file_path}") ;;
    esac

    allowed=0
    # `..` climbing out of the repository resolves to a real path with a real
    # `plans` segment above it, so containment is checked before the shape.
    if [[ "$resolved" == "$root_full"/* ]]; then
        relative="${resolved#"$root_full"/}"
        dirs="${relative%/*}"
        if [ "$dirs" != "$relative" ] && [[ "$relative" == *.md || "$relative" == *.MD ]]; then
            case "/$dirs/" in
                */plans/*) allowed=1 ;;
            esac
        fi
    fi

    if [ "$allowed" -eq 0 ]; then
        echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Plan directory confinement: planner cannot write to '"${file_path}"'. The planner may create only the plan document — a .md file inside a '"'"'plans'"'"' directory within the repository (default docs/plans/). Everything else in this workflow is written by the test-writer, implementer, refactorer or documenter."}}'
        exit 0
    fi
done <<< "$file_paths"

echo '{}'
