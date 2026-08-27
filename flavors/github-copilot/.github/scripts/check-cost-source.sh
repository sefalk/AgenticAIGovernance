#!/usr/bin/env bash
# check-cost-source.sh -- report whether the cost-tracking data source is live.
#
# POSIX twin of check-cost-source.ps1. Keep the wording of both in sync.
#
# The `cost:` block in a workflow log is only as good as its source: VS Code's
# agent debug log. When that is switched off the collector correctly records
# `available: false`, but that lands in a YAML file nobody opens unless they
# already suspect a problem (AAIG issue #228).
#
# The probe measures the EFFECT, not the configuration: it counts session logs
# on disk. Reading the setting itself is unreliable -- it may sit in user,
# workspace, or profile settings, and those files are JSONC, which no JSON
# parser accepts.
#
# ADVISORY ONLY. This always exits 0. The setting is experiment-flagged and
# vendor-controlled, so nothing in the framework may gate on it.

SETTING='github.copilot.chat.agentDebugLog.fileLogging.enabled'
BRIEF=false
USER_DIRS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user-dir)
            USER_DIRS+=("$2")
            shift 2
            ;;
        --brief)
            BRIEF=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

if [[ ${#USER_DIRS[@]} -eq 0 ]]; then
    for root in "$HOME/Library/Application Support" "$HOME/.config" "$APPDATA"; do
        [[ -n "$root" ]] || continue
        for variant in "Code" "Code - Insiders"; do
            [[ -d "$root/$variant/User" ]] && USER_DIRS+=("$root/$variant/User")
        done
    done
fi

sessions=0
for dir in "${USER_DIRS[@]}"; do
    found=$(find "$dir/workspaceStorage" -type f -name 'main.jsonl' \
        -path '*/GitHub.copilot-chat/debug-logs/*' 2>/dev/null | wc -l)
    sessions=$((sessions + found))
done

if [[ "$BRIEF" != "true" ]]; then
    echo "=== Cost Tracking Source ==="
fi

if [[ "$sessions" -gt 0 ]]; then
    echo "  OK: agent debug logging is producing session logs ($sessions found)."
    exit 0
fi

# Naming the searched locations keeps the advisory falsifiable: a portable or
# relocated VS Code install is a false alarm the consumer can recognise.
if [[ ${#USER_DIRS[@]} -eq 0 ]]; then
    where='(no VS Code user directory found)'
else
    where=$(printf '%s; ' "${USER_DIRS[@]}")
    where=${where%; }
fi

echo "  ADVISORY: no agent debug logs found -- workflow cost blocks will be empty."
echo "    Searched: $where"
echo "    Enable the VS Code setting: $SETTING"
echo "    While it is off, every workflow log records 'cost: available: false'"
echo "    and no token or credit figures can be reconciled."
echo "    The setting is experiment-flagged and vendor-controlled; it may be"
echo "    withdrawn. Nothing gates on it -- this notice is advisory only."

exit 0
