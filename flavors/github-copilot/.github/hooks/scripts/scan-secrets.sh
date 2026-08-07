#!/usr/bin/env bash
# PostToolUse hook: Scan edited files for hardcoded secrets.
#
# Uses gitleaks if available, falls back to regex pattern matching.
# Blocking — exits with code 1 when secrets are detected (HARD gate).

set -uo pipefail

# Root, config and interpreter come from this script's location, never from
# the cwd the agent happens to run in (issue #54).
. "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

raw=$(cat)
if [ -z "$AF_PYTHON" ]; then echo '{}'; exit 0; fi
tool_name=$(echo "$raw" | "$AF_PYTHON" -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null || echo "")

if ! af_is_write_tool "$tool_name"; then
    echo '{}'
    exit 0
fi

file_paths=$(printf '%s' "$raw" | af_write_paths)

if [ -z "$file_paths" ]; then
    echo '{}'
    exit 0
fi

# A batched edit touches several files in one call, so the scan runs over all
# of them. A secret anywhere in the batch outranks a missing marker, so the
# provenance advisory is held back until every file has been read: only one
# verdict can be emitted.
provenance_advisory=""

while IFS= read -r file_path; do
    [ -n "$file_path" ] || continue
    [ -f "$file_path" ] || continue

    # Try gitleaks. The exit code has to be read from the command itself:
    # `result=$(...) || true` followed by `[ $? -ne 0 ]` tests the exit code of
    # `true`, so a detection was reported as a pass every single time.
    if command -v gitleaks &>/dev/null; then
        if ! result=$(gitleaks detect --no-git --source "$file_path" --no-color 2>&1); then
            echo "{\"gate\": \"secret-scan\", \"status\": \"FAIL\", \"tool\": \"gitleaks\", \"file\": \"$file_path\"}"
            exit 1
        fi
        continue
    fi

    # Fallback: grep for common patterns.
    # POSIX classes, not \s: inside a bracket expression `\` is a literal, so
    # `[^\s"']` excluded the letter s rather than whitespace and the generic
    # secret rule never fired. The PowerShell sibling used .NET regex and did
    # match, so the two platforms disagreed in silence.
    findings=""
    if grep -qE 'AKIA[0-9A-Z]{16}' "$file_path" 2>/dev/null; then
        findings="AWS Key"
    fi
    if grep -qiE '(password|secret|token|api_key)[[:space:]]*[:=][[:space:]]*["'"'"'][^[:space:]"'"'"']{8,}' "$file_path" 2>/dev/null; then
        findings="${findings:+$findings, }Generic Secret"
    fi
    if grep -q 'BEGIN.*PRIVATE KEY' "$file_path" 2>/dev/null; then
        findings="${findings:+$findings, }Private Key"
    fi

    if [ -n "$findings" ]; then
        echo "{\"gate\": \"secret-scan\", \"status\": \"FAIL\", \"tool\": \"regex-fallback\", \"file\": \"$file_path\", \"patterns\": \"$findings\"}"
        exit 1
    fi

    # --- Provenance marker check (SOFT advisory -- Idea 37a) ---
    case "$file_path" in
        *.py)
            if [ -z "$provenance_advisory" ] && [ -f "$file_path" ]; then
                if ! af_has_provenance_marker "$file_path"; then
                    provenance_advisory="{\"gate\": \"provenance-check\", \"status\": \"WARN\", \"file\": \"$file_path\", \"detail\": \"No copilot:generated or copilot:modified marker found anywhere in this file. If this file was created or substantially modified by an agent, add a provenance marker. See instructions/provenance.instructions.md.\"}"
                fi
            fi
            ;;
    esac
done <<< "$file_paths"

if [ -n "$provenance_advisory" ]; then
    echo "$provenance_advisory"
    exit 0
fi

echo '{}'
exit 0
