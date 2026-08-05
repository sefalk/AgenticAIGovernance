#!/usr/bin/env bash
# Agent-scoped Stop hook for the coordinator agent -- post-merge worktree cleanup gate.
#
# WORKTREE CLEANUP GATE (HARD -- verifies worktree is clean before removal)
#
# Fires when the coordinator agent session ends (Stop event).
# Checks active agent/* worktrees and warns about stale (prunable) entries.
#
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

set -uo pipefail

# Root, config and interpreter come from this script's location, never from
# the cwd the agent happens to run in (issue #54).
. "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

RAW=$(cat)
[ -z "$RAW" ] && RAW='{}'

WT_DIR=$(af_conf_get WORKTREE_DIR '../wt')

# Get worktree list
wt_raw=$(git worktree list --porcelain 2>/dev/null || true)

if [ -z "$wt_raw" ]; then
    echo '{"systemMessage": "coordinator:PostMerge -- no active worktrees found, nothing to clean up"}'
    exit 0
fi

# Check for prunable stale entries
prunable_warning=""
if echo "$wt_raw" | grep -q "prunable"; then
    prunable_warning=" WARNING: prunable stale entries found -- run 'git worktree prune'."
fi

# Count and list active agent/* worktrees
if [ -z "$AF_PYTHON" ]; then
    echo '{"systemMessage": "coordinator:PostMerge -- no usable python interpreter, worktree summary skipped"}'
    exit 0
fi
# The heredoc is python's stdin, so the pipe would be discarded -- pass the
# porcelain output in the environment instead.
agent_worktrees=$(AF_WT_RAW="$wt_raw" "$AF_PYTHON" << 'PYEOF'
import os
lines = os.environ.get('AF_WT_RAW', '').splitlines()
wts = []
i = 0
while i < len(lines):
    if lines[i].startswith('worktree '):
        path = lines[i][9:].strip()
        branch = ''
        for j in range(i+1, min(i+5, len(lines))):
            if lines[j].startswith('branch '):
                branch = lines[j][7:].strip()
                break
            if lines[j] == '':
                break
        if 'refs/heads/agent/' in branch:
            wts.append(f"{path} ({branch})")
    i += 1
if wts:
    print(f"Active agent worktrees ({len(wts)}): {'; '.join(wts)}")
else:
    print("No active agent/* worktrees")
PYEOF
)

echo "{\"systemMessage\": \"coordinator:PostMerge -- ${agent_worktrees}.${prunable_warning}\"}"
exit 0
