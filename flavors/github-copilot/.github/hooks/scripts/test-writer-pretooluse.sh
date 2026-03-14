#!/usr/bin/env bash
# Agent-scoped PreToolUse hook for the test-writer agent.
#
# TDD PHASE ISOLATION (HARD — blocks test-writer from editing production code)
#
# The Red phase must only create/edit test files. If the test-writer modifies
# production code under mpusage/, the tests may pass immediately and the
# Green phase becomes a no-op — violating the most fundamental TDD invariant.
#
# Fires only when the test-writer agent is active.
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
prod_root=$(realpath -m "mpusage" 2>/dev/null || echo "mpusage")

if [[ "$resolved" == "$prod_root"* ]]; then
    echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "TDD phase isolation: test-writer cannot modify production code under mpusage/. Only test files should be created or edited during the Red phase."}}'
    exit 0
fi

# Not a production file — allow
echo '{}'
