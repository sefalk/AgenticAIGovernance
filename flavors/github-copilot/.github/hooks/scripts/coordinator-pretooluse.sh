#!/usr/bin/env bash
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
        # Config: PROJECT_LANGUAGE and PY_ENV_BOOTSTRAP from af-env.conf
        PROJECT_LANGUAGE=$(grep '^PROJECT_LANGUAGE=' .github/af-env.conf 2>/dev/null | cut -d= -f2 | xargs)
        BOOTSTRAP_MODE=$(grep '^PY_ENV_BOOTSTRAP=' .github/af-env.conf 2>/dev/null | cut -d= -f2 | xargs)
        : "${PROJECT_LANGUAGE:=python}"
        : "${BOOTSTRAP_MODE:=ask}"

        # Bootstrap env for non-pytest Python commands when .venv is missing
        IS_PYTEST=false
        if echo "$COMMAND" | grep -qE '\bpytest\b|\bpy\.test\b'; then
            IS_PYTEST=true
        fi

        IS_PY_CMD=false
        if echo "$COMMAND" | grep -qE '(\.github/scripts/(run-tests|run-deps|run-metrics)\.sh)|(\.venv/bin/python)|(^|[[:space:]])(python|python3|pip|ruff|mypy)([[:space:]]|$)'; then
            IS_PY_CMD=true
        fi

        if [[ "$PROJECT_LANGUAGE" == "python" ]] && [[ "$IS_PYTEST" == "false" ]] && [[ "$IS_PY_CMD" == "true" ]] && [[ ! -x ".venv/bin/python" ]]; then
            if [[ "$BOOTSTRAP_MODE" == "always" ]]; then
                if [[ ! -f ".github/scripts/bootstrap-python-env.sh" ]]; then
                    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Python environment missing and bootstrap script not found at .github/scripts/bootstrap-python-env.sh."}}'
                    exit 0
                fi
                bash .github/scripts/bootstrap-python-env.sh >/dev/null 2>&1 || {
                    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Python environment bootstrap failed. Run .github/scripts/bootstrap-python-env.sh manually and retry."}}'
                    exit 0
                }
            elif [[ "$BOOTSTRAP_MODE" == "ask" ]]; then
                printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Python environment (.venv) is missing. Allow running .github/scripts/bootstrap-python-env.sh now to prepare venv + dependencies?"}}'
                exit 0
            fi
        fi

        # Block pytest via terminal -- use runTests tool instead
        if [[ "$IS_PYTEST" == "true" ]]; then
            printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Do not run tests via terminal. Use the execute/runTests tool (structured output, VS Code test integration) or the predefined task '\''tests: domain'\'' / '\''tests: all'\'' via execute/runTask."}}'
            exit 0
        fi

        # Validate git worktree add preconditions
        if echo "$COMMAND" | grep -qE 'git[[:space:]]+worktree[[:space:]]+add'; then
            WT_DIR=$(grep '^WORKTREE_DIR=' .github/af-env.conf 2>/dev/null | cut -d= -f2 | xargs)
            : "${WT_DIR:=../wt}"
            # Extract branch name after -b flag
            BRANCH=$(echo "$COMMAND" | grep -oP '(?<=-b )\S+' || true)
            if [ -n "$BRANCH" ] && ! echo "$BRANCH" | grep -qE '^agent/[a-z0-9][a-z0-9-]*$'; then
                printf '%s\n' "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Worktree branch name '${BRANCH}' is invalid. Must match '^agent/[a-z0-9-]+' (e.g. agent/feat-auth, agent/fix-db-pool). See git-workflow.instructions.md Worktree Lifecycle.\"}}"
                exit 0
            fi
            # Extract worktree path (first arg after 'add')
            WT_PATH=$(echo "$COMMAND" | grep -oP '(?<=worktree add )\S+' || true)
            if [ -n "$WT_PATH" ] && [ -e "$WT_PATH" ]; then
                printf '%s\n' "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Worktree path '${WT_PATH}' already exists. An existing task may still be running. Run 'git worktree list' to check before creating a new worktree here.\"}}"
                exit 0
            fi
            # Check repo health
            if ! git status --porcelain >/dev/null 2>&1; then
                printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Main repository is not healthy (\'git status\' failed). Fix repository state before creating a worktree."}}'
                exit 0
            fi
        fi        # Validate git commit message quality -- reject generic phase-only messages
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
