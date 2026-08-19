#!/usr/bin/env bash
# Agent-scoped PreToolUse hook for the researcher agent.
#
# CREDENTIAL-URL SCAN (SOFT -- warns when fetch URLs contain embedded credentials)
#
# Fires only when the researcher agent is active.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

set -euo pipefail

# Root, config and interpreter come from this script's location, never from
# the cwd the agent happens to run in (issue #54).
. "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

RAW=$(cat)
# `A && B && exit` returns 1 when A is false, which under `set -e` aborts the
# hook instead of falling through. Explicit `if` blocks do not.
if [ -z "$RAW" ]; then echo '{}'; exit 0; fi
if [ -z "$AF_PYTHON" ]; then echo '{}'; exit 0; fi

TOOL_NAME=$(echo "$RAW" | "$AF_PYTHON" -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_name', d.get('toolName', '')))
except Exception:
    print('')
" 2>/dev/null)

# Only inspect fetch tool calls
case "$TOOL_NAME" in
    *fetch*|*Fetch*) ;;
    *) echo '{}'; exit 0 ;;
esac

# VS Code's fetch tool sends `urls` -- an array, beside `query`. The single
# `url`/`uri` string this hook was written against is a legacy shape, so both
# are read and every entry is examined (issue #64).
URLS=$(echo "$RAW" | "$AF_PYTHON" -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', {})
    raw = ti.get('urls') or []
    if isinstance(raw, str):
        raw = [raw]
    for key in ('url', 'uri'):
        v = ti.get(key)
        if v:
            raw.append(v)
    for u in raw:
        u = str(u).strip()
        if u:
            print(u)
except Exception:
    pass
" 2>/dev/null)

if [ -z "$URLS" ]; then echo '{}'; exit 0; fi

json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

scan_credentials() {
    local url="$1" found=""
    if echo "$url" | grep -qE '://[^/@]+:[^/@]+@'; then
        found="Basic auth"
    fi
    if echo "$url" | grep -qiE '[?&](token|access_token|api_key|apikey|auth|key|secret|password)='; then
        found="${found:+$found, }Token query param"
    fi
    if echo "$url" | grep -qiE '[?&]Authorization='; then
        found="${found:+$found, }Authorization query param"
    fi
    if echo "$url" | grep -qE '#(access_token|token)='; then
        found="${found:+$found, }Credential fragment"
    fi
    printf '%s' "$found"
}

# `#` as the s-delimiter: `|` was both the delimiter and the alternation in the
# same expression, so sed aborted the hook on exactly the URLs it exists for.
sanitize_url() {
    printf '%s' "$1" | sed -E 's#://([^/@]+):([^/@]+)@#://***:***@#g; s#([?&])(token|access_token|api_key|apikey|auth|key|secret|password)=[^&]*#\1\2=***#gI'
}

# The host is what follows the last `@` in the authority. Stopping at the first
# `:` reads the userinfo instead, so `https://docs.python.org:x@evil/` would
# pass the allowlist as `docs.python.org`.
url_host() {
    printf '%s' "$1" \
        | sed -E 's|^[a-zA-Z][a-zA-Z0-9+.-]*://||; s|[/?#].*$||; s|^.*@||; s|:[0-9]*$||' \
        | tr '[:upper:]' '[:lower:]'
}

# The config is resolved by the shared preamble. `git rev-parse --show-toplevel`
# misses whenever .github/ is not at the repo top level, and an unread
# allowlist is indistinguishable from an empty one.
CONF="$AF_CONF"
CONF_FOUND="$AF_CONF_FOUND"
ALLOW=$(af_conf_get WEB_FETCH_ALLOWLIST '')

host_allowlisted() {
    local h="$1" d old_ifs="$IFS"
    IFS=','
    for d in $ALLOW; do
        d=$(printf '%s' "$d" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | tr '[:upper:]' '[:lower:]')
        [ -z "$d" ] && continue
        if [ "$h" = "$d" ] || printf '%s' "$h" | grep -qE "\.$(printf '%s' "$d" | sed 's/\./\\./g')$"; then
            IFS="$old_ifs"
            return 0
        fi
    done
    IFS="$old_ifs"
    return 1
}

FINDINGS=""
UNLISTED=""
MATCHED_ANY=0
# Heredoc, not a pipe: a `while read` on the right of a pipe runs in a subshell
# and every variable set below would be discarded at the loop's end.
while IFS= read -r u; do
    [ -z "$u" ] && continue

    found=$(scan_credentials "$u")
    if [ -n "$found" ]; then
        FINDINGS="${FINDINGS:+$FINDINGS; }$found in $(sanitize_url "$u")"
    fi

    fetch_host=$(url_host "$u")
    if [ -z "$fetch_host" ] || ! echo "$u" | grep -qE '://'; then
        continue
    fi
    if host_allowlisted "$fetch_host"; then
        MATCHED_ANY=1
    else
        UNLISTED="${UNLISTED:+$UNLISTED, }$fetch_host"
    fi
done <<EOF
$URLS
EOF

if [ -n "$FINDINGS" ]; then
    # Build a warning note; do NOT short-circuit to allow here -- a credentialed
    # URL to a non-allowlisted domain must still go through the prompt below.
    CRED_NOTE=" WARNING: URL contains embedded credentials ($(json_escape "$FINDINGS")). Strip them from your research brief output."
else
    CRED_NOTE=""
fi

# --- Domain allowlist: auto-approve official docs; prompt (with seed-add offer) otherwise ---
# One unlisted entry decides the batch: the tool fetches every URL in the
# array, so approving on the first match would wave the rest through unseen.
if [ -n "$UNLISTED" ]; then
    if [ "$CONF_FOUND" -eq 1 ]; then
        WHY="Not in WEB_FETCH_ALLOWLIST: $(json_escape "$UNLISTED")."
    else
        WHY="No allowlist available: .github/af-env.conf was not found at $(json_escape "$CONF")."
    fi
    cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"$WHY Approve to fetch once. To auto-approve in future, add the domain to WEB_FETCH_ALLOWLIST in .github/af-env.conf (the agent can do this on your confirmation).$CRED_NOTE"}}
EOF
    exit 0
fi

if [ "$MATCHED_ANY" -eq 1 ]; then
    cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Allowlisted documentation domain.$CRED_NOTE"}}
EOF
    exit 0
fi

# No parseable host: keep the fetch flowing but surface any credential warning.
if [ -n "$CRED_NOTE" ]; then
    cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"URL fetch.$CRED_NOTE"}}
EOF
    exit 0
fi

echo '{}'
exit 0
