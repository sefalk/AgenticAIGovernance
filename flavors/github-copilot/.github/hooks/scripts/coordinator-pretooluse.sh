#!/usr/bin/env bash
# Agent-scoped PreToolUse hook for the coordinator agent.
#
# DELEGATION ENFORCEMENT (HARD -- blocks coordinator from editing/creating files)
#
# The coordinator must delegate all file modifications to subagents.
# Fires only when the coordinator agent is active.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

set -euo pipefail

# Root, config and interpreter come from this script's location, never from
# the cwd the agent happens to run in (issue #54).
. "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

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

# Allow read-only and search tools unconditionally
case "$TOOL_NAME" in
    *read*|*Read*|*search*|*Search*|*find*|*Find*|*list*|*List*|*get*|*Get*|*problems*)
        echo '{}'; exit 0 ;;
esac

# Intercept terminal tool calls -- block pytest, validate git commit message quality
# `case` is case-sensitive: the real tool name is `runInTerminal`, so a
# lowercase-only pattern matched nothing and this whole branch was dead.
case "$TOOL_NAME" in
    *terminal*|*Terminal*)
        COMMAND=$(echo "$RAW" | "$AF_PYTHON" -c "
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
        PROJECT_LANGUAGE=$(af_conf_get PROJECT_LANGUAGE python)
        BOOTSTRAP_MODE=$(af_conf_get PY_ENV_BOOTSTRAP ask)

        # Bootstrap env for non-pytest Python commands when .venv is missing.
        # Match a pytest *invocation*, not the word: the gate used to test the
        # bare substring, so a read-only command that merely names it -- e.g.
        # grepping the config header '[tool.pytest' -- was a hard deny (#183).
        # Quotes are stripped first so a quoted path invocation reads the same.
        IS_PYTEST=false
        CMD_UNQUOTED=$(printf '%s\n' "$COMMAND" | tr -d '\042\047')
        PYTEST_DIRECT='(^|[;&|`(){}])[[:space:]]*(&[[:space:]]*)?([^[:space:];&|]*[/\\])?(pytest|py\.test)(\.exe)?([[:space:];]|$)'
        PYTEST_MODULE='(^|[;&|`(){}])[[:space:]]*(&[[:space:]]*)?([^[:space:];&|]*[/\\])?(python3?|py)(\.exe)?[[:space:]]([^;&|]*[[:space:]])?-m[[:space:]]+pytest([[:space:];]|$)'
        PYTEST_RUNNER='(^|[;&|`(){}])[[:space:]]*(uv|uvx|poetry|pdm|hatch|pipenv|nox|tox|conda)[[:space:]][^;&|]*[[:space:]]pytest([[:space:];]|$)'
        if printf '%s\n' "$CMD_UNQUOTED" | grep -qE "$PYTEST_DIRECT|$PYTEST_MODULE|$PYTEST_RUNNER"; then
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
            WT_DIR=$(af_conf_get WORKTREE_DIR '../wt')
            # `\S+` stops at the first blank, so a quoted path containing spaces
            # was read as several arguments: the collision guard tested a prefix
            # that does not exist and passed everything (issue #200). Split the
            # command into shell-like tokens instead, honouring quotes. This also
            # drops `grep -oP`, which is GNU-only and absent on macOS.
            af_wt_tokens() {
                _s="${1:-}"
                while [ -n "$_s" ]; do
                    case "$_s" in
                        [[:space:]]*) _s="${_s#?}"; continue ;;
                    esac
                    case "$_s" in
                        \"*) _rest="${_s#\"}"
                             case "$_rest" in
                                 *\"*) _tok="${_rest%%\"*}"; _s="${_rest#*\"}" ;;
                                 *)    _tok="$_rest"; _s="" ;;
                             esac ;;
                        \'*) _rest="${_s#\'}"
                             case "$_rest" in
                                 *\'*) _tok="${_rest%%\'*}"; _s="${_rest#*\'}" ;;
                                 *)    _tok="$_rest"; _s="" ;;
                             esac ;;
                        *)   _tok="${_s%%[[:space:]]*}"; _s="${_s#"$_tok"}" ;;
                    esac
                    printf '%s\n' "$_tok"
                done
            }

            BRANCH=""
            WT_PATH=""
            _seen_worktree=0
            _seen_add=0
            _take_branch=0
            _positional=0
            while IFS= read -r _tok; do
                if [ "$_seen_add" -eq 0 ]; then
                    if [ "$_seen_worktree" -eq 1 ] && [ "$_tok" = "add" ]; then
                        _seen_add=1
                    elif [ "$_tok" = "worktree" ]; then
                        _seen_worktree=1
                    else
                        _seen_worktree=0
                    fi
                    continue
                fi
                if [ "$_take_branch" -eq 1 ]; then
                    BRANCH="$_tok"; _take_branch=0; continue
                fi
                case "$_tok" in
                    -b|-B) _take_branch=1 ;;
                    -*)    : ;;
                    *)     _positional=$((_positional + 1))
                           if [ "$_positional" -eq 1 ]; then
                               WT_PATH="$_tok"
                           elif [ "$_positional" -eq 2 ] && [ -z "$BRANCH" ]; then
                               # `git worktree add <path> <commit-ish>` names the
                               # branch positionally. The PowerShell twin has
                               # always checked this form; bash never did, so the
                               # same command was denied on one platform and
                               # allowed on the other (issue #200).
                               BRANCH="$_tok"
                           fi ;;
                esac
            done <<EOF
$(af_wt_tokens "$COMMAND")
EOF
            if [ -n "$BRANCH" ] && ! echo "$BRANCH" | grep -qE '^agent/[a-z0-9][a-z0-9-]*$'; then
                _b=$(af_json_escape "$BRANCH")
                printf '%s\n' "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Worktree branch name '${_b}' is invalid. Must match '^agent/[a-z0-9-]+' (e.g. agent/feat-auth, agent/fix-db-pool). See skills/git-worktrees/SKILL.md.\"}}"
                exit 0
            fi
            if [ -n "$WT_PATH" ] && [ -e "$WT_PATH" ]; then
                _p=$(af_json_escape "$WT_PATH")
                printf '%s\n' "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Worktree path '${_p}' already exists. An existing task may still be running. Run 'git worktree list' to check before creating a new worktree here.\"}}"
                exit 0
            fi
            # Check repo health
            if ! git status --porcelain >/dev/null 2>&1; then
                printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Main repository is not healthy ('\''git status'\'' failed). Fix repository state before creating a worktree."}}'
                exit 0
            fi
        fi

        # Validate git commit message quality -- reject generic phase-only messages
        # Required format: [agent:name] phase: {description >= 10 chars}
        if echo "$COMMAND" | grep -qE 'git[[:space:]]+commit'; then
            # The heredoc *is* python's stdin, so a pipe into it is discarded
            # and the script always saw an empty command. Pass it in the
            # environment instead, which leaves the quoted heredoc intact.
            MSG=$(AF_RAW_COMMAND="$COMMAND" "$AF_PYTHON" << 'PYEOF'
import os, re
cmd = os.environ.get('AF_RAW_COMMAND', '')
m = re.search(r'-m\s+(["\'])(.+?)\1', cmd)
print(m.group(2).strip() if m else '')
PYEOF
)
            if [ -n "$MSG" ]; then
                # A backslash is literal inside an ERE bracket list, so the
                # former '[^\]]' demanded two closing brackets and never
                # matched. A leading ']' after '^' is the portable spelling.
                if ! echo "$MSG" | grep -qE '^\[agent:[^]]+\][[:space:]]+(WIP checkpoint|task cancelled|justify ignore)'; then
                    if ! echo "$MSG" | grep -qE '^\[agent:[^]]+\][[:space:]]+[^:]+:[[:space:]]+.{10,}'; then
                        printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Commit message too generic. Required format: '\''[agent:name] phase: {description >= 10 chars}'\''. E.g.: '\''[agent:test-writer] failing tests: ColumnMeta validation -- null CRC and negative threshold edge cases'\''. See git-workflow.instructions.md Commit Rule 4."}}'
                        exit 0
                    fi
                fi
            fi
        fi
        # Baseline for the PostToolUse check: what was already dirty before this
        # command ran. Without it that hook can only see presence, so it fired on
        # every call while subagents legitimately held uncommitted work (#172).
        SNAP_DIR=$(git rev-parse --absolute-git-dir 2>/dev/null || true)
        if [ -n "$SNAP_DIR" ] && [ -d "$SNAP_DIR" ]; then
            SNAP_SRC=$(af_conf_get SRC_DIR src)
            # Only on success: a failed status would write an empty baseline, and
            # an empty baseline makes every existing change look new.
            if BASELINE=$(git status --porcelain -- "${SNAP_SRC}/" tests/ 2>/dev/null); then
                printf '%s\n' "$BASELINE" > "${SNAP_DIR}/af-delegation.snapshot"
            fi
        fi
        echo '{}'; exit 0 ;;
esac

# Only inspect file-modifying tools
if ! af_is_write_tool "$TOOL_NAME"; then
    echo '{}'
    exit 0
fi

# Block: coordinator must not edit or create files directly
cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Coordinator delegation violation: The coordinator must not modify files directly. Select the appropriate workflow and delegate to the correct subagent: test-writer (Red phase, test files), implementer (Green phase, production code), refactorer (Refactor phase, structural cleanup), documenter (logs and docs), planner (plan files). Review your Cardinal Rules and Workflow Selection."}}
EOF
exit 0
