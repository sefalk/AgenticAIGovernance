#!/usr/bin/env bash
# Asserts deploy.sh keeps the _available/ copy of a deactivated skill current
# (#384), the bash counterpart of test_skill_deactivation.py, updates a
# customizable file the project never changed (#106), keeps an activated
# optional skill where the project moved it (#110), and keeps the baseline
# store and merges a both-sides change like deploy_core (#393).
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

# #106: the same minimal source covers the customizable branch of deploy_file.
ARCH='instructions/architecture.instructions.md'
mkdir -p "$SRC/.github/instructions"
printf '# architecture, framework fix\n' >"$SRC/.github/$ARCH"
OLD_HASH=$(printf '# architecture, as deployed\n' | sha256sum | cut -d' ' -f1 | tr 'a-f' 'A-F')

echo "== C: an untouched customizable file is UPDATEd (#106) =="
mkdir -p "$WORK/c/.github/instructions"
printf '# architecture, as deployed\n' >"$WORK/c/.github/$ARCH"
printf '# AF deployment baseline hashes\n%s=%s\n' "$ARCH" "$OLD_HASH" >"$WORK/c/.github/.af-hashes"
git init -q "$WORK/c"
bash "$SRC/deploy.sh" -t "$WORK/c" </dev/null >"$WORK/c.log" 2>&1
assert_contains "$WORK/c.log" "UPDATE  .github/$ARCH" "The untouched customizable file is classified UPDATE"
assert_contains "$WORK/c/.github/$ARCH" "framework fix" "The framework change is written"

echo "== D: a customized file both sides changed stays CONFLICT (#106 control) =="
mkdir -p "$WORK/d/.github/instructions"
printf '# architecture, ours\n' >"$WORK/d/.github/$ARCH"
printf '# AF deployment baseline hashes\n%s=%s\n' "$ARCH" "$OLD_HASH" >"$WORK/d/.github/.af-hashes"
git init -q "$WORK/d"
bash "$SRC/deploy.sh" -t "$WORK/d" </dev/null >"$WORK/d.log" 2>&1
assert_contains "$WORK/d.log" "CONFLICT .github/$ARCH" "The customized file is classified CONFLICT"
assert_contains "$WORK/d/.github/$ARCH" "architecture, ours" "The customized file is left as it was"

# #110: an activated optional skill stays where the project moved it.
OPT='demo-opt'
OPT_AVAIL="skills/_available/$OPT/SKILL.md"
OPT_ACTIVE="skills/$OPT/SKILL.md"
mkdir -p "$SRC/.github/skills/_available/$OPT"
printf 'opt skill, framework fix\n' >"$SRC/.github/$OPT_AVAIL"
OPT_OLD_HASH=$(printf 'opt skill, as activated\n' | sha256sum | cut -d' ' -f1 | tr 'a-f' 'A-F')
make_activated() {
    local tgt="$1" content="$2"
    mkdir -p "$tgt/.github/skills/$OPT"
    printf '%s\n' "$content" >"$tgt/.github/$OPT_ACTIVE"
    printf '# AF deployment baseline hashes\n%s=%s\n' "$OPT_AVAIL" "$OPT_OLD_HASH" >"$tgt/.github/.af-hashes"
    git init -q "$tgt"
}

echo "== E: an untouched activated skill is UPDATEd in place (#110) =="
make_activated "$WORK/e" 'opt skill, as activated'
bash "$SRC/deploy.sh" -t "$WORK/e" </dev/null >"$WORK/e.log" 2>&1
assert_contains "$WORK/e.log" "UPDATE  .github/$OPT_ACTIVE" "The active copy is classified UPDATE"
assert_contains "$WORK/e/.github/$OPT_ACTIVE" "framework fix" "The framework change lands in the active copy"
if [[ ! -e "$WORK/e/.github/$OPT_AVAIL" ]]; then
    pass "The _available copy is not re-created"
else
    fail "The _available copy is not re-created"
fi

echo "== F: an edited activated skill is a CONFLICT and stays untouched (#110 control) =="
make_activated "$WORK/f" 'opt skill, project edit'
bash "$SRC/deploy.sh" -t "$WORK/f" </dev/null >"$WORK/f.log" 2>&1
assert_contains "$WORK/f.log" "CONFLICT .github/$OPT_ACTIVE" "The edited active copy is classified CONFLICT"
assert_contains "$WORK/f/.github/$OPT_ACTIVE" "project edit" "The edited active copy is left as it was"

echo "== G: the unresolved conflict survives a second deploy (#110) =="
bash "$SRC/deploy.sh" -t "$WORK/f" </dev/null >"$WORK/g.log" 2>&1
assert_contains "$WORK/g.log" "CONFLICT .github/$OPT_ACTIVE" "The second run still reports CONFLICT"
assert_contains "$WORK/f/.github/$OPT_ACTIVE" "project edit" "The second run leaves the edit alone"

# #393: deploy.sh keeps the baseline store and merges a both-sides change like deploy_core.
PLAIN='MANIFEST.md'
lines() { for i in $(seq 1 12); do printf 'line %s\n' "$i"; done; }
edit_lines() { lines | sed "$1"; }
lines >"$SRC/.github/$PLAIN"
H_HASH=$(lines | sha256sum | cut -d' ' -f1 | tr 'a-f' 'A-F')

echo "== H: a script deploy stores each baselined content and ignores the store (#393) =="
mkdir -p "$WORK/h"
git init -q "$WORK/h"
bash "$SRC/deploy.sh" -t "$WORK/h" </dev/null >"$WORK/h.log" 2>&1
assert_contains "$WORK/h/.github/.af-hashes" "$PLAIN=$H_HASH" "The file is baselined"
if [[ -f "$WORK/h/.github/.af-baseline/$H_HASH" ]] && cmp -s "$WORK/h/.github/.af-baseline/$H_HASH" "$SRC/.github/$PLAIN"; then
    pass "The baselined content is stored under its hash"
else
    fail "The baselined content is stored under its hash"
fi
assert_contains "$WORK/h/.github/.af-baseline/.gitignore" "*" "The store ignores itself in git"

echo "== I: a non-overlapping both-sides change is MERGEd (#393) =="
cp -r "$WORK/h" "$WORK/i"
edit_lines '2s/.*/line AF/' >"$SRC/.github/$PLAIN"
edit_lines '10s/.*/line PROJECT/' >"$WORK/i/.github/$PLAIN"
bash "$SRC/deploy.sh" -t "$WORK/i" </dev/null >"$WORK/i.log" 2>&1
assert_contains "$WORK/i.log" "MERGE   .github/$PLAIN" "The file is classified MERGE"
if cmp -s <(edit_lines '2s/.*/line AF/;10s/.*/line PROJECT/') "$WORK/i/.github/$PLAIN"; then
    pass "The merged file carries both edits, byte-exact"
else
    fail "The merged file carries both edits, byte-exact"
fi
if [[ ! -e "$WORK/i/.github/.af-baseline/$H_HASH" ]]; then
    pass "The superseded store object is pruned"
else
    fail "The superseded store object is pruned"
fi

echo "== J: overlapping changes stay CONFLICT (#393 control) =="
cp -r "$WORK/h" "$WORK/j"
edit_lines '2s/.*/line PROJECT/' >"$WORK/j/.github/$PLAIN"
bash "$SRC/deploy.sh" -t "$WORK/j" </dev/null >"$WORK/j.log" 2>&1
assert_contains "$WORK/j.log" "CONFLICT .github/$PLAIN" "The overlapping change is classified CONFLICT"
assert_contains "$WORK/j/.github/$PLAIN" "line PROJECT" "The project file is left as it was"

# #426: VERSION moves only at a release cut, so .af-version names the commit.
echo "== K: a source outside git writes no commit line (#426) =="
if grep -q '^commit:' "$WORK/h/.github/.af-version"; then
    fail "No commit line without a commit"
else
    pass "No commit line without a commit"
fi

echo "== L: a committed source records its commit, dirty when a tracked file is edited (#426) =="
git_t() { git -C "$SRC" -c core.autocrlf=false -c user.name=af-test -c user.email=af-test@example.invalid "$@"; }
git_t init -q
git_t add -- VERSION .github
git_t commit -q --no-verify -m seed
HEAD12=$(git_t rev-parse --short=12 HEAD)
mkdir -p "$WORK/l" "$WORK/m"
git init -q "$WORK/l"
bash "$SRC/deploy.sh" -t "$WORK/l" </dev/null >"$WORK/l.log" 2>&1
if grep -qx "commit: $HEAD12" "$WORK/l/.github/.af-version"; then
    pass "The commit line is the short HEAD"
else
    fail "The commit line is the short HEAD (want $HEAD12)"
fi
printf 'line edited\n' >>"$SRC/.github/$PLAIN"
git init -q "$WORK/m"
bash "$SRC/deploy.sh" -t "$WORK/m" </dev/null >"$WORK/m.log" 2>&1
assert_contains "$WORK/m/.github/.af-version" "commit: $HEAD12-dirty" "An edited tracked file marks the commit dirty"

echo ""
echo "=== Summary ==="
echo "  Passed: $passed"
echo "  Failed: $failed"
if [[ "$failed" -gt 0 ]]; then
    echo "--- deploy output A ---"; cat "$WORK/a.log"
    echo "--- deploy output B ---"; cat "$WORK/b.log"
    echo "--- deploy output C ---"; cat "$WORK/c.log"
    echo "--- deploy output D ---"; cat "$WORK/d.log"
    echo "--- deploy output E ---"; cat "$WORK/e.log"
    echo "--- deploy output F ---"; cat "$WORK/f.log"
    echo "--- deploy output G ---"; cat "$WORK/g.log"
    for c in h i j l m; do echo "--- deploy output ${c^^} ---"; cat "$WORK/$c.log"; done
    exit 1
fi
echo "  All deploy.sh minimal-source tests passed."
