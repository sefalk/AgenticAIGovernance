#!/usr/bin/env bash
# Agent-scoped Stop hook for the refactorer agent.
#
# REFACTOR PHASE GATES (HARD — blocks refactorer if tests fail or new files created)
#
# Gate 1: All tests must still pass after refactoring.
# Gate 2: No new files created — refactoring modifies existing files only.
#         Scoped to .py files under SRC_DIR/ and tests/ to avoid false positives.
# Gate 2b: Provenance markers on files this pass actually authored.
# Gate 3: Python quality (type hints, docstrings) on changed SRC_DIR/ files.
# Gate 4: Each new type:ignore / pyright:ignore / noqa is its own commit.
# Gate 5: ruff linting on changed files under SRC_DIR/ AND tests/.
#
# Fires as SubagentStop when the refactorer is invoked by the coordinator.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

set -uo pipefail

# Root, config and interpreter come from this script's location, never from
# the cwd the agent happens to run in (issue #54).
. "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

SRC_DIR=$(af_conf_get SRC_DIR src)
BASE_BRANCH=$(af_conf_get BASE_BRANCH '')

# Read stdin (hook input JSON — required by protocol)
cat > /dev/null

# ---------- Gate 1: All tests must pass ----------
# A missing test runner disables THIS gate only. Gates 2-5 need neither pytest
# nor a tests/ directory, and exiting here used to take them down too (#12).
test_gate_skipped=""
if ! command -v pytest &>/dev/null; then
    test_gate_skipped="pytest not found"
elif [ ! -d "tests/" ]; then
    test_gate_skipped="no tests/ directory"
fi

# ---------- Test Log Freshness Check ----------
# Accept last run if ALL tests passed AND no code changed since (committed or uncommitted).
# No time limit — change detection is the criterion, not elapsed time.
TEST_LOG=".github/test-log.json"
from_log=false
if [[ -z "$test_gate_skipped" ]] && [[ -f "$TEST_LOG" ]]; then
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

if [[ -n "$test_gate_skipped" ]]; then
    exit_code=0
    output="Tests: gate skipped (${test_gate_skipped})"
elif [[ "$from_log" == true ]]; then
    exit_code=0
    output="Tests: accepted from test log (${log_info} passed, no code changes since)"
else
    # `output=$(...) || true` followed by `exit_code=$?` reads the status of
    # `true`, which is 0 on every path -- so the Refactor gate never fired and a
    # refactor could break the suite unchallenged (issue #123). Same bug, same
    # fix as scan-secrets.sh.
    output=$(.github/scripts/run-tests.sh --scope all 2>&1)
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

# ---------- Changed-file sets for Gates 3 and 5 ----------
# Two distinct scopes on purpose:
#   changed_src_py  -- production source only. Gate 3 enforces type hints and
#                      NumPy docstrings, which do not apply to test functions.
#   changed_lint_py -- source AND tests. Lint violations in tests/ are real
#                      violations; scoping Gate 5 to SRC_DIR/ let them through.

changed_src_py=$(git diff --name-only --cached --diff-filter=AM -- "${SRC_DIR}/" 2>/dev/null | grep -E '\.py$' || true)
if [ -z "$changed_src_py" ]; then
    changed_src_py=$(git diff --name-only HEAD --diff-filter=AM -- "${SRC_DIR}/" 2>/dev/null | grep -E '\.py$' || true)
fi

changed_lint_py=$(git diff --name-only --cached --diff-filter=AM -- "${SRC_DIR}/" 'tests/' 2>/dev/null | grep -E '\.py$' || true)
if [ -z "$changed_lint_py" ]; then
    changed_lint_py=$(git diff --name-only HEAD --diff-filter=AM -- "${SRC_DIR}/" 'tests/' 2>/dev/null | grep -E '\.py$' || true)
fi

# Files committed in an EARLIER phase of this workflow appear in neither diff
# above -- the coordinator commits the test files at the end of the Red phase,
# so they were invisible here and shipped unlinted (issue #13). The unit of
# accountability is the branch delta: what the merge will add.
inherited_lint_py=""
merge_base=""
if [ -n "$BASE_BRANCH" ]; then
    merge_base=$(git merge-base HEAD "$BASE_BRANCH" 2>/dev/null | head -1)
    [ -z "$merge_base" ] && merge_base=$(git merge-base HEAD "origin/$BASE_BRANCH" 2>/dev/null | head -1)
fi
if [ -n "$merge_base" ]; then
    branch_delta=$(git diff --name-only --diff-filter=AM "${merge_base}..HEAD" -- "${SRC_DIR}/" 'tests/' 2>/dev/null | grep -E '\.py$' || true)
    if [ -n "$branch_delta" ]; then
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            [ -f "$f" ] || continue
            if echo "$changed_lint_py" | grep -qxF "$f"; then continue; fi
            inherited_lint_py+="$f"$'\n'
        done <<< "$branch_delta"
    fi
fi

# Resolve Python once -- Gate 3 and Gate 5 both need it. Gate 5 must still run
# when only tests/ changed, so this cannot live inside the Gate 3 branch.
python_exe=""
if [ -x ".venv/bin/python" ]; then
    python_exe=".venv/bin/python"
elif [ -x ".venv/Scripts/python.exe" ]; then
    python_exe=".venv/Scripts/python.exe"
else
    python_exe="$AF_PYTHON"
fi

# The quality gate reports per changed function, not per changed file (issue
# #45). It reuses the base resolved above rather than deriving its own, so the
# framework keeps one base-branch resolver.
diff_base_args=""
[ -n "$merge_base" ] && diff_base_args="--diff-base $merge_base"

# ---------- Gate 2b: Provenance markers on authored files ----------
# refactorer.agent.md carries a HARD provenance gate whose only stated
# verification was the refactorer's own scan -- so a pass could report
# "Marked as copilot:modified in both files" with no marker in either
# (issue #175). A self-scan is the claim restated, not a check.
# The authorship filter is mirrored from implementer-stop and matters more
# here: this is the agent that runs `ruff format`, and a marker may only be
# demanded of files it actually wrote in (issue #86).
authored_py="$changed_lint_py"
authorship_script=".github/scripts/check-python-quality.py"
if [ -n "$changed_lint_py" ] && [ -n "$merge_base" ] && [ -n "$python_exe" ] && [ -f "$authorship_script" ]; then
    if authored_out=$(echo "$changed_lint_py" | xargs "$python_exe" "$authorship_script" $diff_base_args --list-authored --files 2>/dev/null); then
        authored_py="$authored_out"
    fi
fi

missing=""
if [ -n "$authored_py" ]; then
    while IFS= read -r f; do
        if [ -f "$f" ]; then
            if ! af_has_provenance_marker "$f"; then
                missing="${missing:+$missing, }$f"
            fi
        fi
    done <<< "$authored_py"
fi

if [ -n "$missing" ]; then
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"Stop\", \"decision\": \"block\", \"reason\": \"Provenance gate: these refactored .py files carry no copilot:generated or copilot:modified marker anywhere: ${missing}. Add a marker in the position instructions/provenance.instructions.md prescribes before completing.\"}}"
    exit 0
fi

# ---------- Gate 3: Python quality on changed source files ----------

if [ -n "$changed_src_py" ]; then
    quality_script=".github/scripts/check-python-quality.py"
    if [ ! -f "$quality_script" ]; then
        echo '{"hookSpecificOutput": {"hookEventName": "Stop", "decision": "block", "reason": "Refactor phase violation: python quality script missing (.github/scripts/check-python-quality.py)."}}'
        exit 0
    fi

    if [ -z "$python_exe" ]; then
        echo '{"hookSpecificOutput": {"hookEventName": "Stop", "decision": "block", "reason": "Refactor phase violation: no Python executable found to run quality gate checks."}}'
        exit 0
    fi

    quality_output=$(echo "$changed_src_py" | xargs "$python_exe" "$quality_script" $diff_base_args --files 2>&1)
    quality_exit=$?
    if [ "$quality_exit" -ne 0 ]; then
        summary=$(echo "$quality_output" | head -10 | tr '\n' ' ' | sed 's/"/\\"/g')
        echo "{\"hookSpecificOutput\": {\"hookEventName\": \"Stop\", \"decision\": \"block\", \"reason\": \"Refactor phase violation: python quality gate failed (type hints/docstrings/ignore hygiene). Summary: ${summary}\"}}"
        exit 0
    fi
fi

# ---------- Gate 3b: Ignore hygiene on the rest of the lint set ----------
# #13 makes `# noqa: RULE  # reason` the sanctioned way to acknowledge an
# inherited violation, and those live in tests/ -- where Gate 3 never looked.
# Hygiene applies everywhere a suppression can ship; type hints and docstrings
# stay source-only.
hygiene_py=""
while IFS= read -r f; do
    [ -z "$f" ] && continue
    if echo "$changed_src_py" | grep -qxF "$f"; then continue; fi
    if echo "$hygiene_py" | grep -qxF "$f"; then continue; fi
    hygiene_py+="$f"$'\n'
done <<< "${changed_lint_py}"$'\n'"${inherited_lint_py}"

if [ -n "$hygiene_py" ]; then
    quality_script=".github/scripts/check-python-quality.py"
    if [ ! -f "$quality_script" ] || [ -z "$python_exe" ]; then
        echo '{"hookSpecificOutput": {"hookEventName": "Stop", "decision": "block", "reason": "Ignore hygiene gate unavailable: check-python-quality.py or a Python executable is missing."}}'
        exit 0
    fi
    hygiene_output=$(echo "$hygiene_py" | xargs "$python_exe" "$quality_script" $diff_base_args --checks ignore-hygiene --files 2>&1)
    hygiene_exit=$?
    if [ "$hygiene_exit" -ne 0 ]; then
        summary=$(echo "$hygiene_output" | head -10 | tr '\n' ' ' | sed 's/"/\\"/g')
        echo "{\"hookSpecificOutput\": {\"hookEventName\": \"Stop\", \"decision\": \"block\", \"reason\": \"Refactor phase violation: ignore hygiene gate failed -- every suppression must be explicit and justified. Findings: ${summary}\"}}"
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

# ---------- Gate 5: Python linting on changed source AND test files ----------
lint_status="no python changes"
if [ -n "$changed_lint_py" ] || [ -n "$inherited_lint_py" ]; then
    lint_status="skipped (script/python not available)"
    lint_script=".github/scripts/check-python-linting.py"
    if [ -f "$lint_script" ] && [ -n "$python_exe" ]; then
        lint_exit=0
        if [ -n "$changed_lint_py" ]; then
            lint_output=$(echo "$changed_lint_py" | xargs "$python_exe" "$lint_script" --files 2>&1)
            lint_exit=$?
        fi
        # Inherited files are checked separately so the block message can say
        # whose debt this is and which moves are legal.
        inherited_exit=0
        if [ "$lint_exit" -eq 0 ] && [ -n "$inherited_lint_py" ]; then
            inherited_output=$(echo "$inherited_lint_py" | xargs "$python_exe" "$lint_script" --files 2>&1)
            inherited_exit=$?
        fi
        if [ "$lint_exit" -eq 2 ]; then
            lint_summary=$(echo "$lint_output" | head -15 | tr '\n' ' ' | sed 's/"/\\"/g')
            echo "{\"hookSpecificOutput\": {\"hookEventName\": \"Stop\", \"decision\": \"block\", \"reason\": \"Refactor phase violation: linting gate failed. Fix with: ruff check --fix <files>. Violations: ${lint_summary}\"}}"
            exit 0
        elif [ "$lint_exit" -eq 1 ] || [ "$inherited_exit" -eq 1 ]; then
            echo '{"hookSpecificOutput": {"hookEventName": "Stop", "decision": "block", "reason": "Refactor phase blocked: linting gate unavailable because ruff is not installed. Install dev dependencies or run: pip install ruff"}}'
            exit 0
        elif [ "$inherited_exit" -eq 2 ]; then
            inherited_summary=$(echo "$inherited_output" | head -15 | tr '\n' ' ' | sed 's/"/\\"/g')
            echo "{\"hookSpecificOutput\": {\"hookEventName\": \"Stop\", \"decision\": \"block\", \"reason\": \"Refactor phase violation: linting gate failed on files this branch committed in an EARLIER phase (branch delta vs ${BASE_BRANCH}). You did not author them in this step, but they ship on merge. Two legal moves: fix them (usually ruff check --fix <files>), or acknowledge each one with '# noqa: RULE  # reason' in its own standalone commit ([agent:name] justify ignore: file:line RULE -- reason). Do not leave them unrecorded. Violations: ${inherited_summary}\"}}"
            exit 0
        else
            lint_status="clean"
            if [ -n "$inherited_lint_py" ]; then
                lint_status="clean (incl. $(echo "$inherited_lint_py" | grep -c '[^[:space:]]') inherited from earlier phases)"
            fi
        fi
    fi
fi

# All gates passed
if [[ -n "$test_gate_skipped" ]]; then
    pass_detail="test gate skipped (${test_gate_skipped})"
elif [[ "$from_log" == true ]]; then
    pass_detail="tests accepted from log"
else
    pass_detail="tests green"
fi
echo "{\"systemMessage\": \"refactorer:Stop \u2014 all gates PASS: ${pass_detail}, no new files created, python quality verified, linting: ${lint_status}\"}"
exit 0
