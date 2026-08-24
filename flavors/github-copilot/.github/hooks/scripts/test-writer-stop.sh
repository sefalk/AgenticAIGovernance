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

# Root resolution AND the shared provenance detector both come from here.
# Without it af_has_provenance_marker exits 127, which `if !` reads as "no
# marker" -- Gate 2 flagged every new test file, marked or not (issue #175).
. "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

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

# The exit code has to be read from pytest itself. `output=$(pytest ...) || true`
# followed by `exit_code=$?` reads the status of `true`, which is 0 on every
# path — so this gate always took the "all tests PASS" branch and blocked every
# legitimate Red phase. Same bug, same fix as scan-secrets.sh (issue #123).
output=$(pytest tests/ -q --tb=line --no-header 2>&1)
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

# Not every red is a red. A file that cannot be imported (exit 2) or a test that
# errors before it runs — missing fixture, fixture raising — never reaches the
# behaviour it claims to guard, and it stays red after a perfect implementation.
# Counting it as a satisfied Red phase sends the Green phase hunting for a defect
# that does not exist (issue #123, finding 2).
#
# Read off the summary line rather than the exit code: a missing fixture reports
# `1 error` and still exits 1, which is indistinguishable from a genuine failure
# by exit code alone. Measured 2026-08-24.
summary_line=$(printf '%s' "$output" | grep -v '^[[:space:]]*$' | tail -1)
if [ "$exit_code" -eq 2 ] || printf '%s' "$summary_line" | grep -qE '[0-9]+ error'; then
    detail=$(printf '%s' "$summary_line" | sed 's/"/\\"/g')
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"Stop\", \"decision\": \"block\", \"reason\": \"Red phase invalid: the suite reported collection or setup ERRORS, not test failures. A test that cannot be collected or set up never reaches the behaviour it claims to guard, and it stays red after a correct implementation. Fix the test construction — imports, syntax, fixtures, schema-less DataFrames — so the red comes from an assertion. Summary: ${detail}\"}}"
    exit 0
fi

# Tests are failing — Red phase satisfied. Now check provenance.

# ---------- Gate 2: Provenance markers on new test files (H5) ----------

missing=""
while IFS= read -r line; do
    # Extract filename from git status (untracked ?? or added A)
    file=$(echo "$line" | sed 's/^.. //' | tr -d '"')
    if [[ "$file" == *.py ]] && [ -f "$file" ]; then
        if ! af_has_provenance_marker "$file" generated; then
            missing="${missing}${file}, "
        fi
    fi
done < <(git status --porcelain "tests/" 2>/dev/null | grep -E '^\?\? |^A ')

if [ -n "$missing" ]; then
    missing="${missing%, }"  # trim trailing comma
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"Stop\", \"decision\": \"block\", \"reason\": \"Provenance violation: these new test files carry no copilot:generated marker anywhere: ${missing}. See instructions/provenance.instructions.md for where to put it.\"}}"
    exit 0
fi

# All gates passed
summary=$(echo "$output" | tail -1)
echo "{\"systemMessage\": \"test-writer:Stop — Red gate PASS: tests are failing as expected. Provenance OK. Summary: ${summary}\"}"
exit 0
