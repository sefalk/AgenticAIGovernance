#!/usr/bin/env bash
# Agent-scoped PostToolUse hook for the coordinator agent.
#
# TERMINAL FILE-WRITE DETECTOR (detective -- warns when terminal modifies source files)
#
# Fires AFTER terminal commands. Checks git status for modified source files.
# Detective control complementing the preventative PreToolUse hook.
#
# Fires only when the coordinator agent is active.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

set -euo pipefail

# Load project config
SRC_DIR="src"
_conf=".github/af-env.conf"
if [ -f "$_conf" ]; then
    _val=$(grep -E '^SRC_DIR=' "$_conf" | head -1 | cut -d= -f2-)
    [ -n "$_val" ] && SRC_DIR="$_val"
fi

RAW=$(cat)
[ -z "$RAW" ] && echo '{}' && exit 0

TOOL_NAME=$(echo "$RAW" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_name', d.get('toolName', '')))
except Exception:
    print('')
" 2>/dev/null)

[ -z "$TOOL_NAME" ] && echo '{}' && exit 0

# Only inspect terminal tool calls
case "$TOOL_NAME" in
    *terminal*|*Terminal*|*runInTerminal*) ;;
    *) echo '{}'; exit 0 ;;
esac

# Check for modified/new files in source directories
STATUS=$(git status --porcelain -- "${SRC_DIR}/" tests/ 2>/dev/null || true)
[ -z "$STATUS" ] && echo '{}' && exit 0

# Extract file names (first 10)
FILES=$(echo "$STATUS" | sed 's/^.\{3\}//' | head -10 | tr '\n' ', ' | sed 's/,$//')
COUNT=$(echo "$STATUS" | wc -l | tr -d ' ')

cat <<EOF
{"hookSpecificOutput":{"additionalContext":"DELEGATION VIOLATION DETECTED: ${COUNT} source file(s) have uncommitted changes: ${FILES}. If you modified these via terminal, this violates Cardinal Rule 1. The coordinator must delegate all file modifications to subagents. Consider reverting (git checkout -- <file>) and delegating to the proper workflow."}}
EOF
exit 0
