#!/usr/bin/env bash
# Agent-scoped Stop hook for the refactorer agent.
#
# REFACTOR PHASE GATES (HARD — blocks refactorer if tests fail or new files created)
#
# Gate 1: All tests must still pass after refactoring.
# Gate 2: No new files created — refactoring modifies existing files only.
#         Scoped to .py files under mpusage/ and tests/ to avoid false positives.
#
# Fires as SubagentStop when the refactorer is invoked by the coordinator.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

set -uo pipefail

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

output=$(pytest tests/ -q --tb=line --no-header 2>&1) || true
exit_code=$?

if [ "$exit_code" -ne 0 ] && [ "$exit_code" -ne 5 ]; then
    summary=$(echo "$output" | tail -3 | tr '\n' ' ' | sed 's/"/\\"/g')
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"Stop\", \"decision\": \"block\", \"reason\": \"Refactor phase violation: tests are failing after refactoring. All tests must remain green. Summary: ${summary}\"}}"
    exit 0
fi

# ---------- Gate 2: No new .py files under mpusage/ or tests/ ----------

new_files=""
while IFS= read -r line; do
    file=$(echo "$line" | sed 's/^.. //' | tr -d '"')
    if [[ "$file" == *.py ]]; then
        new_files="${new_files}${file}, "
    fi
done < <(git status --porcelain "mpusage/" "tests/" 2>/dev/null | grep -E '^\?\? ')

if [ -n "$new_files" ]; then
    new_files="${new_files%, }"
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"Stop\", \"decision\": \"block\", \"reason\": \"Refactor phase violation: new files were created. Refactoring must only modify existing files. New files: ${new_files}\"}}"
    exit 0
fi

# All gates passed
echo '{"systemMessage": "refactorer:Stop — all gates PASS: tests green, no new files created"}'
exit 0
