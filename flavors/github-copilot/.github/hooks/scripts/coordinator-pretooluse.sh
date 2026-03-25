#!/usr/bin/env bash
# copilot:generated | implementer | 2026-03-16
# copilot:modified  | implementer | 2026-03-17 | fixed false-positive deny on read-only tools
# Agent-scoped PreToolUse hook for the coordinator agent.
#
# DELEGATION ENFORCEMENT (HARD -- blocks coordinator from editing/creating files)
#
# The coordinator must delegate all file modifications to subagents.
# Fires only when the coordinator agent is active.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

set -euo pipefail

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

# Allow read-only and search tools unconditionally
case "$TOOL_NAME" in
    *read*|*Read*|*search*|*Search*|*find*|*Find*|*list*|*List*|*get*|*Get*|*problems*)
        echo '{}'; exit 0 ;;
esac

# Only inspect file-modifying tools
case "$TOOL_NAME" in
    *edit*|*create*|*write*|*file*|*Edit*|*Create*|*Write*|*File*)
        # Allow createTerminal (not a file operation)
        case "$TOOL_NAME" in
            *terminal*|*Terminal*) echo '{}'; exit 0 ;;
        esac
        ;;
    *) echo '{}'; exit 0 ;;
esac

# Block: coordinator must not edit or create files directly
cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Coordinator delegation violation: The coordinator must not modify files directly. Select the appropriate workflow and delegate to the correct subagent: test-writer (Red phase, test files), implementer (Green phase, production code), refactorer (Refactor phase, structural cleanup), documenter (logs and docs), planner (plan files). Review your Cardinal Rules and Workflow Selection."}}
EOF
exit 0
