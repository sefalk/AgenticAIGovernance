#!/usr/bin/env bash
# Agent-scoped Stop hook for the implementer agent.
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

output=$(pytest tests/ -q --tb=line --no-header 2>&1) || true
exit_code=$?

if [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 5 ]; then
    echo '{"systemMessage": "implementer:Stop — Green gate PASS: all tests pass"}'
    exit 0
else
    summary=$(echo "$output" | tail -3 | tr '\n' ' ' | sed 's/"/\\"/g')
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"Stop\", \"decision\": \"block\", \"reason\": \"Green phase violation: tests are failing. Fix the failing tests before completing. Summary: ${summary}\"}}"
    exit 0
fi
