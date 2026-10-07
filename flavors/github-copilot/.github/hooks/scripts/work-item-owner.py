"""PreToolUse gate for work-item writes.

Covers the ADO owner (#36), Bug body placement (#289), field shrink (#197) and
GitHub body shrink (#376).

Called by both block-dangerous wrappers for ``*wit_work_item_write`` and the
GitHub ``issue_write`` / ``update_pull_request`` / ``update_issue_comment`` calls.
Reads the payload on stdin and the resolved config path from ``AF_CONF_RESOLVED``;
writes one PreToolUse verdict to stdout and always exits 0. The shrink checks live
in ``_field_guard.py`` (ADO) and ``_body_guard.py`` (GitHub).
"""

from __future__ import annotations

import json
import os
import re
import sys

from _body_guard import check_body as body_guard
from _field_guard import check as field_guard

OWNER_KEY = "ADO_DEFAULT_ASSIGNED_TO"
OWNER_FIELD = "System.AssignedTo"
DESCRIPTION = "System.Description"
REPRO_STEPS = "Microsoft.VSTS.TCM.ReproSteps"
LONG_TEXT = (
    DESCRIPTION,
    REPRO_STEPS,
    "Microsoft.VSTS.TCM.SystemInfo",
    "Microsoft.VSTS.Common.AcceptanceCriteria",
)
# ADO stores an unformatted value as HTML, so these render as literal text.
MARKDOWN_SIGNS = re.compile(r"^(#{1,6} |```|\|.*\|\s*$)", re.MULTILINE)


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
    return bool(field_value(fields, OWNER_FIELD).strip())


def field_entries(fields: object) -> list[dict]:
    return [f for f in fields if isinstance(f, dict)] if isinstance(fields, list) else []


def field_value(fields: object, name: str) -> str:
    for field in field_entries(fields):
        if str(field.get("name", "")).removeprefix("/fields/").lower() == name.lower():
            return str(field.get("value") or "")
    return ""


def body_problem(work_item_type: str, fields: object) -> str:
    """Name why a create would store its body where no one reads it (#289), or ''."""
    if (
        work_item_type.strip().lower() == "bug"
        and field_value(fields, DESCRIPTION).strip()
        and not field_value(fields, REPRO_STEPS).strip()
    ):
        return (
            f"Policy hard-deny: the stock Bug form renders Repro Steps and System Info, not {DESCRIPTION}, "
            "so a Bug body written there is stored but never seen (#289). "
            f"Put the body in {REPRO_STEPS} instead, with format Markdown if it is Markdown."
        )
    for field in field_entries(fields):
        name = str(field.get("name", "")).removeprefix("/fields/")
        if name.lower() not in (n.lower() for n in LONG_TEXT) or field.get("format"):
            continue
        if MARKDOWN_SIGNS.search(str(field.get("value") or "")):
            return (
                f"Policy hard-deny: {name} holds Markdown but sets no format, so ADO stores it as HTML "
                'and headings render as literal "##" (#289). Add "format": "Markdown" to that field and retry.'
            )
    return ""


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
        payload = json.loads(sys.stdin.buffer.read().decode("utf-8-sig", errors="replace"))
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

    if not str(payload.get("tool_name") or "").endswith("wit_work_item_write"):
        verdict = body_guard({**payload, "tool_input": tool_input}, os.environ.get("AF_CONF_RESOLVED", ""))
        if verdict:
            print(json.dumps(verdict, separators=(",", ":")))
            return 0
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

    if action == "create":
        problem = body_problem(str(tool_input.get("workItemType") or ""), tool_input.get("fields"))
        if problem:
            return deny(problem)

    if action in ("update", "update_batch") and isinstance(payload, dict):
        verdict = field_guard({**payload, "tool_input": tool_input}, os.environ.get("AF_CONF_RESOLVED", ""))
        if verdict:
            print(json.dumps(verdict, separators=(",", ":")))
            return 0

    return defer()


if __name__ == "__main__":
    sys.exit(main())
