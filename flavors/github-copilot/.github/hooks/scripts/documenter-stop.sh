#!/usr/bin/env bash
# Agent-scoped Stop hook for the documenter agent.
#
# DOCUMENTATION ARTIFACT GATE (HARD — blocks documenter FINALISATION if
# required artifacts are missing)
#
# Verifies the documenter has produced the required workflow artifacts:
#   1. YAML workflow log in .github/logs/{workflow-id}.yaml
#   2. Retro snippet in .github/retros/auto/{workflow-id}.md -- but only when
#      the workflow log shows there was something to learn (issue #27)
#
# The gate applies only to finalisation, which is recognised by the plan file
# being marked COMPLETED. A mid-workflow documenter call (plan persistence,
# Step 1 of Full TDD) terminates without these artifacts — see Gate 0.
#
# Fires as SubagentStop when the documenter is invoked by the coordinator.
# Requires chat.useCustomAgentHooks = true in .vscode/settings.json.

set -uo pipefail

# Root, config and interpreter come from this script's location, never from
# the cwd the agent happens to run in (issue #54).
. "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
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

BASE_BRANCH=$(af_conf_get BASE_BRANCH dev)

# ---------- Gate 0: Which lifecycle is this? ----------
#
# The documenter has two chartered jobs: persist plan files mid-workflow, and
# finalise at the end. This gate used to fire on both, so a mid-workflow call
# could only terminate by inventing a COMPLETED workflow log and retro for a
# workflow still running — the hook mechanically compelled the false artifact
# it existed to guarantee (issue #72).
#
# Intent is not on stdin, so it is read off the plan file: a plan marked
# COMPLETED is the documenter's own claim that it finalised, and that claim is
# what this gate holds it to.

plan_info=$(af_plan_lifecycle "$workflow_id" "$AF_CODE_ROOT")
plan_found="${plan_info%%|*}"
plan_rest="${plan_info#*|}"
plan_status="${plan_rest%%|*}"

if [ "$plan_found" != "1" ]; then
    # Unclassifiable is not the same as fine, and saying nothing would repeat
    # the defect this gate is meant to prevent. Completeness is still enforced
    # once, by the compliance-checker post-flight gate.
    echo "{\"systemMessage\": \"documenter:Stop — no plan file names 'agent/${workflow_id}', so a mid-workflow call cannot be told from finalisation; artifact gate not applied. Completeness is enforced by the compliance-checker post-flight gate.\"}"
    exit 0
fi

if [ "$plan_status" != "COMPLETED" ]; then
    echo "{\"systemMessage\": \"documenter:Stop — plan status is ${plan_status:-unset}, not COMPLETED: treated as a mid-workflow documenter call, artifact gate not applied.\"}"
    exit 0
fi

# ---------- Gate 1: Workflow log YAML ----------

if [ ! -f ".github/logs/${workflow_id}.yaml" ] && [ ! -f ".github/logs/${workflow_id}.yml" ]; then
    missing+=("workflow log (.github/logs/${workflow_id}.yaml)")
fi

# ---------- Gate 2: Retro snippet ----------
#
# One destination. The bare root path used to be accepted too, which did not
# resolve the ambiguity but preserved it: a documenter writing to the wrong
# place was indistinguishable from one writing to the right place (issue #98).
# A legacy file is named rather than silently ignored.
#
# Whether a retro is owed at all is decided from the log, not from the
# documenter's account of its own run (issue #27).

retro_note=""
if [ ! -f ".github/retros/auto/${workflow_id}.md" ]; then
    retro_verdict=$(af_retro_required "$workflow_id")
    retro_reason="${retro_verdict#*|}"
    if [ "${retro_verdict%%|*}" = "1" ]; then
        if [ -f "retros/auto/${workflow_id}.md" ]; then
            missing+=("retro snippet at its canonical path -- found 'retros/auto/${workflow_id}.md', which is no longer accepted; move it to .github/retros/auto/${workflow_id}.md")
        else
            missing+=("retro snippet (.github/retros/auto/${workflow_id}.md), required because ${retro_reason}")
        fi
    else
        retro_note=" -- no retro required (${retro_reason})"
    fi
fi

# ---------- Verdict ----------

if [ ${#missing[@]} -gt 0 ]; then
    list=$(IFS='; '; echo "${missing[*]}")
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"Stop\", \"decision\": \"block\", \"reason\": \"Documentation phase violation: required artifacts missing for workflow '${workflow_id}': ${list}. Create these files before completing.\"}}"
    exit 0
fi

# ---------- Timestamps (ADVISORY — never blocks, never fails the hook) ----------
#
# Stamped here rather than written by the documenter so the values never pass
# through a language model. Measured: a documenter wrote a `completed:` six and
# a half hours into the future, in the same output that declared "zero
# fabricated data" — and every gate downstream accepted it, because they check
# that the field is present, and an invented value is present (issue #91).
#
# `completed:` is now: this hook fires when the documenter finishes. `started:`
# is the branch's oldest commit, the same approximation the cost collector
# already uses for --workflow-start. Anything the documenter left behind is
# replaced rather than joined — two `completed:` keys is a YAML file whose
# meaning depends on which one the parser reaches last.

stamp_note=""
log_path=".github/logs/${workflow_id}.yaml"
[ -f "$log_path" ] || log_path=".github/logs/${workflow_id}.yml"

if [ -f "$log_path" ]; then
    completed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    started_at=$(git log --format=%cI "${BASE_BRANCH}..HEAD" 2>/dev/null | tail -1)
    [ -n "$started_at" ] || started_at="$completed_at"

    stamp_tmp=$(mktemp)
    # Top-level keys only: a `started:` indented inside a step belongs to that
    # step and is none of this hook's business.
    if awk -v s="started: \"${started_at}\"" -v c="completed: \"${completed_at}\"" '
        /^(started|completed):/ { next }
        { print }
        /^workflow_id:/ && !ins { print s; print c; ins = 1 }
        END { if (!ins) { print s; print c } }
    ' "$log_path" > "$stamp_tmp" 2>/dev/null && [ -s "$stamp_tmp" ]; then
        mv "$stamp_tmp" "$log_path"
        stamp_note=" + timestamps measured"
    else
        rm -f "$stamp_tmp"
    fi
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
            # AF_PYTHON is already validated, not merely resolved: on Windows
            # `python3` is the Store stub -- present on PATH, executes nothing.
            python_exe="$AF_PYTHON"
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

# ---------- Scratch task audit (ADVISORY — never blocks) ----------
#
# createAndRunTask writes its payload into .vscode/tasks.json, so every one-off
# invocation becomes a permanent entry. Report the leftovers at workflow end;
# the human decides whether to keep or prune them.

scratch_note=""
checker=".github/hooks/scripts/check-scratch-tasks.py"
if [ -f "$checker" ] && [ -f ".vscode/tasks.json" ]; then
    scratch_py=""
    for c in .venv/bin/python .venv/Scripts/python.exe; do
        [ -x "$c" ] && scratch_py="$c" && break
    done
    if [ -z "$scratch_py" ]; then
        scratch_py="$AF_PYTHON"
    fi
    if [ -n "$scratch_py" ]; then
        found=$("$scratch_py" "$checker" ".vscode/tasks.json" 2>/dev/null)
        if [ -n "$found" ]; then
            count=$(printf '%s\n' "$found" | grep -c .)
            joined=$(printf '%s' "$found" | tr '\n' ';' | sed 's/;$//')
            scratch_note=" + scratch tasks to prune (${count}): ${joined}"
        fi
    fi
fi

echo "{\"systemMessage\": \"documenter:Stop — artifact gate PASS for '${workflow_id}'${retro_note}${stamp_note}${cost_note}${scratch_note}\"}"
exit 0
