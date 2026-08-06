#!/usr/bin/env bash
# Canonical test runner for agent workflows.
# All agents MUST use this script instead of calling pytest directly.
#
# Usage:
#   .github/scripts/run-tests.sh                                    # Run all tests
#   .github/scripts/run-tests.sh --scope domain                     # Domain tests only
#   .github/scripts/run-tests.sh --scope adapters                   # Adapter tests only
#   .github/scripts/run-tests.sh --file tests/domain/test_helper.py # Specific file
#   .github/scripts/run-tests.sh --filter "test_name"               # Filter by -k
#   .github/scripts/run-tests.sh --scope domain --coverage          # With coverage
#   .github/scripts/run-tests.sh --scope domain --fail-fast         # Stop on first failure
#   .github/scripts/run-tests.sh --scope domain --output-file --force  # Write full output
#   .github/scripts/run-tests.sh --traceback long                   # Long tracebacks
#
# Output file: .github/test-output.txt (only when --output-file is set)
#
# Exit codes:
#   0 = all tests passed
#   1 = test failures
#   2 = no tests collected
#   5 = no tests matched (pytest exit code)

# Resolve workspace root (script is at .github/scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# --- Configuration: set COV_PACKAGE to your source package name ---
# Load project config for source package name
SRC_DIR="src"
_conf="${WORKSPACE_ROOT}/.github/af-env.conf"
if [ -f "$_conf" ]; then
    _val=$(grep -E '^SRC_DIR=' "$_conf" | head -1 | cut -d= -f2-)
    [ -n "$_val" ] && SRC_DIR="$_val"
fi
COV_PACKAGE="${SRC_DIR}"

# Defaults
SCOPE="all"
FILE=""
FILTER=""
TRACEBACK="short"
COVERAGE=false
FAIL_FAST=false
DO_OUTPUT_FILE=false
FORCE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope)
            SCOPE="$2"
            shift 2
            ;;
        --file)
            FILE="$2"
            shift 2
            ;;
        --filter)
            FILTER="$2"
            shift 2
            ;;
        --traceback)
            TRACEBACK="$2"
            shift 2
            ;;
        --coverage)
            COVERAGE=true
            shift
            ;;
        --fail-fast)
            FAIL_FAST=true
            shift
            ;;
        --output-file)
            DO_OUTPUT_FILE=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Resolve venv python
PYTHON="$WORKSPACE_ROOT/.venv/bin/python"
if [[ ! -x "$PYTHON" ]]; then
    echo "ERROR: venv python not found at $PYTHON"
    exit 1
fi

# Validate --file if provided
if [[ -n "$FILE" ]]; then
    FULL_FILE="$WORKSPACE_ROOT/$FILE"
    if [[ ! -f "$FULL_FILE" ]]; then
        echo "ERROR: test file not found: $FILE"
        exit 1
    fi
fi

# Check output file conflict
OUTPUT_FILE_PATH="$WORKSPACE_ROOT/.github/test-output.txt"
if [[ "$DO_OUTPUT_FILE" == true ]] && [[ -f "$OUTPUT_FILE_PATH" ]] && [[ "$FORCE" != true ]]; then
    echo "ERROR: Output file exists at .github/test-output.txt. Use --force to overwrite."
    exit 1
fi

if [[ "$FORCE" == true ]] && [[ "$DO_OUTPUT_FILE" != true ]]; then
    echo "WARNING: --force has no effect without --output-file"
fi

# Map scope to test directory.
# INVARIANT: no scope path may carry a trailing separator (kept in lockstep with
# run-tests.ps1, where a trailing separator corrupts the argument vector).
# Pinned by .github/scripts/test-run-tests.ps1.
case "$SCOPE" in
    all)        TEST_PATH="$WORKSPACE_ROOT/tests" ;;
    domain)     TEST_PATH="$WORKSPACE_ROOT/tests/domain" ;;
    adapters)   TEST_PATH="$WORKSPACE_ROOT/tests/adapters" ;;
    properties) TEST_PATH="$WORKSPACE_ROOT/tests/properties" ;;
    contracts)  TEST_PATH="$WORKSPACE_ROOT/tests/contracts" ;;
    *)
        echo "ERROR: invalid scope '$SCOPE'. Use: all|domain|adapters|properties|contracts"
        exit 1
        ;;
esac

# Validate traceback
case "$TRACEBACK" in
    short|long|line|no|auto) ;;
    *) echo "ERROR: invalid traceback '$TRACEBACK'. Use: short|long|line|no|auto"; exit 1 ;;
esac

# Build pytest arguments
PYTEST_ARGS=(-m pytest)
if [[ -n "$FILE" ]]; then
    PYTEST_ARGS+=("$FULL_FILE")
else
    PYTEST_ARGS+=("$TEST_PATH")
fi

PYTEST_ARGS+=("--tb=$TRACEBACK" -q --no-header)

if [[ -n "$FILTER" ]]; then
    PYTEST_ARGS+=(-k "$FILTER")
fi

if [[ "$COVERAGE" == true ]]; then
    PYTEST_ARGS+=("--cov=$COV_PACKAGE" --cov-report=term-missing --cov-branch)
fi

if [[ "$FAIL_FAST" == true ]]; then
    PYTEST_ARGS+=(-x)
fi

# Header
if [[ -n "$FILE" ]]; then
    TARGET_DISPLAY="file=$FILE"
else
    TARGET_DISPLAY="scope=$SCOPE"
fi
FILTER_DISPLAY="${FILTER:-none}"
echo "=== Test Runner: $TARGET_DISPLAY filter=$FILTER_DISPLAY ==="

# Run pytest. stderr is captured to a file rather than discarded: it is noise on
# a successful run (PySpark), but it is the ONLY diagnosis when the runner itself
# fails, and discarding it is what made this failure mode silent.
cd "$WORKSPACE_ROOT"
STDERR_PATH="$(mktemp "${TMPDIR:-/tmp}/af-run-tests.XXXXXX")"
STDOUT=$("$PYTHON" "${PYTEST_ARGS[@]}" 2>"$STDERR_PATH")
PYTEST_EXIT=$?
STDERR_TEXT="$(cat "$STDERR_PATH" 2>/dev/null)"
rm -f "$STDERR_PATH"

# ---------- Update test log (.github/test-log.json) ----------
TEST_LOG_PATH="$WORKSPACE_ROOT/.github/test-log.json"

# Parse pytest summary: "619 passed in 5.33s" or "617 passed, 2 failed in 5.33s"
PASSED=0; FAILED=0; ERRORS=0; RUNTIME=0
if [[ -n "$STDOUT" ]]; then
    SUMMARY_LINE=$(echo "$STDOUT" | grep -E '\d+ passed|\d+ failed|\d+ error' | tail -1)
    if [[ -n "$SUMMARY_LINE" ]]; then
        p=$(echo "$SUMMARY_LINE" | grep -oP '(\d+) passed' | grep -oP '\d+')
        f=$(echo "$SUMMARY_LINE" | grep -oP '(\d+) failed' | grep -oP '\d+')
        e=$(echo "$SUMMARY_LINE" | grep -oP '(\d+) error'  | grep -oP '\d+')
        r=$(echo "$SUMMARY_LINE" | grep -oP 'in (\d+\.?\d*)s' | grep -oP '[\d.]+')
        [[ -n "$p" ]] && PASSED=$p
        [[ -n "$f" ]] && FAILED=$f
        [[ -n "$e" ]] && ERRORS=$e
        [[ -n "$r" ]] && RUNTIME=$r
    fi
fi
TOTAL=$((PASSED + FAILED + ERRORS))

# A run that produced no parseable summary AND exited non-zero never executed a
# test: wrong interpreter, missing dependency, usage error, nothing collected.
# Reporting that as "0 failed" is indistinguishable from a clean green run, so
# the counters are recorded as null and the entry is labelled an error instead.
RUNNER_FAILED=false
if [[ -z "$SUMMARY_LINE" ]] && [[ "$PYTEST_EXIT" -ne 0 ]]; then
    RUNNER_FAILED=true
fi

# Extract coverage % if requested
COV_PCT="null"
if [[ "$COVERAGE" == true ]] && [[ -n "$STDOUT" ]]; then
    cov_line=$(echo "$STDOUT" | grep -E '^TOTAL\s+' | tail -1)
    if [[ -n "$cov_line" ]]; then
        cov_val=$(echo "$cov_line" | grep -oP '\d+%' | grep -oP '\d+')
        [[ -n "$cov_val" ]] && COV_PCT=$cov_val
    fi
fi

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Build JSON entry
if [[ "$RUNNER_FAILED" == true ]]; then
    ERR_MSG="$(echo "$STDERR_TEXT" | grep -v '^[[:space:]]*$' | tail -3 | tr '\n' '|' | sed 's/|$//')"
    [[ -z "$ERR_MSG" ]] && ERR_MSG="pytest produced no output and exited with code $PYTEST_EXIT"
    # Escape for JSON embedding (backslash, quote, control chars).
    ERR_MSG="$(printf '%s' "$ERR_MSG" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/ /g')"
    ENTRY=$(cat <<ENTRY_EOF
{"last_run":"$NOW","passed":null,"failed":null,"errors":null,"total":0,"runtime_seconds":0,"run_by":"run-tests.sh","exit_code":$PYTEST_EXIT,"coverage_percent":null,"status":"error","error_message":"$ERR_MSG"}
ENTRY_EOF
)
else
    ENTRY=$(cat <<ENTRY_EOF
{"last_run":"$NOW","passed":$PASSED,"failed":$FAILED,"errors":$ERRORS,"total":$TOTAL,"runtime_seconds":$RUNTIME,"run_by":"run-tests.sh","exit_code":$PYTEST_EXIT,"coverage_percent":$COV_PCT,"status":"ok"}
ENTRY_EOF
)
fi

# Determine scope key
if [[ -n "$FILE" ]]; then
    SCOPE_KEY="file"
    [[ "$FILE" == *"tests/domain"* ]]     && SCOPE_KEY="domain"
    [[ "$FILE" == *"tests/adapters"* ]]   && SCOPE_KEY="adapters"
    [[ "$FILE" == *"tests/properties"* ]] && SCOPE_KEY="properties"
    [[ "$FILE" == *"tests/contracts"* ]]  && SCOPE_KEY="contracts"
elif [[ "$SCOPE" == "all" ]]; then
    SCOPE_KEY="all"
else
    SCOPE_KEY="$SCOPE"
fi

# Merge into existing log (or create new) — pure bash, no python
# NOTE: The sed extraction below assumes test-log.json has a FLAT structure:
#   { "scope": { ...flat-key-value-pairs... }, ... }
# Constraints for correctness:
#   1. Each scope value must be a single-level object (no nested braces).
#   2. The greedy .* in sed patterns matches the LAST occurrence of each key.
#      This is safe because the known scope names (domain, adapters, properties,
#      contracts, all, file) do not appear as substrings in value fields.
# If the schema gains nested objects, dynamic keys, or scope names in values,
# replace this with jq or python.
d_domain="" d_adapters="" d_properties="" d_contracts="" d_all="" d_file=""
if [[ -f "$TEST_LOG_PATH" ]]; then
    _flat=$(tr -d '\n\r' < "$TEST_LOG_PATH" | tr -s ' ')
    d_domain=$(echo "$_flat" | sed -n 's/.*"domain" *: *\({[^}]*}\).*/\1/p')
    d_adapters=$(echo "$_flat" | sed -n 's/.*"adapters" *: *\({[^}]*}\).*/\1/p')
    d_properties=$(echo "$_flat" | sed -n 's/.*"properties" *: *\({[^}]*}\).*/\1/p')
    d_contracts=$(echo "$_flat" | sed -n 's/.*"contracts" *: *\({[^}]*}\).*/\1/p')
    d_all=$(echo "$_flat" | sed -n 's/.*"all" *: *\({[^}]*}\).*/\1/p')
    d_file=$(echo "$_flat" | sed -n 's/.*"file" *: *\({[^}]*}\).*/\1/p')
fi

case "$SCOPE_KEY" in
    domain)     d_domain="$ENTRY" ;;
    adapters)   d_adapters="$ENTRY" ;;
    properties) d_properties="$ENTRY" ;;
    contracts)  d_contracts="$ENTRY" ;;
    all)        d_all="$ENTRY" ;;
    file)       d_file="$ENTRY" ;;
esac

{
    printf '{\n'
    _first=true
    for _scope in domain adapters properties contracts all file; do
        case "$_scope" in
            domain)     _val="$d_domain" ;;
            adapters)   _val="$d_adapters" ;;
            properties) _val="$d_properties" ;;
            contracts)  _val="$d_contracts" ;;
            all)        _val="$d_all" ;;
            file)       _val="$d_file" ;;
        esac
        if [[ -n "$_val" ]]; then
            $_first || printf ',\n'
            printf '  "%s": %s' "$_scope" "$_val"
            _first=false
        fi
    done
    printf '\n}\n'
} > "$TEST_LOG_PATH"

# Write output file if requested
if [[ "$DO_OUTPUT_FILE" == true ]]; then
    if [[ -n "$STDOUT" ]]; then
        echo "$STDOUT" > "$OUTPUT_FILE_PATH"
        LINE_COUNT=$(echo "$STDOUT" | wc -l)
        echo "(Full output: .github/test-output.txt - $LINE_COUNT lines)"
    else
        echo "(no pytest output)" > "$OUTPUT_FILE_PATH"
        echo "(Full output: .github/test-output.txt - empty)"
    fi
fi

# Show summary (last 5 lines of stdout)
if [[ -n "$STDOUT" ]]; then
    echo "$STDOUT" | tail -5
else
    echo "(no pytest output)"
fi

# Surface the runner failure instead of leaving the caller with a bare exit code.
if [[ "$RUNNER_FAILED" == true ]]; then
    echo "ERROR: pytest did not run -- no test results were produced."
    if [[ -n "$STDERR_TEXT" ]]; then
        echo "$STDERR_TEXT" | grep -v '^[[:space:]]*$' | tail -10 | sed 's/^/  /'
    fi
    echo "(test-log.json entry recorded as status=error, not as a passing run)"
fi

# Footer
echo "=== Exit Code: $PYTEST_EXIT ==="

exit $PYTEST_EXIT
