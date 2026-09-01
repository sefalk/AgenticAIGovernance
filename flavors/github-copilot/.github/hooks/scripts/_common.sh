#!/usr/bin/env bash
# Shared resolution preamble for AF hooks (bash side).
#
# SOURCE this file, never execute it:
#
#     _AF_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
#     . "$_AF_DIR/_common.sh"
#
# Provides:
#   AF_SCRIPT_DIR   directory this file lives in
#   AF_MAIN_ROOT    checkout where .github/ is deployed
#   AF_CODE_ROOT    active worktree if the sentinel points at one, else MAIN
#   AF_CONF         config path: $AF_CONF_PATH if set, else .github/af-env.conf
#   AF_CONF_FOUND   1 if that file exists, 0 if it does not
#   AF_PYTHON       an interpreter that was proven to run, or ""
#   af_conf_get KEY [DEFAULT]
#
# Why this exists: every value is derived from this file's own location, never
# from the current working directory. A hook runs from wherever the agent
# process happens to sit, and a config read from the wrong place returns
# nothing -- which is indistinguishable from "the setting is not configured".
# The same failure shape applies to the interpreter, so it is resolved here
# too rather than re-rolled per hook.

# ${BASH_SOURCE[0]} and not $0: when sourced, $0 is the *caller*.
AF_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
AF_MAIN_ROOT=$(dirname "$(dirname "$(dirname "$AF_SCRIPT_DIR")")")

AF_CODE_ROOT="$AF_MAIN_ROOT"
_af_sentinel="$AF_MAIN_ROOT/.github/.active-worktree"
if [ -f "$_af_sentinel" ]; then
    _af_wt=$(tr -d '[:space:]' < "$_af_sentinel" 2>/dev/null)
    if [ -n "$_af_wt" ] && [ -d "$_af_wt" ]; then
        AF_CODE_ROOT="$_af_wt"
    fi
fi
unset _af_sentinel _af_wt

# AF_CONF_PATH overrides the deployed config for this process (issue #108), so
# a test can state the policy it asserts under instead of inheriting whatever
# the consumer ships. A path that does not exist counts as NO config rather
# than falling back to the deployed one -- see _common.ps1 for the reasoning
# and for why this cannot lift a hard-deny.
if [ -n "${AF_CONF_PATH:-}" ]; then
    AF_CONF="$AF_CONF_PATH"
else
    AF_CONF="$AF_MAIN_ROOT/.github/af-env.conf"
fi
if [ -f "$AF_CONF" ]; then
    AF_CONF_FOUND=1
else
    AF_CONF_FOUND=0
fi

# af_conf_get KEY [DEFAULT]
#
# Always returns 0. Callers run under `set -e`/`set -o pipefail`, where a
# non-zero return from a lookup would kill the hook; a missing key is not an
# error, it is the default.
af_conf_get() {
    local _key="$1"
    local _default="${2:-}"
    local _val=""
    if [ "$AF_CONF_FOUND" -eq 1 ]; then
        _val=$(grep -E "^${_key}=" "$AF_CONF" 2>/dev/null | head -1 | cut -d= -f2-)
        _val=${_val%$'\r'}
        _val=$(printf '%s' "$_val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    fi
    if [ -n "$_val" ]; then
        printf '%s\n' "$_val"
    else
        printf '%s\n' "$_default"
    fi
    return 0
}

# af_retro_dir
#
# The retro destination is configurable (issue #117), so every gate has to
# derive it the same way. A hook that kept the old path hardcoded would report
# a missing artifact the documenter had correctly written somewhere else --
# the gate would be wrong and the agent would be blamed.
#
# Normalised so `docs/retros/`, `docs\retros` and `docs/retros` are one value.
# A trailing slash yields `docs/retros//id.md`, which `test -f` accepts and
# string comparison does not, so the path a gate reports would stop matching
# the path it checked.
af_retro_dir() {
    local _dir
    _dir=$(af_conf_get RETRO_DIR '.github/retros/auto')
    _dir=$(printf '%s' "$_dir" | tr '\\' '/' | sed -e 's:/*$::')
    if [ -z "$_dir" ]; then
        _dir=".github/retros/auto"
    fi
    printf '%s\n' "$_dir"
    return 0
}

# af_find_python CANDIDATE...
#
# A resolvable interpreter is not a working one. On Windows, `python3` is an
# App Execution Alias: 121 bytes, on PATH, prints a Microsoft Store advert to
# stderr and exits non-zero without running anything. Hooks that accepted it
# fell through to their `[ -z "$PYTHON" ] && echo '{}'` fail-open path and
# stopped gating anything. So probe each candidate before accepting it.
af_find_python() {
    local _c
    for _c in "$@"; do
        [ -n "$_c" ] || continue
        if command -v "$_c" >/dev/null 2>&1 && "$_c" -c '' >/dev/null 2>&1; then
            command -v "$_c"
            return 0
        fi
    done
    printf '%s\n' ""
    return 0
}

AF_PYTHON=$(af_find_python "${AF_PYTHON_OVERRIDE:-}" python3 python py)

# af_tool_name_from_json RAW
#
# Prints the payload's tool_name. Returns 1 when it cannot be read with
# confidence -- "unreadable" is an answer callers must be able to act on,
# which is why it is not conflated with the empty string.
#
# Parameter expansion only: no cat, no grep, no interpreter. That is the
# entire point. This function exists to answer when the interpreter is gone,
# and one reason it can be gone is a PATH that takes every external binary
# with it.
#
# Parsing JSON by string surgery is normally a mistake, and it is defensible
# here only because of the single field it reads: tool names are bare
# identifiers, so the value cannot contain an escape or an embedded quote.
# Nothing else may be read this way -- tool_input.command certainly cannot.
#
# A command string cannot forge the key, because JSON requires the quotes
# inside a string to be escaped: `\"tool_name\"` in a command is not the token
# searched for here. A nested second key is possible, though, and that is
# reported unreadable rather than guessed at.
af_tool_name_from_json() {
    _tn_rest="$1"
    case "$_tn_rest" in
        *'"tool_name"'*) ;;
        *) return 1 ;;
    esac
    _tn_rest="${_tn_rest#*\"tool_name\"}"
    case "$_tn_rest" in
        *'"tool_name"'*) return 1 ;;
    esac
    _tn_rest="${_tn_rest#*:}"
    case "$_tn_rest" in
        *\"*) ;;
        *) return 1 ;;
    esac
    _tn_rest="${_tn_rest#*\"}"
    _tn_rest="${_tn_rest%%\"*}"
    [ -n "$_tn_rest" ] || return 1
    printf '%s\n' "$_tn_rest"
    return 0
}

# af_require_python RAW PREDICATE GATE
#
# The single answer every PreToolUse gate gives when it has no interpreter.
# Returns normally when one is available, so the caller's happy path is
# unchanged; otherwise it emits a verdict and exits.
#
# A missing interpreter used to mean `echo '{}'; exit 0` -- byte for byte the
# answer a gate gives to a call it has inspected and approved. The gate
# vanished and said nothing about it (issue #251). It refuses instead.
#
# The refusal is scoped by PREDICATE, the caller's own "do I judge this tool"
# test, because these hooks are registered for every tool call: refusing
# blindly would stop reads and edits too and take the session down with the
# gate. A tool the gate never judges is still allowed, which is a real
# verdict rather than a failure to reach one. A payload whose tool_name
# cannot be read is refused, because unreadable is not harmless.
#
# GATE names the gate in the refusal and must be a plain literal -- see
# af_deny_no_python.
af_require_python() {
    [ -n "${AF_PYTHON:-}" ] && return 0
    if _rq_tool=$(af_tool_name_from_json "$1"); then
        if ! "$2" "$_rq_tool"; then
            printf '{}\n'
            exit 0
        fi
    fi
    af_deny_no_python "$3"
}

# af_deny_no_python GATE
#
# Emits the PreToolUse refusal for a missing interpreter, then exits 0.
#
# The reason is fixed text and GATE must be a plain literal: this runs
# precisely when nothing can be trusted to escape anything correctly, and an
# unparsable verdict is indistinguishable from no verdict at all -- the gate
# would disarm itself exactly when it had something to say.
af_deny_no_python() {
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Policy hard-deny: the %s gate found no working Python interpreter (tried AF_PYTHON_OVERRIDE, python3, python, py) and cannot read the payload it exists to judge. A guard that cannot read its input refuses rather than waves through (issue #251). Install Python 3, or set AF_PYTHON_OVERRIDE to an interpreter that runs."}}\n' "$1"
    exit 0
}

# af_plan_lifecycle WORKFLOW_ID [ROOT]
#
# Prints "FOUND|STATUS|PATH" for the plan file belonging to this workflow:
# FOUND is 1 or 0, STATUS is upper-cased or empty, PATH is empty when not found.
# Always returns 0 -- "no plan" is an answer, not an error.
#
# Why a plan file: a Stop hook receives session_id and transcript_path, never
# the delegation prompt. Whether an agent was called mid-workflow or to
# finalise is therefore not knowable from stdin -- it has to be read off the
# repository. The plan file is the honest signal, because setting its status
# to COMPLETED IS the documenter's declaration that it finalised (issue #72).
#
# Two things this deliberately does not do:
#   * It does not match the raw text. templates/PLAN.md ships
#     `**Status:** <!-- DRAFT | APPROVED | IN_PROGRESS | COMPLETED -->`, so a
#     grep for COMPLETED calls an untouched template a finished workflow.
#     HTML comments are stripped first (awk, because sed has no non-greedy
#     match and `<!--[^>]*-->` stops at the first `>` inside a comment).
#   * It does not accept any plan in the directory. A plan speaks for one
#     workflow only, the one whose branch it names.
af_plan_lifecycle() {
    local wid="$1" root="${2:-.}" dir f text status esc
    dir="$root/docs/plans"
    [ -d "$dir" ] || dir="$root/docs"
    [ -d "$dir" ] || { printf '0||\n'; return 0; }

    esc=$(printf '%s' "$wid" | sed 's/[][\.^$*+?(){}|/]/\\&/g')

    while IFS= read -r f; do
        [ -n "$f" ] || continue
        [ "$(basename "$f")" = "WIP.md" ] && continue

        text=$(awk '{ buf = buf $0 "\n" }
            END {
                while ((i = index(buf, "<!--")) > 0) {
                    rest = substr(buf, i + 4)
                    j = index(rest, "-->")
                    if (j == 0) { buf = substr(buf, 1, i - 1); break }
                    buf = substr(buf, 1, i - 1) substr(rest, j + 3)
                }
                printf "%s", buf
            }' "$f" 2>/dev/null)

        # `agent/72-x` must not be satisfied by `agent/72-x-followup`.
        printf '%s' "$text" | grep -Eq "agent/${esc}([^[:alnum:]_-]|\$)" || continue

        status=$(printf '%s' "$text" \
            | grep -iEm1 '^[[:space:]]*[*_# ]*status[*_ ]*:' \
            | sed -E 's/^[^:]*:[[:space:]]*[*_`[:space:]]*//' \
            | grep -oE '^[A-Za-z_]+' \
            | tr '[:lower:]' '[:upper:]')

        printf '1|%s|%s\n' "$status" "$f"
        return 0
    done < <(find "$dir" -type f -name '*.md' 2>/dev/null | sort)

    printf '0||\n'
    return 0
}

# af_retro_required WORKFLOW_ID [ROOT]
# Prints "1|reason" when a retro snippet is owed, "0|reason" when it is not.
#
# The retro used to be unconditional, so a clean run produced a file recording
# that nothing happened — and the next workflow read it back as input.
#
# The condition is derived here, from the workflow log, and never from the
# documenter's account of its own run: "it was clean, so I skipped it" is the
# self-report channel #91 closed for timestamps.
#
# The default is REQUIRED. Skipping needs positive evidence — counters that
# actually read zero, a COMPLETED status, no adverse verdict. A log that is
# missing, unreadable, or still carrying the unfilled `retries: <number>`
# template establishes nothing, and absence of evidence is not evidence of a
# clean run.
#
# Every condition matches a FIELD, not a word: the log quotes the user request
# verbatim in `trigger:`, so "blocked" and "rejected" can appear as prose.
af_retro_required() {
    local wid="$1" root="${2:-.}" log=""

    if [ -f "$root/.github/logs/${wid}.yaml" ]; then
        log="$root/.github/logs/${wid}.yaml"
    elif [ -f "$root/.github/logs/${wid}.yml" ]; then
        log="$root/.github/logs/${wid}.yml"
    fi

    if [ -z "$log" ] || [ ! -s "$log" ]; then
        printf '1|the workflow log could not be read, so a clean run is not established\n'
        return 0
    fi

    grep -Eq '^[[:blank:]]*retries:[[:blank:]]*0[[:space:]]*$' "$log" || {
        printf '1|the log does not record `retries: 0`\n'; return 0; }
    grep -Eq '^[[:blank:]]*escalations:[[:blank:]]*0[[:space:]]*$' "$log" || {
        printf '1|the log does not record `escalations: 0`\n'; return 0; }
    grep -Eqi '^[[:blank:]]*status:[[:blank:]]*"?COMPLETED' "$log" || {
        printf '1|the workflow status is not COMPLETED\n'; return 0; }
    if grep -Eqi '^[[:blank:]]*verdict:[[:blank:]]*"?[[:blank:]]*(REJECTED|ESCALATE|BLOCKED)' "$log"; then
        printf '1|a step verdict was adverse\n'; return 0
    fi
    if grep -Eq '^escalation:[[:space:]]*$' "$log"; then
        printf '1|the log carries an escalation block\n'; return 0
    fi

    printf '0|retries 0, escalations 0, status COMPLETED, no adverse verdict\n'
    return 0
}

# af_is_write_tool TOOL_NAME
#
# True if the tool call modifies files or directories in the workspace.
#
# The names below were read out of captured PreToolUse payloads, not out of
# tool documentation (issue #69). The PowerShell gates used to match camelCase
# names -- editFiles, createFile -- that no client has ever sent, and the bash
# gates matched `*file*`, which caught every read as well. Both failure modes
# are invisible: a gate that never fires and a gate that approves look alike.
#
# Observed: create_file, replace_string_in_file, multi_replace_string_in_file.
# The camelCase spellings stay so a client that does send them is still judged.
af_is_write_tool() {
    case "$1" in
        create_file|replace_string_in_file|multi_replace_string_in_file) return 0 ;;
        create_directory|edit_notebook_file|create_new_jupyter_notebook) return 0 ;;
        editFiles|editFile|createFile|createDirectory|createDir) return 0 ;;
        editNotebook|writeFile|applyPatch|insertEdit) return 0 ;;
    esac
    # An exact list cannot recognise a tool that does not exist yet, and a gate
    # that has never heard of a tool fails open. A writing verb plus a file
    # noun is enough to take the call seriously: `read_file` carries no verb,
    # `create_and_run_task` carries no file noun, so neither is caught here.
    case "$1" in
        *create*|*write*|*edit*|*insert*|*apply*|*replace*|\
        *Create*|*Write*|*Edit*|*Insert*|*Apply*|*Replace*)
            case "$1" in
                *file*|*File*|*notebook*|*Notebook*|*dir*|*Dir*) return 0 ;;
            esac
            ;;
    esac
    return 1
}

# af_write_paths -- reads a raw hook payload on stdin, prints one path per line.
#
# Flat payloads keep their path in `filePath`. `multi_replace_string_in_file`
# keeps none at the top level: its paths sit in `replacements[].filePath`, the
# same one-level-down shape that made the researcher's URL gate inert in #64.
af_write_paths() {
    [ -n "$AF_PYTHON" ] || return 0
    "$AF_PYTHON" -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
tool_input = data.get("tool_input") or {}
found = []
for key in ("filePath", "path", "dirPath", "notebookUri", "uri"):
    value = tool_input.get(key)
    if isinstance(value, str) and value:
        found.append(value)
for entry in tool_input.get("replacements") or []:
    if isinstance(entry, dict):
        value = entry.get("filePath")
        if isinstance(value, str) and value:
            found.append(value)
seen = set()
for path in found:
    if path not in seen:
        seen.add(path)
        print(path)
' 2>/dev/null
}

# --- Provenance marker detection -------------------------------------------
#
# instructions/provenance.instructions.md puts a Python marker *after* the
# module docstring, and the marker for a modified function *inside that
# function's docstring*. Every gate here used to read the first five lines, so
# a module docstring of four lines or more put the instructed placement out of
# reach and the function-level placement was unreachable by construction
# (issue #81). The block message quoted the instruction it contradicted.
#
# Two things this deliberately does not do:
#   * It does not judge *where* the marker sits. A marker's job is to be
#     found; prescribing its position is the instruction's job and checking it
#     is a reviewer's.
#   * It does not tighten what counts as a marker. The second argument narrows
#     which kinds satisfy the caller ("generated" for test-writer's new-file
#     gate, where copilot:modified must not count). It does not additionally
#     demand the full `kind | agent | date` triple -- widening where we look
#     must not quietly start blocking work the old window would have passed.
#
# Usage: af_has_provenance_marker <path> [any|generated]
# Exit status 0 = marked, 1 = unmarked. A missing or unreadable path is
# unmarked, never an error.
af_has_provenance_marker() {
    _prov_file="$1"
    _prov_kind="${2:-any}"

    [ -n "$_prov_file" ] || return 1
    [ -f "$_prov_file" ] || return 1

    if [ "$_prov_kind" = "generated" ]; then
        _prov_pattern='copilot:generated'
    else
        _prov_pattern='copilot:(generated|modified)'
    fi

    grep -qE "$_prov_pattern" "$_prov_file" 2>/dev/null
}

# af_json_escape VALUE
#
# Prints VALUE safe to paste between the quotes of a JSON string.
#
# The bash hooks build their JSON with printf and interpolate values straight
# in. A Windows path then emits `C:\Users\...`, whose `\U` is not a JSON escape
# -- the client cannot parse the object and the decision is discarded, so a
# correct deny reaches nobody (measured on the worktree gate, issue #200).
# Escaping quotes alone, as several call sites do, does not cover this.
#
# Backslash must be replaced first, or it would double the backslashes this
# function itself introduces. Control characters are dropped rather than
# encoded: these values are single-line human-readable reasons.
af_json_escape() {
    printf '%s' "${1:-}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\000-\037'
}

# ── Files a concurrent peer agent edited (issue #101) ──────────────────
#
# Producer stop-hook gates scope themselves from `git diff`, which is global to
# the checkout. Two producers on one branch therefore see each other's in-flight
# edits, and the gate demands work on a file the agent was told not to touch --
# then the provenance gate makes it stamp an authorship marker recording the
# wrong agent.
#
# Echoes the files a DIFFERENT subagent edited while this one was running, one
# per line, so the caller can drop them from its own scope. Every failure path
# echoes nothing: no stdin, no session id, no session directory, no
# interpreter, a non-zero exit. Subtracting nothing is exactly today's
# behaviour, which is the only direction this may fail in -- a watchdog that
# fails a legitimate workflow gets switched off (issue #108).
#
# Usage: af_peer_edits "$stdin_raw" implementer
af_peer_edits() {
    _pe_stdin="${1:-}"
    _pe_agent="${2:-}"
    [ -n "$_pe_stdin" ] && [ -n "$_pe_agent" ] || return 0

    _pe_sid=$(printf '%s' "$_pe_stdin" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    _pe_transcript=$(printf '%s' "$_pe_stdin" | grep -o '"transcript_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    [ -n "$_pe_sid" ] && [ -n "$_pe_transcript" ] || return 0

    # <ws>/GitHub.copilot-chat/transcripts/<sid>.jsonl -> .../debug-logs/<sid>
    _pe_chat_dir=$(dirname "$(dirname "$_pe_transcript")")
    _pe_session_dir="${_pe_chat_dir}/debug-logs/${_pe_sid}"
    [ -d "$_pe_session_dir" ] || return 0

    _pe_reader="${AF_MAIN_ROOT:-.}/.github/hooks/scripts/concurrent-agent-edits.py"
    [ -f "$_pe_reader" ] || return 0

    _pe_python=""
    for _pe_c in .venv/bin/python .venv/Scripts/python.exe; do
        [ -x "$_pe_c" ] && _pe_python="$_pe_c" && break
    done
    [ -n "$_pe_python" ] || _pe_python="${AF_PYTHON:-}"
    [ -n "$_pe_python" ] || return 0

    "$_pe_python" "$_pe_reader" --session-dir "$_pe_session_dir" \
        --agent "$_pe_agent" --repo-root "${AF_CODE_ROOT:-.}" 2>/dev/null || return 0
}

# Remove from a newline-separated list ($1) every line present in a second
# list ($2). Used to drop a concurrent peer's files from a gate scope (#101).
#
# The blank-line guard is not cosmetic: `grep -vxF` reads its pattern argument
# as one pattern PER LINE, so a single empty line in the drop list is an empty
# pattern, `-x` makes it match every line, and the entire scope would be
# filtered away -- a gate that silently checks nothing.
af_strip_lines() {
    _sl_list="${1:-}"
    _sl_drop=$(printf '%s\n' "${2:-}" | sed '/^[[:space:]]*$/d')
    if [ -z "$_sl_list" ] || [ -z "$_sl_drop" ]; then
        printf '%s' "$_sl_list"
        return 0
    fi
    printf '%s\n' "$_sl_list" | grep -vxF "$_sl_drop" || true
}
