#!/usr/bin/env bash
# Agent-scoped Stop hook for the refactorer agent.
# copilot:modified  | implementer | 2026-03-19 | test log freshness check in stop hooks
#
# REFACTOR PHASE GATES (HARD — blocks refactorer if tests fail or new files created)
#
# Gate 1: All tests must still pass after refactoring.
# Gate 2: No new files created — refactoring modifies existing files only.
#         Scoped to .py files under SRC_DIR/ and tests/ to avoid false positives.
#
# Fires as SubagentStop when the refactorer is invoked by the coordinator.
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

# ---------- Gate 1: All tests must pass ----------

if ! command -v pytest &>/dev/null; then
    echo '{"systemMessage": "refactorer:Stop — pytest not found, test gate skipped"}'
    exit 0
fi

if [ ! -d "tests/" ]; then
    echo '{"systemMessage": "refactorer:Stop — no tests/ directory, test gate skipped"}'
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

if [ "$exit_code" -ne 0 ] && [ "$exit_code" -ne 5 ]; then
    summary=$(echo "$output" | grep -v '^===' | tail -3 | tr '\n' ' ' | sed 's/"/\\"/g')
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"Stop\", \"decision\": \"block\", \"reason\": \"Refactor phase violation: tests are failing after refactoring. All tests must remain green. Summary: ${summary}\"}}"
    exit 0
fi

# ---------- Gate 2: No new .py files under SRC_DIR/ or tests/ ----------

new_files=""
while IFS= read -r line; do
    file=$(echo "$line" | sed 's/^.. //' | tr -d '"')
    if [[ "$file" == *.py ]]; then
        new_files="${new_files}${file}, "
    fi
done < <(git status --porcelain "${SRC_DIR}/" "tests/" 2>/dev/null | grep -E '^\?\? ')

if [ -n "$new_files" ]; then
    new_files="${new_files%, }"
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"Stop\", \"decision\": \"block\", \"reason\": \"Refactor phase violation: new files were created. Refactoring must only modify existing files. New files: ${new_files}\"}}"
    exit 0
fi

# ---------- Gate 3: Python quality on changed source files ----------

changed_src_py=$(git diff --name-only --cached --diff-filter=AM -- "${SRC_DIR}/" 2>/dev/null | grep -E '\.py$' || true)
if [ -z "$changed_src_py" ]; then
    changed_src_py=$(git diff --name-only HEAD --diff-filter=AM -- "${SRC_DIR}/" 2>/dev/null | grep -E '\.py$' || true)
fi

if [ -n "$changed_src_py" ]; then
    quality_script=".github/scripts/check-python-quality.py"
    if [ ! -f "$quality_script" ]; then
        echo '{"hookSpecificOutput": {"hookEventName": "Stop", "decision": "block", "reason": "Refactor phase violation: python quality script missing (.github/scripts/check-python-quality.py)."}}'
        exit 0
    fi

    python_exe=""
    if [ -x ".venv/Scripts/python.exe" ]; then
        python_exe=".venv/Scripts/python.exe"
    elif command -v python &>/dev/null; then
        python_exe="python"
    fi

    if [ -z "$python_exe" ]; then
        echo '{"hookSpecificOutput": {"hookEventName": "Stop", "decision": "block", "reason": "Refactor phase violation: no Python executable found to run quality gate checks."}}'
        exit 0
    fi

    quality_output=$(echo "$changed_src_py" | xargs "$python_exe" "$quality_script" --files 2>&1)
    quality_exit=$?
    if [ "$quality_exit" -ne 0 ]; then
        summary=$(echo "$quality_output" | head -10 | tr '\n' ' ' | sed 's/"/\\"/g')
        echo "{\"hookSpecificOutput\": {\"hookEventName\": \"Stop\", \"decision\": \"block\", \"reason\": \"Refactor phase violation: python quality gate failed (type hints/docstrings/ignore hygiene). Summary: ${summary}\"}}"
        exit 0
    fi
fi

# Gate 4: Atomic ignore commit check
diff_output=$(git diff --cached -- '*.py' 2>/dev/null)
[ -z "$diff_output" ] && diff_output=$(git diff HEAD -- '*.py' 2>/dev/null)
new_ignores=$(echo "$diff_output" | grep -cE '^\+[^+].*#[[:space:]]*(type:[[:space:]]*ignore|pyright:[[:space:]]*ignore|noqa)' || true)
other_additions=$(echo "$diff_output" | grep -E '^\+[^+]' | grep -cvE '#[[:space:]]*(type:[[:space:]]*ignore|pyright:[[:space:]]*ignore|noqa)' | grep -cE '[^[:space:]]' || true)
if [ "$new_ignores" -gt 1 ]; then
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"Stop\", \"decision\": \"block\", \"reason\": \"Refactor phase violation: ${new_ignores} new ignore statements in one commit. Each must be its own standalone atomic commit. Format: [agent:name] justify ignore: file:line RULE -- reason\"}}"
    exit 0
fi
if [ "$new_ignores" -eq 1 ] && [ "$other_additions" -gt 0 ]; then
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"Stop\", \"decision\": \"block\", \"reason\": \"Refactor phase violation: new ignore statement mixed with ${other_additions} other code changes. Commit code changes first, then add the ignore in its own standalone commit. Format: [agent:name] justify ignore: file:line RULE -- reason\"}}"
    exit 0
fi

# ---------- Gate 5: Python linting on changed source files ----------
lint_status="no src changes"
if [ -n "$changed_src_py" ]; then
    lint_status="skipped (script/python not available)"
    lint_script=".github/scripts/check-python-linting.py"
    if [ -f "$lint_script" ] && [ -n "$python_exe" ]; then
        lint_output=$(echo "$changed_src_py" | xargs "$python_exe" "$lint_script" --files 2>&1)
        lint_exit=$?
        if [ "$lint_exit" -eq 2 ]; then
            lint_summary=$(echo "$lint_output" | head -15 | tr '\n' ' ' | sed 's/"/\\"/g')
            echo "{\"hookSpecificOutput\": {\"hookEventName\": \"Stop\", \"decision\": \"block\", \"reason\": \"Refactor phase violation: linting gate failed. Fix with: ruff check --fix <files>. Violations: ${lint_summary}\"}}"
            exit 0
        elif [ "$lint_exit" -eq 1 ]; then
            echo '{"hookSpecificOutput": {"hookEventName": "Stop", "decision": "block", "reason": "Refactor phase blocked: linting gate unavailable because ruff is not installed. Install dev dependencies or run: pip install ruff"}}'
            exit 0
        else
            lint_status="clean"
        fi
    fi
fi

# All gates passed
if [[ "$from_log" == true ]]; then
    pass_detail="tests accepted from log"
else
    pass_detail="tests green"
fi
echo "{\"systemMessage\": \"refactorer:Stop \u2014 all gates PASS: ${pass_detail}, no new files created, python quality verified, linting: ${lint_status}\"}"
exit 0
