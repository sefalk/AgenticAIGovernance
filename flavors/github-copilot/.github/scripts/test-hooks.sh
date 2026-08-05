#!/usr/bin/env bash
# Behavioural tests for the bash hook pendants.
#
# The PowerShell suite (test-hooks.ps1) is the primary harness; this script
# covers the .sh pendants, which are otherwise only ever reviewed by reading.
# It is deliberately narrow: the guards whose verdicts depend on repository
# state (branch context, TDD phase isolation, no-new-files, fetch allowlist).
#
# Every case runs the hook inside a throwaway git repository checked out on a
# stated branch, so the assertion never depends on the developer's own
# checkout. Run from anywhere:
#
#     bash .github/scripts/test-hooks.sh

set -uo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GITHUB_DIR=$(dirname "$SCRIPT_DIR")
HOOK_DIR="$GITHUB_DIR/hooks/scripts"

pass=0
fail=0

# The hooks resolve and probe their own interpreter (hooks/scripts/_common.sh),
# so this harness deliberately does NOT shim a non-functional `python3` away --
# that shim used to hide the very defect the probe exists for (issue #54).
# It only refuses to run when no interpreter works at all, because then no hook
# can parse its tool input and every verdict would be meaningless.
if ! af_py=$(bash -c ". '$HOOK_DIR/_common.sh'; printf '%s' \"\$AF_PYTHON\"" 2>/dev/null) || [ -z "$af_py" ]; then
    echo "SKIP: no usable Python interpreter -- the bash hooks cannot parse tool input here."
    exit 0
fi

# run_case <name> <hook> <branch|--detach> <json> <deny|allow|ask|silent>
run_case() {
    local name="$1" hook="$2" mode="$3" json="$4" expect="$5"
    local fixture out err ok=0
    fixture=$(mktemp -d)

    mkdir -p "$fixture/.github/hooks/scripts"
    cp "$HOOK_DIR/$hook" "$fixture/.github/hooks/scripts/"
    # Hooks source the shared preamble; a deployed .github always ships it,
    # so the fixture has to as well or every hook dies before its first gate.
    cp "$HOOK_DIR/_common.sh" "$fixture/.github/hooks/scripts/"
    [ -f "$GITHUB_DIR/af-env.conf" ] && cp "$GITHUB_DIR/af-env.conf" "$fixture/.github/"

    (
        cd "$fixture" || exit 1
        git init -q .
        if [ "$mode" = "--detach" ]; then
            git -c user.email=fixture@local -c user.name=fixture \
                commit -q --allow-empty -m fixture
            git checkout -q --detach
        else
            git checkout -q -b "$mode"
        fi
        printf '%s' "$json" | bash ".github/hooks/scripts/$hook"
    ) > "$fixture/out.txt" 2> "$fixture/err.txt"

    out=$(cat "$fixture/out.txt")
    err=$(cat "$fixture/err.txt")

    case "$expect" in
        deny)   [[ "$out" == *'"deny"'*   ]] && ok=1 ;;
        allow)  [[ "$out" == *'"allow"'*  ]] && ok=1 ;;
        ask)    [[ "$out" == *'"ask"'*    ]] && ok=1 ;;
        silent) [[ "$out" == '{}'         ]] && ok=1 ;;
    esac

    if [ $ok -eq 1 ]; then
        echo "PASS  $name"
        pass=$((pass + 1))
    else
        echo "FAIL  $name -- expected $expect, got: ${out:-<no output>} ${err}"
        fail=$((fail + 1))
    fi

    rm -rf "$fixture"
}

TEST_EDIT='{"tool_name":"editFiles","tool_input":{"filePath":"tests/test_x.py"}}'
SRC_EDIT='{"tool_name":"editFiles","tool_input":{"filePath":"src/main.py"}}'
SRC_CREATE='{"tool_name":"createFile","tool_input":{"filePath":"src/new.py"}}'
FETCH_OK='{"tool_name":"fetch","tool_input":{"url":"https://docs.python.org/3/library/os.html"}}'
FETCH_UNKNOWN='{"tool_name":"fetch","tool_input":{"url":"https://unlisted.example.com/x"}}'

echo "## test-writer-pretooluse.sh"
run_case "branch gate denies on dev"            test-writer-pretooluse.sh dev           "$TEST_EDIT" deny
run_case "branch gate denies on detached HEAD"  test-writer-pretooluse.sh --detach      "$TEST_EDIT" deny
run_case "test file allowed on agent branch"    test-writer-pretooluse.sh agent/fixture "$TEST_EDIT" silent
run_case "production edit denied on agent branch" test-writer-pretooluse.sh agent/fixture "$SRC_EDIT" deny

echo "## refactorer-pretooluse.sh"
run_case "branch gate denies on dev"            refactorer-pretooluse.sh dev            "$SRC_EDIT"   deny
run_case "branch gate denies on detached HEAD"  refactorer-pretooluse.sh --detach       "$SRC_EDIT"   deny
run_case "existing file allowed on agent branch" refactorer-pretooluse.sh agent/fixture "$SRC_EDIT"   silent
run_case "file creation denied on agent branch" refactorer-pretooluse.sh agent/fixture  "$SRC_CREATE" deny

echo "## researcher-pretooluse.sh"
run_case "allowlisted domain is allowed"        researcher-pretooluse.sh agent/fixture  "$FETCH_OK"      allow
run_case "unlisted domain prompts"              researcher-pretooluse.sh agent/fixture  "$FETCH_UNKNOWN" ask

# --- Resolution invariants -------------------------------------------------
#
# run_case copies the hook into a fixture and runs it *from the fixture root*,
# so a cwd-relative config read looks correct there. These cases run from
# elsewhere, which is the shape production actually has.

assert_true() {
    local name="$1" ok="$2" detail="${3:-}"
    if [ "$ok" -eq 1 ]; then
        echo "PASS  $name"
        pass=$((pass + 1))
    else
        echo "FAIL  $name -- $detail"
        fail=$((fail + 1))
    fi
}

echo "## resolution invariants"

COMMON="$HOOK_DIR/_common.sh"
if [ -f "$COMMON" ]; then
    assert_true "shared preamble present" 1
else
    assert_true "shared preamble present" 0 "expected $COMMON"
fi

if [ -f "$COMMON" ]; then
    fx=$(mktemp -d)
    mkdir -p "$fx/.github/hooks/scripts" "$fx/docs/deep"
    cp "$COMMON" "$fx/.github/hooks/scripts/"
    printf 'SRC_DIR=lib\nBASE_BRANCH=trunk\n' > "$fx/.github/af-env.conf"
    probe="$fx/.github/hooks/scripts/probe.sh"
    cat > "$probe" <<'PROBE'
. "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
echo "found=$AF_CONF_FOUND src=$(af_conf_get SRC_DIR src) absent=$(af_conf_get NOPE fallback)"
PROBE

    elsewhere=$(mktemp -d)
    first=""
    same=1
    joined=""
    for d in "$fx" "$fx/docs/deep" "$elsewhere"; do
        out=$( (cd "$d" && bash "$probe") 2>&1 )
        joined="$joined [$out]"
        if [ -z "$first" ]; then first="$out"; elif [ "$out" != "$first" ]; then same=0; fi
    done

    assert_true "config resolves identically from every cwd" "$same" "got:$joined"
    case "$joined" in *"src=lib"*) assert_true "configured value wins over the default" 1 ;;
        *) assert_true "configured value wins over the default" 0 "got:$joined" ;; esac
    case "$joined" in *"absent=fallback"*) assert_true "absent key falls back to the default" 1 ;;
        *) assert_true "absent key falls back to the default" 0 "got:$joined" ;; esac
    case "$joined" in *"found=1"*) assert_true "config presence is reported" 1 ;;
        *) assert_true "config presence is reported" 0 "got:$joined" ;; esac

    rm -f "$fx/.github/af-env.conf"
    noconf=$( (cd "$elsewhere" && bash "$probe") 2>&1 )
    case "$noconf" in *"found=0"*"src=src"*) assert_true "missing config is distinguishable from an unset key" 1 ;;
        *) assert_true "missing config is distinguishable from an unset key" 0 "got: $noconf" ;; esac

    # An interpreter that resolves but does not run is the same defect class as
    # a config file that is not found: presence is not executability.
    stub=$(mktemp -d)
    printf '#!/bin/sh\necho "Python was not found; run without arguments to install from the Microsoft Store" >&2\nexit 9009\n' > "$stub/python3"
    chmod +x "$stub/python3"
    picked=$(PATH="$stub:$PATH" bash -c ". '$fx/.github/hooks/scripts/_common.sh'; echo \"\$AF_PYTHON\"" 2>/dev/null)
    if [ -n "$picked" ] && "$picked" -c 'print(1)' >/dev/null 2>&1; then
        assert_true "interpreter resolver rejects a stub that resolves but does not run" 1
    else
        assert_true "interpreter resolver rejects a stub that resolves but does not run" 0 "picked: [${picked:-<none>}]"
    fi

    rm -rf "$fx" "$elsewhere" "$stub"
fi

echo ""
echo "=== Summary ==="
echo "  Passed: $pass"
echo "  Failed: $fail"
if [ $fail -eq 0 ]; then
    echo "  All bash hook tests passed."
    exit 0
fi
exit 1
