"""PreToolUse gate: an ADO work item is never created without an owner (#36).

Called by both block-dangerous wrappers for ``*wit_work_item_write`` calls only.
Reads the payload on stdin and the resolved config path from ``AF_CONF_RESOLVED``;
writes one PreToolUse verdict to stdout and always exits 0.
"""

from __future__ import annotations

import json
import os
import sys

OWNER_KEY = "ADO_DEFAULT_ASSIGNED_TO"
OWNER_FIELD = "System.AssignedTo"


def configured_owner(conf_path: str) -> str:
    if not conf_path or not os.path.isfile(conf_path):
        return ""
    with open(conf_path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            key, sep, value = line.strip().partition("=")
            if sep and key == OWNER_KEY:
                return value.strip()
    return ""


def deny(reason: str) -> int:
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason,
                }
            },
            separators=(",", ":"),
        )
    )
    return 0


def defer() -> int:
    print("{}")
    return 0


def has_owner(fields: object) -> bool:
    if not isinstance(fields, list):
        return False
    for field in fields:
        if not isinstance(field, dict):
            continue
        name = str(field.get("name", "")).removeprefix("/fields/")
        if name.lower() == OWNER_FIELD.lower() and str(field.get("value") or "").strip():
            return True
    return False


def owner_hint(owner: str) -> str:
    if owner:
        return f'Add {{"name": "{OWNER_FIELD}", "value": "{owner}"}} to fields (the {OWNER_KEY} default) and retry.'
    return (
        f"{OWNER_KEY} is not set in .github/af-env.conf, so there is no default owner. "
        "Ask the human who should own this item, pass it as "
        f"{OWNER_FIELD}, and suggest setting {OWNER_KEY} so the question does not recur."
    )


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return defer()
    tool_input = payload.get("tool_input") if isinstance(payload, dict) else None
    if isinstance(tool_input, str):
        try:
            tool_input = json.loads(tool_input)
        except json.JSONDecodeError:
            tool_input = None
    if not isinstance(tool_input, dict):
        return defer()

    action = str(tool_input.get("action", "")).lower()
    owner = configured_owner(os.environ.get("AF_CONF_RESOLVED", ""))

    if action == "add_child":
        # The MCP schema for add_child has no assignee field at all.
        return deny(
            "Policy hard-deny: wit_work_item_write action=add_child cannot set "
            f"{OWNER_FIELD}, so every child it creates is unowned and falls off the board (#36). "
            "Create each child with action=create including "
            f"{OWNER_FIELD}, then link it to the parent with wit_work_item_link_write. " + owner_hint(owner)
        )

    if action == "create" and not has_owner(tool_input.get("fields")):
        return deny(
            f"Policy hard-deny: a work item is never created without {OWNER_FIELD}; "
            "unowned items fall off the board (#36). " + owner_hint(owner)
        )

    return defer()


if __name__ == "__main__":
    sys.exit(main())
