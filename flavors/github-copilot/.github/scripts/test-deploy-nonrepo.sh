#!/usr/bin/env bash
# Asserts deploy.sh treats a target that is not a git repository as a supported
# first run, and says so. Before #244 it exited 128 with no output at all.
#
# This is the bash counterpart of the same assertion in test-deploy-flags.ps1.
# The two deploy paths are only equivalent if both are executed (#190).
# Cases E-H do the same for the .mcp.json registration (#547).
#
# Each case stops the deploy once it is provably past the branch check rather
# than waiting for it to finish: a full dry run of ~213 files takes over five
# minutes under Git-for-Windows bash (#260), and every claim this suite makes
# is already settled by then.

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

# #104: the bash twin of the ignored-payload warning in test-deploy-flags.ps1.
echo "== D: same repository, .github/ and .vscode/ gitignored =="
printf 'build/\n.github/\n.vscode/\n' >"$TARGET/.gitignore"
run_past_header "$TARGET" "$WORK/d.log"
assert_contains "$WORK/d.log" "WARNING: .github/ is gitignored in the target" "An ignored payload is announced before anything is written"
assert_contains "$WORK/d.log" ".gitignore:2" "The warning names the rule that ignores it"
assert_contains "$WORK/d.log" "WARNING: .vscode/ is gitignored in the target" "An ignored .vscode/ is announced too"
assert_absent "$WORK/c.log" "is gitignored in the target" "control: case C (nothing ignored) drew no warning"

# #547: the bash twin of test-github-mcp-registration.ps1. The registration
# runs before the payload copy, so each case stops once the copy announces itself.
MCP_PAST='.github/ directories:'
MCP_WARN='has no "af-github" server'

run_past_registration() {
    local target="$1" log="$2" mode="$3"
    : >"$log"
    if [[ "$mode" == "dry" ]]; then
        bash "$DEPLOY" -t "$target" -n </dev/null >"$log" 2>&1 &
    else
        bash "$DEPLOY" -t "$target" </dev/null >"$log" 2>&1 &
    fi
    local pid=$! waited=0
    while kill -0 "$pid" 2>/dev/null; do
        grep -qF -- "$MCP_PAST" "$log" && break
        [[ "$waited" -ge "$MAX_WAIT" ]] && break
        sleep 1
        waited=$((waited + 1))
    done
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
}

echo "== E: no .mcp.json -> created with af-github =="
mkdir -p "$WORK/e"
run_past_registration "$WORK/e" "$WORK/e.log" real
if [[ -f "$WORK/e/.mcp.json" ]]; then pass "An absent .mcp.json is created"; else fail "An absent .mcp.json is created"; fi
assert_contains "$WORK/e/.mcp.json" '"af-github"' "The created file registers af-github" 2>/dev/null
assert_contains "$WORK/e/.mcp.json" 'Bearer ${AF_GH_TOKEN}' "The token is an env reference, not a secret" 2>/dev/null

echo "== F: no .mcp.json, dry run -> nothing written =="
mkdir -p "$WORK/f"
run_past_registration "$WORK/f" "$WORK/f.log" dry
if [[ -e "$WORK/f/.mcp.json" ]]; then fail "A dry run writes no .mcp.json"; else pass "A dry run writes no .mcp.json"; fi
assert_contains "$WORK/f.log" "CREATE  .mcp.json" "The dry run announces the creation"

echo "== G: project .mcp.json without af-github -> untouched, warned =="
mkdir -p "$WORK/g"
printf '{\r\n  "mcpServers": { "other": { "type": "stdio", "command": "x" } }\r\n}\r\n' >"$WORK/g/.mcp.json"
cp "$WORK/g/.mcp.json" "$WORK/g.orig"
run_past_registration "$WORK/g" "$WORK/g.log" real
if cmp -s "$WORK/g/.mcp.json" "$WORK/g.orig"; then pass "A project .mcp.json stays byte-identical"; else fail "A project .mcp.json stays byte-identical"; fi
assert_contains "$WORK/g.log" "$MCP_WARN" "A missing af-github entry is warned about"
assert_contains "$WORK/g.log" 'Bearer ${AF_GH_TOKEN}' "The warning carries the snippet"

echo "== H: project .mcp.json with af-github -> no warning =="
mkdir -p "$WORK/h"
printf '{"mcpServers":{"af-github":{"type":"http","url":"https://example.invalid/mcp/"}}}' >"$WORK/h/.mcp.json"
cp "$WORK/h/.mcp.json" "$WORK/h.orig"
run_past_registration "$WORK/h" "$WORK/h.log" dry
assert_contains "$WORK/h.log" "$MCP_PAST" "control: the deploy got past the registration step"
assert_absent "$WORK/h.log" "$MCP_WARN" "A registered af-github draws no warning"
if cmp -s "$WORK/h/.mcp.json" "$WORK/h.orig"; then pass "A registered .mcp.json is untouched"; else fail "A registered .mcp.json is untouched"; fi

echo ""
echo "=== Summary ==="
echo "  Passed: $passed"
echo "  Failed: $failed"

if [[ "$failed" -gt 0 ]]; then
    exit 1
fi
echo "  All deploy non-repo tests passed."
