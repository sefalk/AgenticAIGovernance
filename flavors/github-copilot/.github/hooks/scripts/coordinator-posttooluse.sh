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

if [ -z "$TOOL_NAME" ]; then echo '{}'; exit 0; fi

# Only inspect terminal tool calls
case "$TOOL_NAME" in
    *terminal*|*Terminal*|*runInTerminal*) ;;
    *) echo '{}'; exit 0 ;;
esac

# Attribution, not presence. PreToolUse leaves a baseline of what was already
# dirty, so only what appeared since is attributable to this call (#172).
# No baseline means no evidence -- and a guard that accuses without evidence is
# the defect this replaced, so it stays silent instead.
GIT_DIR_ABS=$(git rev-parse --absolute-git-dir 2>/dev/null || true)
if [ -z "$GIT_DIR_ABS" ] || [ ! -d "$GIT_DIR_ABS" ]; then echo '{}'; exit 0; fi
SNAPSHOT="${GIT_DIR_ABS}/af-delegation.snapshot"
if [ ! -f "$SNAPSHOT" ]; then echo '{}'; exit 0; fi

# Check for modified/new files in source directories
STATUS=$(git status --porcelain -- "${SRC_DIR}/" tests/ 2>/dev/null || true)
if [ -z "$STATUS" ]; then rm -f "$SNAPSHOT"; echo '{}'; exit 0; fi

# Keep only entries the baseline did not already contain. Comparing the whole
# porcelain line, not just the path, so a staged/unstaged transition still counts.
DELTA=$(printf '%s\n' "$STATUS" | grep -Fxv -f "$SNAPSHOT" || true)
rm -f "$SNAPSHOT"
if [ -z "$DELTA" ]; then echo '{}'; exit 0; fi

# Extract file names (first 10)
FILES=$(printf '%s\n' "$DELTA" | sed 's/^.\{3\}//' | head -10 | tr '\n' ',' | sed 's/,$//')
COUNT=$(printf '%s\n' "$DELTA" | wc -l | tr -d ' ')

cat <<EOF
{"hookSpecificOutput":{"additionalContext":"DELEGATION VIOLATION DETECTED: ${COUNT} source file(s) changed while this terminal call ran: ${FILES}. Cardinal Rule 1 requires the coordinator to delegate file modifications to subagents. Delegate the change and let the subagent redo it. Do not discard uncommitted work to clear this warning."}}
EOF
exit 0
