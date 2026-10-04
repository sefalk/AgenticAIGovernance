#!/usr/bin/env bash
# SessionStart hook: verifies Azure DevOps MCP readiness and optionality state.
# Output: additionalContext with READY, DEGRADED, or BLOCKED readiness summary.

set -euo pipefail

# Root, config and interpreter come from this script's location, never from
# the cwd the agent happens to run in (issue #54).
. "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

cat > /dev/null

repo_root="$AF_MAIN_ROOT"
if [[ -z "$repo_root" ]]; then
    printf '{}\n'
    exit 0
fi

conf_path="$AF_CONF"
mode="off"
missing=()
advisories=()
project=""
wiki_identifier=""

get_conf_value() {
    af_conf_get "$1" ""
}

if [[ "$AF_CONF_FOUND" -ne 1 ]]; then
    missing+=(".github/af-env.conf")
else
    mode="$(get_conf_value ADO_CAPABILITY_MODE)"
    mode="${mode:-off}"
    mode="$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')"

    project="$(get_conf_value ADO_PROJECT)"
    organization="$(get_conf_value ADO_ORGANIZATION)"
    wiki_identifier="$(get_conf_value ADO_WIKI_IDENTIFIER)"
    repo_id="$(get_conf_value ADO_REPOSITORY_ID)"
    repo_name="$(get_conf_value ADO_REPOSITORY_NAME)"

    if [[ "$mode" == "required" ]]; then
        [[ -n "$project" ]] || missing+=("ADO_PROJECT")
    elif [[ "$mode" == "optional" ]]; then
        [[ -n "$project" ]] || advisories+=("ADO_PROJECT missing (work-item workflows will use fallback traceability)")
    fi

    if [[ -z "$wiki_identifier" ]]; then
        advisories+=("ADO_WIKI_IDENTIFIER missing (wiki workflows may need confirmation)")
    fi

    if [[ "$mode" != "off" && -z "$organization" ]]; then
        advisories+=("ADO_ORGANIZATION missing (artifact web links depend on the MCP response carrying a URL)")
    fi

    if [[ -z "$repo_id" && -z "$repo_name" ]]; then
        advisories+=("ADO_REPOSITORY_ID/ADO_REPOSITORY_NAME missing (branch artifact links may degrade to comments)")
    fi

    if [[ "$mode" != "off" ]]; then
        grep -q '^ADO_DEFAULT_TARGET_BRANCH=' "$conf_path" || advisories+=("ADO_DEFAULT_TARGET_BRANCH missing (PR integration defaults to dev)")
        if ! grep -q '^ADO_PR_AUTOCOMPLETE_BRANCHES=' "$conf_path" || ! grep -q '^ADO_PR_HUMAN_ONLY_BRANCHES=' "$conf_path"; then
            advisories+=("ADO_PR_AUTOCOMPLETE_BRANCHES/ADO_PR_HUMAN_ONLY_BRANCHES missing (PR completion policy uses defaults)")
        fi
    fi
fi

while IFS= read -r -d '' f; do
    if grep -q 'Azure DevOps' "$f"; then
        agent_name=$(grep '^name:' "$f" | head -1 | sed 's/^name:[[:space:]]*//')
        if [[ -n "$agent_name" && "$agent_name" != ado-* ]]; then
            advisories+=("ADO agent without ado- prefix: $agent_name")
        fi
    fi
done < <(find "$repo_root/.github/agents" -maxdepth 1 -name '*.agent.md' -type f -print0 2>/dev/null)

# Legacy MCP tool ids fail prompt validation silently, so catch them once per
# session rather than discovering it mid-workflow.
# Every step below is guarded: under `set -e` a failing probe must degrade this
# advisory, never abort the hook.
if [[ "$mode" != "off" ]]; then
    checker="$repo_root/.github/scripts/check-mcp-tool-ids.py"
    if [[ -f "$checker" ]]; then
        py="$AF_PYTHON"
        if [[ -n "$py" ]]; then
            check_rc=0
            check_out=$("$py" "$checker" --root "$repo_root/.github" --quiet 2>/dev/null) || check_rc=$?
            if [[ $check_rc -eq 1 ]]; then
                count=$(printf '%s' "$check_out" | grep -oE '[0-9]+ legacy' | head -1 | grep -oE '[0-9]+' || true)
                [[ -z "$count" ]] && count="some"
                advisories+=("$count legacy azure-devops-mcp tool id(s) present -- ADO agents will silently lose tools (run .github/scripts/check-mcp-tool-ids.py)")
            fi
        fi
    fi
fi

auth_hint="auth-provider-managed"
if [[ -n "${AZURE_DEVOPS_EXT_PAT:-}" || -n "${ADO_PAT:-}" || -n "${SYSTEM_ACCESSTOKEN:-}" ]]; then
    auth_hint="token-env-present"
fi

status="READY"
if [[ "$mode" == "required" && ${#missing[@]} -gt 0 ]]; then
    status="BLOCKED"
elif [[ "$mode" == "optional" && ${#missing[@]} -gt 0 ]]; then
    status="DEGRADED"
elif [[ "$mode" == "off" ]]; then
    advisories+=("ADO capability mode is off")
fi

msg="ADO MCP readiness: $status | mode=$mode | auth=$auth_hint"
if [[ ${#missing[@]} -gt 0 ]]; then
    msg="$msg | missing=$(IFS=','; echo "${missing[*]}")"
fi
if [[ ${#advisories[@]} -gt 0 ]]; then
    msg="$msg | advisory=$(IFS=';'; echo "${advisories[*]}")"
fi
if [[ -n "$project" ]]; then
    msg="$msg | defaults:project=$project"
fi
if [[ -n "$wiki_identifier" ]]; then
    msg="$msg | wiki=$wiki_identifier"
fi

# Backslashes first -- escaping quotes before backslashes would re-escape the
# backslash this step just introduced.
msg_escaped=$(af_json_escape "$msg")
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$msg_escaped"

exit 0