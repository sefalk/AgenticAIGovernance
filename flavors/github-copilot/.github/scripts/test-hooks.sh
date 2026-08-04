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

# Some Windows hosts expose `python3` as a Microsoft Store execution alias:
# `command -v python3` reports a path, but running it prints an install notice
# and exits non-zero. The hooks would see that on Linux as a working
# interpreter, so shim it away rather than letting it fake a hook failure.
SHIM=""
if ! printf '{}' | python3 -c 'import sys,json; json.load(sys.stdin)' >/dev/null 2>&1; then
    if real_py=$(command -v python 2>/dev/null) && printf '{}' | "$real_py" -c 'import sys,json; json.load(sys.stdin)' >/dev/null 2>&1; then
        SHIM=$(mktemp -d)
        printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$real_py" > "$SHIM/python3"
        chmod +x "$SHIM/python3"
        export PATH="$SHIM:$PATH"
        echo "note: shimmed a non-functional python3 with $real_py"
    else
        echo "SKIP: no usable python3 -- the bash hooks cannot parse tool input here."
        exit 0
    fi
fi

# run_case <name> <hook> <branch|--detach> <json> <deny|allow|ask|silent>
run_case() {
    local name="$1" hook="$2" mode="$3" json="$4" expect="$5"
    local fixture out err ok=0
    fixture=$(mktemp -d)

    mkdir -p "$fixture/.github/hooks/scripts"
    cp "$HOOK_DIR/$hook" "$fixture/.github/hooks/scripts/"
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

[ -n "$SHIM" ] && rm -rf "$SHIM"

echo ""
echo "=== Summary ==="
echo "  Passed: $pass"
echo "  Failed: $fail"
if [ $fail -eq 0 ]; then
    echo "  All bash hook tests passed."
    exit 0
fi
exit 1
