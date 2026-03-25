#!/usr/bin/env bash
# copilot:generated | implementer | 2026-03-17
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

    cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"WARNING: URL contains embedded credentials ($FINDINGS). Ensure credentials are stripped from your research brief output. Sanitized URL: $SANITIZED"}}
EOF
    exit 0
fi

echo '{}'
exit 0
