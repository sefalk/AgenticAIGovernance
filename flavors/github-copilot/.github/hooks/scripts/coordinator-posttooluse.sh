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

# Root, config and interpreter come from this script's location, never from
# the cwd the agent happens to run in (issue #54).
. "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

SRC_DIR=$(af_conf_get SRC_DIR src)

RAW=$(cat)
# `A && B && exit` returns 1 when A is false, which under `set -e` aborts the
# hook instead of falling through. Explicit `if` blocks do not.
if [ -z "$RAW" ]; then echo '{}'; exit 0; fi
if [ -z "$AF_PYTHON" ]; then echo '{}'; exit 0; fi

TOOL_NAME=$(echo "$RAW" | "$AF_PYTHON" -c "
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
