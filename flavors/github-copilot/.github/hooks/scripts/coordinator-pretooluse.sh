#!/usr/bin/env bash
# copilot:generated | implementer | 2026-03-16
# copilot:modified  | implementer | 2026-03-17 | fixed false-positive deny on read-only tools
# copilot:modified  | implementer | 2026-04-14 | add terminal interception: pytest block + commit message quality gate
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

# Intercept terminal tool calls -- block pytest, validate git commit message quality
case "$TOOL_NAME" in
    *terminal*)
        COMMAND=$(echo "$RAW" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', {})
    if isinstance(ti, str): ti = json.loads(ti)
    print(ti.get('command', ''))
except Exception:
    print('')
" 2>/dev/null)
        # Block pytest via terminal -- use runTests tool instead
        if echo "$COMMAND" | grep -qE '\bpytest\b|\bpy\.test\b'; then
            printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Do not run tests via terminal. Use the execute/runTests tool (structured output, VS Code test integration) or the predefined task '\''tests: domain'\'' / '\''tests: all'\'' via execute/runTask."}}'
            exit 0
        fi
        # Validate git commit message quality -- reject generic phase-only messages
        # Required format: [agent:name] phase: {description >= 10 chars}
        if echo "$COMMAND" | grep -qE 'git[[:space:]]+commit'; then
            MSG=$(echo "$COMMAND" | python3 << 'PYEOF'
import sys, re
cmd = sys.stdin.read()
m = re.search(r'-m\s+["\']([^"\']+)["\']', cmd)
print(m.group(1).strip() if m else '')
PYEOF
)
            if [ -n "$MSG" ]; then
                if ! echo "$MSG" | grep -qE '^\[agent:[^\]]+\][[:space:]]+(WIP checkpoint|task cancelled|justify ignore)'; then
                    if ! echo "$MSG" | grep -qE '^\[agent:[^\]]+\][[:space:]]+[^:]+:[[:space:]]+.{10,}'; then
                        printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Commit message too generic. Required format: '\''[agent:name] phase: {description >= 10 chars}'\''. E.g.: '\''[agent:test-writer] failing tests: ColumnMeta validation -- null CRC and negative threshold edge cases'\''. See git-workflow.instructions.md Commit Rule 4."}}'
                        exit 0
                    fi
                fi
            fi
        fi
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
