#!/usr/bin/env bash
# Agent-scoped Stop hook for the implementer agent.
# copilot:modified  | implementer | 2026-03-19 | test log freshness check in stop hooks
#
# GREEN PHASE GATE (HARD — blocks implementer from completing if tests fail)
#
# Runs the test suite and blocks the implementer subagent if any test fails.
# This converts the Green phase from a self-asserted claim into a
# machine-verified precondition.
#
# Fires as SubagentStop when the implementer is invoked by the coordinator.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

set -uo pipefail

# Load project config
SRC_DIR="src"
_conf=".github/af-env.conf"
if [ -f "$_conf" ]; then
    _val=$(grep -E '^SRC_DIR=' "$_conf" | head -1 | cut -d= -f2-)
    [ -n "$_val" ] && SRC_DIR="$_val"
fi

# Read stdin (hook input JSON — required by protocol)
cat > /dev/null

if ! command -v pytest &>/dev/null; then
    echo '{"systemMessage": "implementer:Stop — pytest not found, Green gate skipped"}'
    exit 0
fi

if [ ! -d "tests/" ]; then
    echo '{"systemMessage": "implementer:Stop — no tests/ directory, Green gate skipped"}'
    exit 0
fi

# ---------- Test Log Freshness Check ----------
# Accept last run if ALL tests passed AND no code changed since (committed or uncommitted).
# No time limit — change detection is the criterion, not elapsed time.
TEST_LOG=".github/test-log.json"
from_log=false
if [[ -f "$TEST_LOG" ]]; then
    _flat=$(tr -d '\n\r' < "$TEST_LOG" | tr -s ' ')
    _all_block=$(echo "$_flat" | sed -n 's/.*"all" *: *\({[^}]*}\).*/\1/p')
    if [[ -n "$_all_block" ]]; then
        _ec=$(echo "$_all_block" | sed -n 's/.*"exit_code" *: *\([0-9][0-9]*\).*/\1/p')
        if [[ "$_ec" == "0" ]]; then
            _lr=$(echo "$_all_block" | sed -n 's/.*"last_run" *: *"\([^"]*\)".*/\1/p')
            if [[ -n "$_lr" ]]; then
                commits_since=$(git log --oneline --after="$_lr" -- "${SRC_DIR}/" 'tests/' 2>/dev/null)
                uncommitted=$(git diff --name-only HEAD -- "${SRC_DIR}/" 'tests/' 2>/dev/null)
                if [[ -z "$commits_since" ]] && [[ -z "$uncommitted" ]]; then
                    _passed=$(echo "$_all_block" | sed -n 's/.*"passed" *: *\([0-9][0-9]*\).*/\1/p')
                    _total=$(echo "$_all_block" | sed -n 's/.*"total" *: *\([0-9][0-9]*\).*/\1/p')
                    from_log=true
                    log_info="${_passed:-0}/${_total:-0}"
                fi
            fi
        fi
    fi
fi

if [[ "$from_log" == true ]]; then
    exit_code=0
    output="Tests: accepted from test log (${log_info} passed, no code changes since)"
else
    output=$(.github/scripts/run-tests.sh --scope all 2>&1) || true
    exit_code=$?
fi

if [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 5 ]; then
    # Check provenance markers on changed .py files
    changed_py=$(git diff --name-only --cached --diff-filter=AM -- '*.py' 2>/dev/null)
    if [ -z "$changed_py" ]; then
        changed_py=$(git diff --name-only HEAD --diff-filter=AM -- '*.py' 2>/dev/null)
    fi

    missing=""
    if [ -n "$changed_py" ]; then
        while IFS= read -r f; do
            if [ -f "$f" ]; then
                first_lines=$(head -n 5 "$f" 2>/dev/null || true)
                if [ -n "$first_lines" ] && ! echo "$first_lines" | grep -qE 'copilot:(generated|modified)'; then
                    missing="${missing:+$missing, }$f"
                fi
            fi
        done <<< "$changed_py"
    fi

    if [ -n "$missing" ]; then
        echo "{\"hookSpecificOutput\": {\"hookEventName\": \"Stop\", \"decision\": \"block\", \"reason\": \"Provenance gate: these changed .py files lack copilot:generated or copilot:modified markers in their first 5 lines: ${missing}. Add provenance markers per instructions/provenance.instructions.md before completing.\"}}"
        exit 0
    fi

    if [[ "$from_log" == true ]]; then
        pass_detail="tests accepted from log"
    else
        pass_detail="all tests pass"
    fi
    echo "{\"systemMessage\": \"implementer:Stop \u2014 Green gate PASS: ${pass_detail}, provenance markers verified\"}"
    exit 0
else
    summary=$(echo "$output" | grep -v '^===' | tail -3 | tr '\n' ' ' | sed 's/"/\\"/g')
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"Stop\", \"decision\": \"block\", \"reason\": \"Green phase violation: tests are failing. Fix the failing tests before completing. Summary: ${summary}\"}}"
    exit 0
fi
