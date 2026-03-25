#!/usr/bin/env bash
# Agent-scoped PreToolUse hook for the test-writer agent.
#
# TDD PHASE ISOLATION (HARD — blocks test-writer from editing production code)
#
# The Red phase must only create/edit test files. If the test-writer modifies
# production code under SRC_DIR/, the tests may pass immediately and the
# Green phase becomes a no-op — violating the most fundamental TDD invariant.
#
# Fires only when the test-writer agent is active.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

set -uo pipefail

# Load project config
SRC_DIR="src"
_conf=".github/af-env.conf"
if [ -f "$_conf" ]; then
    _val=$(grep -E '^SRC_DIR=' "$_conf" | head -1 | cut -d= -f2-)
    [ -n "$_val" ] && SRC_DIR="$_val"
fi

PYTHON=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "")

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
