#!/usr/bin/env bash
# Agent-scoped PreToolUse hook for the researcher agent.
#
# CREDENTIAL-URL SCAN (SOFT -- warns when fetch URLs contain embedded credentials)
#
# Fires only when the researcher agent is active.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

set -euo pipefail

RAW=$(cat)
[ -z "$RAW" ] && echo '{}' && exit 0

TOOL_NAME=$(echo "$RAW" | python3 -c "
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

URL=$(echo "$RAW" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', {})
    print(ti.get('url', ti.get('uri', '')))
except Exception:
    print('')
" 2>/dev/null)

[ -z "$URL" ] && echo '{}' && exit 0

# Check for credential patterns
FINDINGS=""
if echo "$URL" | grep -qE '://[^/@]+:[^/@]+@'; then
    FINDINGS="Basic auth"
fi
if echo "$URL" | grep -qiE '[?&](token|access_token|api_key|apikey|auth|key|secret|password)='; then
    FINDINGS="${FINDINGS:+$FINDINGS, }Token query param"
fi
if echo "$URL" | grep -qiE '[?&]Authorization='; then
    FINDINGS="${FINDINGS:+$FINDINGS, }Authorization query param"
fi
if echo "$URL" | grep -qE '#(access_token|token)='; then
    FINDINGS="${FINDINGS:+$FINDINGS, }Credential fragment"
fi

if [ -n "$FINDINGS" ]; then
    # Sanitize URL for display
    SANITIZED=$(echo "$URL" | sed -E 's|://([^/@]+):([^/@]+)@|://***:***@|g; s|([?&])(token|access_token|api_key|apikey|auth|key|secret|password)=[^&]*|\1\2=***|gI')
    # Build a warning note; do NOT short-circuit to allow here -- a credentialed
    # URL to a non-allowlisted domain must still go through the prompt below.
    CRED_NOTE=" WARNING: URL contains embedded credentials ($FINDINGS). Strip them from your research brief output. Sanitized URL: $SANITIZED"
else
    CRED_NOTE=""
fi

# --- Domain allowlist: auto-approve official docs; prompt (with seed-add offer) otherwise ---
REPO=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
ALLOW=""
if [ -n "$REPO" ] && [ -f "$REPO/.github/af-env.conf" ]; then
    ALLOW=$(grep -E '^[[:space:]]*WEB_FETCH_ALLOWLIST=' "$REPO/.github/af-env.conf" 2>/dev/null | head -n1 | sed -E 's/^[[:space:]]*WEB_FETCH_ALLOWLIST=//')
fi

FETCH_HOST=$(echo "$URL" | sed -E 's|^[a-zA-Z][a-zA-Z0-9+.-]*://([^/:?#]+).*|\1|' | tr '[:upper:]' '[:lower:]')

if [ -n "$FETCH_HOST" ] && echo "$URL" | grep -qE '://'; then
    MATCHED=0
    OLD_IFS="$IFS"; IFS=','
    for d in $ALLOW; do
        d=$(echo "$d" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | tr '[:upper:]' '[:lower:]')
        [ -z "$d" ] && continue
        if [ "$FETCH_HOST" = "$d" ] || echo "$FETCH_HOST" | grep -qE "\.$(echo "$d" | sed 's/\./\\./g')$"; then
            MATCHED=1
            break
        fi
    done
    IFS="$OLD_IFS"

    if [ "$MATCHED" -eq 1 ]; then
        cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Allowlisted documentation domain.$CRED_NOTE"}}
EOF
        exit 0
    fi

    cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Domain '$FETCH_HOST' is not in WEB_FETCH_ALLOWLIST. Approve to fetch once. To auto-approve this domain in future, add '$FETCH_HOST' to WEB_FETCH_ALLOWLIST in .github/af-env.conf (the agent can do this on your confirmation).$CRED_NOTE"}}
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
