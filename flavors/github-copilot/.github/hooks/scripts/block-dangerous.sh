#!/usr/bin/env bash
# PreToolUse hook: three-tier terminal command classifier (allow / ask / deny).
# copilot:modified | implementer | 2026-07-01 | 3-tier branch-aware autonomy classifier
#
# Tiers: deny (hard-block), allow (auto-approve safe), ask (confirm durable
# change), {} (defer to user settings -- fail-safe default).

PYTHON=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "")

raw=$(cat)

if [ -z "$PYTHON" ]; then
    echo '{}'
    exit 0
fi

tool_name=$(echo "$raw" | "$PYTHON" -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

case "$tool_name" in
    *terminal*|*Terminal*) ;;
    *) echo '{}'; exit 0 ;;
esac

command_str=$(echo "$raw" | "$PYTHON" -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

if [ -z "$command_str" ]; then
    echo '{}'
    exit 0
fi

# --- Load autonomy config from .github/af-env.conf ---
repo=$(git rev-parse --show-toplevel 2>/dev/null)
conf="$repo/.github/af-env.conf"
get_af_env() {
    # $1 = key, $2 = default
    local val=""
    if [ -f "$conf" ]; then
        val=$(grep -E "^[[:space:]]*$1=" "$conf" 2>/dev/null | head -n1 | sed -E "s/^[[:space:]]*$1=//")
        val=$(echo "$val" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    fi
    if [ -z "$val" ]; then echo "$2"; else echo "$val"; fi
}

level=$(get_af_env AUTONOMY_LEVEL balanced | tr '[:upper:]' '[:lower:]')
case "$level" in conservative|balanced|autonomous) ;; *) level=balanced ;; esac
protected=$(get_af_env PROTECTED_BRANCHES 'main,master,dev')
prot_alt=$(echo "$protected" | sed -E 's/[[:space:]]//g; s/,/|/g')
[ -z "$prot_alt" ] && prot_alt='main|master|dev'
cur_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
# Optional executable path prefix (.venv/bin/, .venv\Scripts\, ./, /usr/bin/) and .exe suffix.
path_pfx='(\S*[\\/])?'
exe='(\.exe)?'

# category resolver: override wins, else level default
cat_default() {
    # $1 = category name
    case "$level" in
        conservative)
            case "$1" in git_read|fs_read) echo auto ;; *) echo ask ;; esac ;;
        autonomous)
            case "$1" in git_read|fs_read|tests|git_feature|pkg|cloud_read) echo auto ;; *) echo ask ;; esac ;;
        *) # balanced
            case "$1" in git_read|fs_read|tests|git_feature|cloud_read) echo auto ;; *) echo ask ;; esac ;;
    esac
}
resolve_cat() {
    # $1 = category name, $2 = env key
    local ov
    ov=$(get_af_env "$2" "" | tr '[:upper:]' '[:lower:]')
    if [ -n "$ov" ]; then echo "$ov"; else cat_default "$1"; fi
}
cat_git_read=$(resolve_cat git_read AUTONOMY_CAT_GIT_READ)
cat_git_feature=$(resolve_cat git_feature AUTONOMY_CAT_GIT_FEATURE)
cat_tests=$(resolve_cat tests AUTONOMY_CAT_TESTS)
cat_fs_read=$(resolve_cat fs_read AUTONOMY_CAT_FS_READ)
cat_pkg=$(resolve_cat pkg AUTONOMY_CAT_PKG_INSTALL)
cat_databricks=$(resolve_cat databricks AUTONOMY_CAT_DATABRICKS)
cat_cloud_read=$(resolve_cat cloud_read AUTONOMY_CAT_CLOUD_READ)

emit() {
    # $1 = decision, $2 = reason
    cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"$1","permissionDecisionReason":"$2"}}
EOF
    exit 0
}

matches() { echo "$command_str" | grep -qEi "$1"; }

# ===================== TIER 1 -- DENY (hard) =====================
deny_msg="Policy hard-deny. The agent will not run this. If genuinely required, either (a) run it yourself -- the agent can prepare the exact command for you to paste and execute -- or (b) make a conscious decision to relax the autonomy policy in .github/af-env.conf."
deny_patterns=(
    'git\s+push\b.*(--force|-f)\b'
    "git\s+push\b.*(\s|:)($prot_alt)(\s|$)"
    'git\s+reset\s+--hard'
    'git\s+rebase\b'
    'git\s+branch\s+-[dD]\b'
    'git\s+add\s+(\S+\s+)*(--force|-f)(\s|$)'
    'git\s+add\s+(-\S+\s+)*\.(\s|$)'
    'git\s+add\s+(\S+\s+)*-A(\s|$)'
    '--no-verify'
    'rm\s+-r[f ].*(\s|=)(/|~|\*)'
    'Remove-Item.*-Recurse.*-Force'
    'dd\s+if=.*of=/dev/'
    'mkfs\.'
    'format\s+[A-Za-z]:'
    'chmod\s+-R\s+777'
    '\|\s*(bash|sh|iex|Invoke-Expression)\b'
    'DROP\s+(TABLE|DATABASE)'
    'TRUNCATE\s+TABLE'
)
for p in "${deny_patterns[@]}"; do
    if matches "$p"; then emit deny "$deny_msg"; fi
done
# Category-scoped deny (when autonomy policy sets a category to 'deny').
if [ "$cat_pkg" = "deny" ] && matches '\bpip3?\s+(install|uninstall)\b|\bconda\s+(install|remove)\b'; then
    emit deny "$deny_msg"
fi
if [ "$cat_databricks" = "deny" ] && matches '\bdatabricks\b'; then
    emit deny "$deny_msg"
fi

# ===================== TIER 2 -- ALLOW (segment-based) =====================
# The command is split into segments on ; && || | and auto-approved only when
# EVERY segment is individually safe. This lets common composites through
# (e.g. `cd ... ; pytest ... 2>&1 | Select-Object -Last 30`). DENY already
# scanned the whole string, so hidden dangerous segments are blocked above.
# Command substitution ($( ) / backticks) and file-write redirects (> file)
# are never auto-allowed.
sm() { printf '%s' "$SEG" | grep -qEi "$1"; }
is_safe_segment() {
    SEG="$(printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -z "$SEG" ] && return 0
    # file-write redirect (excludes fd duplication like 2>&1, >&1)
    if printf '%s' "$SEG" | grep -qE '>>?[[:space:]]*[^&[:space:]>]'; then return 1; fi
    # background / inline chaining operator ( & ) not handled by the split
    # ( & is not split on because it also appears in fd redirects like 2>&1 )
    if printf '%s' "$SEG" | grep -qE '(^|[^0-9>&])&([^&]|$)'; then return 1; fi
    sm '^(cd|Set-Location|pushd|popd|Push-Location|Pop-Location)\b' && return 0
    sm '^(Select-Object|Select-String|Sort-Object|Measure-Object|Out-String|Out-Host|Format-Table|Format-List|Get-Unique|more|wc|findstr|grep|ConvertFrom-Json|ConvertTo-Json)\b' && return 0
    sm '^[[:space:]]*[[:alnum:]._/-]+([[:space:]]+-{1,2}[[:alnum:]=.,_-]+)*[[:space:]]+--version\b' && return 0
    if [ "$cat_git_read" = "auto" ]; then
        sm '^\s*git\s+(status|diff|log|show|rev-parse|rev-list|remote|blame|describe|shortlog|for-each-ref|ls-files|config\s+--get|fetch)\b' && return 0
        sm '^\s*git\s+stash\s+list\b' && return 0
        if sm '^\s*git\s+branch\b' && ! sm '\s-[dDmMcC]\b' && ! sm '--(delete|move|copy|force)\b'; then return 0; fi
        if sm '^\s*git\s+tag\b' && ! sm '\s-[adfsm]\b' && ! sm '--(delete|force|sign|annotate)\b' && ! sm '^\s*git\s+tag\s+[^\s-]'; then return 0; fi
    fi
    if [ "$cat_git_feature" = "auto" ]; then
        sm '^\s*git\s+commit\b' && return 0
        sm '^\s*git\s+add\s+\S' && return 0
        sm '^\s*git\s+(checkout|switch)\s+-[bc]\s+agent/' && return 0
        sm '^\s*git\s+(checkout|switch)\s+agent/' && return 0
        # switch to a branch (never touches files, so always safe)
        sm '^[[:space:]]*git[[:space:]]+switch[[:space:]]+[[:alnum:]_./-]+[[:space:]]*$' && return 0
        # checkout an existing ref (branch/tag/commit) -- verified so a file
        # pathspec (which would discard changes) is NOT auto-approved
        if printf '%s' "$SEG" | grep -qE '^[[:space:]]*git[[:space:]]+checkout[[:space:]]+[[:alnum:]_./-]+[[:space:]]*$'; then
            ref=$(printf '%s' "$SEG" | sed -E 's/^[[:space:]]*git[[:space:]]+checkout[[:space:]]+([[:alnum:]_./-]+)[[:space:]]*$/\1/')
            if git rev-parse --verify --quiet "${ref}^{commit}" >/dev/null 2>&1; then return 0; fi
        fi
        if sm '^\s*git\s+push\b' && ! sm "(\s|:)($prot_alt)(\s|$)"; then
            if sm 'agent/'; then return 0; fi
            if [ -n "$cur_branch" ] && ! echo "$cur_branch" | grep -qxE "$prot_alt"; then return 0; fi
        fi
        sm '^\s*git\s+(restore|switch\s+agent/)\b' && return 0
    fi
    if [ "$cat_tests" = "auto" ]; then
        sm "^\s*${path_pfx}(pytest|mypy|pyright|tox|nox|radon|bandit|flake8|pylint|vulture|pip-audit)${exe}\b" && return 0
        sm "^\s*${path_pfx}python([0-9])?${exe}\s+-m\s+(pytest|mypy|pyright)\b" && return 0
        sm "^\s*${path_pfx}ruff${exe}\s+(check|format\s+--check)\b" && return 0
        sm 'run-tests' && return 0
    fi
    if [ "$cat_fs_read" = "auto" ]; then
        sm '^\s*(ls|dir|Get-ChildItem|cat|type|Get-Content|head|tail|Test-Path|pwd|Get-Location|where(\.exe)?|Get-Command|Get-Date|whoami|hostname|Get-Process|Get-Service|echo|Write-Output|Write-Host)\b' && return 0
        sm "^\s*${path_pfx}pip3?${exe}\s+(list|show|freeze|check)\b" && return 0
        sm '^\s*python([0-9])?\s+-m\s+pip\s+(list|show|freeze|check)\b' && return 0
    fi
    if [ "$cat_pkg" = "auto" ]; then
        sm "^\s*${path_pfx}pip3?${exe}\s+(install|uninstall)\b" && return 0
        sm '^\s*python([0-9])?\s+-m\s+pip\s+(install|uninstall)\b' && return 0
        sm "^\s*${path_pfx}conda${exe}\s+(install|remove)\b" && return 0
    fi
    if [ "$cat_cloud_read" = "auto" ]; then
        # read-only cloud CLI; exclude anything touching secrets/credentials/tokens
        if ! printf '%s' "$SEG" | grep -qiE '(secret|credential|token|password|keyvault|get-access-token)'; then
            sm '^\s*databricks\s+[[:alnum:]_-]+\s+(list|get|ls|show)\b' && return 0
            sm '^\s*az\s+.+\b(show|list)\b' && return 0
        fi
    fi
    if [ "$cat_databricks" = "auto" ]; then
        sm '^\s*databricks\b' && return 0
    fi
    return 1
}

# Suppress auto-allow when the command uses grouping / subexpression /
# scriptblock metacharacters OUTSIDE quotes -- e.g. bash `(cmd)` runs a subshell
# and `Write-Host (Remove-Item x)` executes the inner command. Quote-strip first
# so conventional-commit messages like "fix(scope): ..." are not falsely blocked.
stripped_guard=$(printf '%s' "$command_str" | sed -E 's/"[^"]*"//g' | sed -E "s/'[^']*'//g")
if ! printf '%s' "$stripped_guard" | grep -qE '[`({]'; then
    seg_lines=$(printf '%s' "$command_str" | sed -E 's/\|\||&&|;/\n/g' | sed -E 's/\|/\n/g')
    any=0; allsafe=1
    while IFS= read -r seg; do
        [ -z "$(printf '%s' "$seg" | tr -d '[:space:]')" ] && continue
        any=1
        if ! is_safe_segment "$seg"; then allsafe=0; break; fi
    done <<SEGEOF
$seg_lines
SEGEOF
    if [ "$any" -eq 1 ] && [ "$allsafe" -eq 1 ]; then
        emit allow 'Safe: every command segment is read-only or a known-safe operation.'
    fi
fi

# ===================== TIER 3 -- ASK (durable change) =====================
ask_patterns=(
    'git\s+merge\b'
    'git\s+(checkout|switch)\b'
    'git\s+tag\b'
    '\bpip3?\s+(install|uninstall)\b'
    '\bconda\s+(install|remove)\b'
    '\bruff\s+format\b'
    '\bdatabricks\b.*\b(submit|run|create|update|delete|import|export|deploy)\b'
    '\baz\b.*\b(create|set|delete|update|deploy)\b'
    'Remove-Item\b'
    '(^|\s)rm\b'
    '(Move-Item|Copy-Item|New-Item|mkdir|mv|cp)\b'
)
for p in "${ask_patterns[@]}"; do
    if matches "$p"; then
        emit ask 'This command makes a durable change. Please confirm it is intentional.'
    fi
done

echo '{}'
