#!/usr/bin/env bash
# Global Stop / SubagentStop hook: refresh the session cost store (issue #457).
#
# The chat debug log loses its head at a moment nobody controls, so the cost
# rows are read out as often as the session offers a chance: after every turn
# and every subagent. The collector reads only what the logs gained since its
# last run (see logs/README.md, "The session store").
#
# It runs in the background and this hook answers {} at once: no turn waits for
# it, and it never decides anything. AF_COST_SNAPSHOT_SYNC=1 runs it in the
# foreground so a test can read the store it wrote.

set -uo pipefail

. "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

raw=$(cat)

if [ -n "$AF_PYTHON" ]; then
    # Prints the session log directory, or nothing. The session id becomes a
    # directory and file name; one carrying a path must not.
    session_dir=$(printf '%s' "$raw" | "$AF_PYTHON" -c '
import json, os, re, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
sid = str(data.get("session_id") or "")
transcript = str(data.get("transcript_path") or "")
if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", sid) or not transcript:
    sys.exit(0)
chat = os.path.dirname(os.path.dirname(transcript))
# Joined with "/" so a POSIX path stays one under a Windows interpreter.
print(chat.rstrip("/\\") + "/debug-logs/" + sid)
' 2>/dev/null)
    collector="$AF_MAIN_ROOT/.github/scripts/collect-session-cost.py"
    store="$AF_MAIN_ROOT/.github/logs/cost/sessions"
    if [ -n "$session_dir" ] && [ -d "$session_dir" ] && [ -f "$collector" ]; then
        if [ -n "${AF_COST_SNAPSHOT_SYNC:-}" ]; then
            "$AF_PYTHON" "$collector" --session-dir "$session_dir" --store "$store" --snapshot >/dev/null 2>&1
        else
            nohup "$AF_PYTHON" "$collector" --session-dir "$session_dir" --store "$store" --snapshot >/dev/null 2>&1 &
        fi
    fi
fi

echo '{}'
exit 0
