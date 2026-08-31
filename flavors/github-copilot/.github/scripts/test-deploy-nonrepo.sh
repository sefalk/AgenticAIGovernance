#!/usr/bin/env bash
# Asserts deploy.sh treats a target that is not a git repository as a supported
# first run, and says so. Before #244 it exited 128 with no output at all.
#
# This is the bash counterpart of the same assertion in test-deploy-flags.ps1.
# The two deploy paths are only equivalent if both are executed (#190).
#
# Each case stops the deploy once it is provably past the branch check rather
# than waiting for it to finish: a full dry run of ~213 files takes over five
# minutes under Git-for-Windows bash, and every claim this suite makes is
# already settled by then.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AF_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEPLOY="$AF_ROOT/deploy.sh"

NOTE_LINE='Note: Target is not a git repository -- branch checks skipped.'
WARN_PREFIX='WARNING: Target repo is on'
PAST_HEADER='CREATE '
MAX_WAIT=180

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); }

assert_contains() {
    local file="$1" needle="$2" label="$3"
    if grep -qF -- "$needle" "$file"; then pass "$label"; else fail "$label"; fi
}

assert_absent() {
    local file="$1" needle="$2" label="$3"
    if grep -qF -- "$needle" "$file"; then fail "$label"; else pass "$label"; fi
}

# Runs a deploy until its file plan starts, then stops it. A run that dies at
# the branch check -- the #244 defect -- never gets there and leaves the marker
# absent, which is what the caller asserts on.
run_past_header() {
    local target="$1" log="$2"
    : >"$log"
    bash "$DEPLOY" -t "$target" -n </dev/null >"$log" 2>&1 &
    local pid=$! waited=0
    while kill -0 "$pid" 2>/dev/null; do
        grep -qF -- "$PAST_HEADER" "$log" && break
        [[ "$waited" -ge "$MAX_WAIT" ]] && break
        sleep 1
        waited=$((waited + 1))
    done
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
}

if [[ ! -f "$DEPLOY" ]]; then
    echo "No deploy.sh at $DEPLOY -- this suite would prove nothing."
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
TARGET="$WORK/target"
mkdir -p "$TARGET"

echo "== A: target is not a git repository =="
run_past_header "$TARGET" "$WORK/a.log"
assert_contains "$WORK/a.log" "$PAST_HEADER" "Deploy proceeds instead of aborting at the header"
assert_contains "$WORK/a.log" "$NOTE_LINE" "The non-repo case is stated"

echo "== B: same directory, now a repository on an agent branch =="
git init -q "$TARGET"
git -C "$TARGET" checkout -q -b agent/deploy-probe
run_past_header "$TARGET" "$WORK/b.log"
assert_contains "$WORK/b.log" "$PAST_HEADER" "Deploy proceeds on a repository target"
assert_absent "$WORK/b.log" "$NOTE_LINE" "The non-repo note does not fire for a repository"
assert_contains "$WORK/b.log" "$WARN_PREFIX" "The agent-branch warning still fires"

echo "== C: same repository on dev =="
git -C "$TARGET" checkout -q -b dev
run_past_header "$TARGET" "$WORK/c.log"
assert_contains "$WORK/c.log" "$PAST_HEADER" "Deploy proceeds on dev"
assert_absent "$WORK/c.log" "$WARN_PREFIX" "No branch warning on dev"

echo ""
echo "=== Summary ==="
echo "  Passed: $passed"
echo "  Failed: $failed"

if [[ "$failed" -gt 0 ]]; then
    exit 1
fi
echo "  All deploy non-repo tests passed."
