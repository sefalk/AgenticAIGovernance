#!/usr/bin/env bash
# Agent-scoped Stop hook for the documenter agent.
#
# DOCUMENTATION ARTIFACT GATE (HARD — blocks documenter if required artifacts missing)
#
# Verifies the documenter has produced the required workflow artifacts:
#   1. YAML workflow log in .github/logs/{workflow-id}.yaml
#   2. Retro snippet in retros/auto/{workflow-id}.md or .github/retros/auto/
#
# Fires as SubagentStop when the documenter is invoked by the coordinator.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

set -uo pipefail

# Read stdin (hook input JSON — required by protocol).
# It carries session_id and transcript_path, which is how the cost block below
# locates the debug log; both name the PARENT session even inside a subagent
# (measured 2026-08-03), so no session has to be guessed.
stdin_raw=$(cat)

# Derive workflow-id from current branch
branch=$(git branch --show-current 2>/dev/null || echo "")
if [[ ! "$branch" =~ ^agent/(.+)$ ]]; then
    echo '{"systemMessage": "documenter:Stop — not on agent/ branch, artifact gate skipped"}'
    exit 0
fi

workflow_id="${BASH_REMATCH[1]}"
missing=()

BASE_BRANCH="dev"
if [ -f ".github/af-env.conf" ]; then
    conf_base=$(grep -E '^BASE_BRANCH=' .github/af-env.conf 2>/dev/null | head -1 | cut -d= -f2- | tr -d '[:space:]')
    [ -n "$conf_base" ] && BASE_BRANCH="$conf_base"
fi

# ---------- Gate 1: Workflow log YAML ----------

if [ ! -f ".github/logs/${workflow_id}.yaml" ] && [ ! -f ".github/logs/${workflow_id}.yml" ]; then
    missing+=("workflow log (.github/logs/${workflow_id}.yaml)")
fi

# ---------- Gate 2: Retro snippet ----------

# Canonical location is .github/retros/auto/; the bare path is accepted for
# projects that adopted it before the location was settled.
if [ ! -f ".github/retros/auto/${workflow_id}.md" ] && [ ! -f "retros/auto/${workflow_id}.md" ]; then
    missing+=("retro snippet (.github/retros/auto/${workflow_id}.md)")
fi

# ---------- Verdict ----------

if [ ${#missing[@]} -gt 0 ]; then
    list=$(IFS='; '; echo "${missing[*]}")
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"Stop\", \"decision\": \"block\", \"reason\": \"Documentation phase violation: required artifacts missing for workflow '${workflow_id}': ${list}. Create these files before completing.\"}}"
    exit 0
fi

# ---------- Cost block (ADVISORY — never blocks, never fails the hook) ----------
#
# Appended here rather than written by the documenter so the numbers never pass
# through a language model. A vendor setting being off is not a framework
# failure, so every path below degrades silently.

cost_note=""
log_path=".github/logs/${workflow_id}.yaml"
[ -f "$log_path" ] || log_path=".github/logs/${workflow_id}.yml"

# Appending twice would produce a duplicate YAML key; first write wins.
if ! grep -q '^cost:' "$log_path" 2>/dev/null; then
    sid=$(printf '%s' "$stdin_raw" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    transcript=$(printf '%s' "$stdin_raw" | grep -o '"transcript_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')

    if [ -n "$sid" ] && [ -n "$transcript" ]; then
        # <ws>/GitHub.copilot-chat/transcripts/<sid>.jsonl -> .../debug-logs/<sid>
        chat_dir=$(dirname "$(dirname "$transcript")")
        session_dir="${chat_dir}/debug-logs/${sid}"

        collector=".github/scripts/collect-session-cost.py"
        python_exe=""
        for c in .venv/bin/python .venv/Scripts/python.exe; do
            [ -x "$c" ] && python_exe="$c" && break
        done
        if [ -z "$python_exe" ]; then
            for n in python3 python; do
                command -v "$n" >/dev/null 2>&1 && python_exe="$n" && break
            done
        fi

        if [ -n "$python_exe" ] && [ -f "$collector" ]; then
            # Oldest commit on the branch approximates the workflow start;
            # a session that began later means earlier phases are unlogged.
            args=(--session-dir "$session_dir")
            oldest=$(git log --format=%ct "${BASE_BRANCH}..HEAD" 2>/dev/null | tail -1)
            if [ -n "$oldest" ]; then
                args+=(--workflow-start "$((oldest * 1000))")
            fi

            if block=$("$python_exe" "$collector" "${args[@]}" 2>/dev/null) && [ -n "$block" ]; then
                printf '\n%s\n' "$block" >> "$log_path"
                cost_note=" + cost block appended"
            fi
        fi
    fi
fi

echo "{\"systemMessage\": \"documenter:Stop — artifact gate PASS: workflow log and retro snippet exist for '${workflow_id}'${cost_note}\"}"
exit 0
