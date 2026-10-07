#!/usr/bin/env bash
# Asserts deploy.sh keeps the _available/ copy of a deactivated skill current
# (#384), the bash counterpart of test_skill_deactivation.py.
#
# The pytest parity cases for deploy.sh skip on Windows: a full deploy of the
# real payload outlasts their 300s limit under Git-for-Windows bash (#260). This
# deploys from a minimal source -- deploy.sh, VERSION, the manifest and one skill
# -- so the engine runs in about a minute and the claim is actually executed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AF_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); }
assert_contains() { if grep -qF -- "$2" "$1"; then pass "$3"; else fail "$3"; fi; }

for f in deploy.sh VERSION .github/.af-manifest; do
    if [[ ! -f "$AF_ROOT/$f" ]]; then
        echo "No $f under $AF_ROOT -- this suite would prove nothing."
        exit 1
    fi
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SRC="$WORK/src"
mkdir -p "$SRC/.github/skills/demo-skill"
cp "$AF_ROOT/deploy.sh" "$AF_ROOT/VERSION" "$SRC/"
cp "$AF_ROOT/.github/.af-manifest" "$SRC/.github/"
printf 'demo skill, current version\n' >"$SRC/.github/skills/demo-skill/SKILL.md"

KEY='skills/_available/demo-skill/SKILL.md'

# A project that deactivated demo-skill at an older version, deployed before.
make_target() {
    local tgt="$1" baseline_line="$2"
    mkdir -p "$tgt/.github/skills/_available/demo-skill"
    printf 'demo skill, old version\n' >"$tgt/.github/$KEY"
    printf '# AF deployment baseline hashes\n%s\n' "$baseline_line" >"$tgt/.github/.af-hashes"
    git init -q "$tgt"
}

echo "== A: an unedited stale copy is refreshed, the skill stays deactivated =="
make_target "$WORK/a" 'probe=0'
bash "$SRC/deploy.sh" -t "$WORK/a" </dev/null >"$WORK/a.log" 2>&1
assert_contains "$WORK/a.log" "DEACTIVATED .github/skills/demo-skill/SKILL.md" "The skill is still reported DEACTIVATED"
assert_contains "$WORK/a.log" "UPDATE  .github/$KEY" "The _available copy is classified UPDATE"
if cmp -s "$SRC/.github/skills/demo-skill/SKILL.md" "$WORK/a/.github/$KEY"; then
    pass "The _available copy now equals the source"
else
    fail "The _available copy now equals the source"
fi
if [[ ! -e "$WORK/a/.github/skills/demo-skill/SKILL.md" ]]; then
    pass "skills/demo-skill/ is not re-created"
else
    fail "skills/demo-skill/ is not re-created"
fi
assert_contains "$WORK/a/.github/.af-hashes" "$KEY=" "The copy is baselined under its _available key"

echo "== B: a project-edited copy is a CONFLICT and stays untouched =="
make_target "$WORK/b" "$KEY=0000000000000000000000000000000000000000000000000000000000000000"
bash "$SRC/deploy.sh" -t "$WORK/b" </dev/null >"$WORK/b.log" 2>&1
assert_contains "$WORK/b.log" "CONFLICT .github/$KEY" "The edited copy is classified CONFLICT"
assert_contains "$WORK/b/.github/$KEY" "demo skill, old version" "The edited copy is left as it was"

echo ""
echo "=== Summary ==="
echo "  Passed: $passed"
echo "  Failed: $failed"
if [[ "$failed" -gt 0 ]]; then
    echo "--- deploy output A ---"; cat "$WORK/a.log"
    echo "--- deploy output B ---"; cat "$WORK/b.log"
    exit 1
fi
echo "  All deactivated-skill sync tests passed."
