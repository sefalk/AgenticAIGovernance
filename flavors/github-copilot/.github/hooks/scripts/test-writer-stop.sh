#!/usr/bin/env bash
# Agent-scoped Stop hook for the test-writer agent.
#
# RED PHASE GATE (HARD — blocks test-writer if new tests do NOT fail)
#
# The Red phase requires that all newly written tests FAIL against the
# existing production code. If tests pass, the test-writer has not
# expressed a genuine requirement gap.
#
# Also checks provenance markers on newly created test files (H5).
#
# Fires as SubagentStop when the test-writer is invoked by the coordinator.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

set -uo pipefail

# Read stdin (hook input JSON — required by protocol)
cat > /dev/null

if ! command -v pytest &>/dev/null; then
    echo '{"systemMessage": "test-writer:Stop — pytest not found, Red gate skipped"}'
    exit 0
fi

if [ ! -d "tests/" ]; then
    echo '{"systemMessage": "test-writer:Stop — no tests/ directory, Red gate skipped"}'
    exit 0
fi

# ---------- Gate 1: Red phase — new tests must FAIL ----------

output=$(pytest tests/ -q --tb=line --no-header 2>&1) || true
exit_code=$?

# Exit code 0 = all tests pass → Red phase violation
if [ "$exit_code" -eq 0 ]; then
    echo '{"hookSpecificOutput": {"hookEventName": "Stop", "decision": "block", "reason": "Red phase violation: all tests PASS. New tests must FAIL against the existing production code to express a genuine requirement gap. Ensure your tests assert behaviour that is not yet implemented."}}'
    exit 0
fi

# Exit code 5 = no tests collected → skip
if [ "$exit_code" -eq 5 ]; then
    echo '{"systemMessage": "test-writer:Stop — no tests collected, Red gate skipped"}'
    exit 0
fi

# Tests are failing — Red phase satisfied. Now check provenance.

# ---------- Gate 2: Provenance markers on new test files (H5) ----------

missing=""
while IFS= read -r line; do
    # Extract filename from git status (untracked ?? or added A)
    file=$(echo "$line" | sed 's/^.. //' | tr -d '"')
    if [[ "$file" == *.py ]] && [ -f "$file" ]; then
        if ! head -5 "$file" | grep -q 'copilot:generated'; then
            missing="${missing}${file}, "
        fi
    fi
done < <(git status --porcelain "tests/" 2>/dev/null | grep -E '^\?\? |^A ')

if [ -n "$missing" ]; then
    missing="${missing%, }"  # trim trailing comma
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"Stop\", \"decision\": \"block\", \"reason\": \"Provenance violation: new test files missing copilot:generated marker: ${missing}\"}}"
    exit 0
fi

# All gates passed
summary=$(echo "$output" | tail -1)
echo "{\"systemMessage\": \"test-writer:Stop — Red gate PASS: tests are failing as expected. Provenance OK. Summary: ${summary}\"}"
exit 0
