#!/usr/bin/env python3
"""Translate a native ``version: 1`` hook payload for an AF hook (#566).

A ``version: 1`` registration (``.github/hooks/*.json``, camelCase event
names) hands hooks a camelCase payload -- ``toolName``, ``toolArgs``,
``sessionId``. Every AF policy reads the snake_case shape the PascalCase
registration delivers (``tool_name``, ``tool_input``, ``session_id``). Fed the
camelCase payload directly, each policy finds no tool name and returns ``{}``:
a success-shaped no-op, measured on ``block-dangerous`` with a force push.

Usage::

    python _native_adapter.py <event> -- <target command...>

The adapter sits in front of one unchanged hook. snake_case input passes
through byte for byte; camelCase input is renamed, never guessed. What cannot
be translated is refused on ``preToolUse`` and reported on every other event,
so a translation gap cannot pass as a clean result. The target's stdout,
stderr and exit code reach the host unchanged, except that a verdict nested
under ``hookSpecificOutput`` is also lifted to the top level -- the only form
a ``version: 1`` host is certain to honour.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from typing import Any

EVENTS = {
    "preToolUse": "PreToolUse",
    "postToolUse": "PostToolUse",
    "sessionStart": "SessionStart",
    "agentStop": "Stop",
    "subagentStart": "SubagentStart",
    "subagentStop": "SubagentStop",
    "userPromptSubmitted": "UserPromptSubmit",
}
EVENTS.update({pascal: pascal for pascal in list(EVENTS.values())})

TOOL_EVENTS = {"PreToolUse", "PostToolUse"}
SNAKE_MARKERS = ("tool_name", "session_id", "hook_event_name")
RENAMES = {"toolArgs": "tool_input", "toolCallId": "tool_use_id"}
LIFTED = ("permissionDecision", "permissionDecisionReason", "additionalContext")


def _snake(name: str) -> str:
    return re.sub(r"(?<=[a-z0-9])([A-Z])", r"_\1", name).lower()


def _decode_tool_args(value: Any) -> Any:
    """Return tool arguments as an object when they are JSON, else unchanged.

    ``apply_patch`` sends its patch text as a plain string; that string is the
    argument and must stay one.
    """
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
        except ValueError:
            return value
        return parsed if isinstance(parsed, dict) else value
    return value


def translate(payload: dict[str, Any], event: str) -> dict[str, Any]:
    """Rename a camelCase payload to the snake_case PascalCase-registration shape.

    Parameters
    ----------
    payload : dict
        The decoded ``version: 1`` payload.
    event : str
        The PascalCase event name.

    Returns
    -------
    dict
        The payload with every top-level key snake_cased and
        ``hook_event_name`` set. An existing snake_case key wins over its
        camelCase twin.
    """
    out: dict[str, Any] = {}
    for key, value in payload.items():
        if key == "toolResult" and isinstance(value, dict):
            value = {_snake(k): v for k, v in value.items()}
        elif key == "toolArgs":
            value = _decode_tool_args(value)
        new_key = RENAMES.get(key, _snake(key))
        if new_key != key and new_key in payload:
            continue
        out[new_key] = value
    out["hook_event_name"] = event
    return out


def _refuse(event: str, reason: str) -> int:
    reason = f"AF native adapter: {reason}"
    if event == "PreToolUse":
        verdict = {
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
            "hookSpecificOutput": {
                "hookEventName": event,
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            },
        }
    else:
        verdict = {"additionalContext": f"WARNING: {reason}"}
    sys.stdout.write(json.dumps(verdict))
    return 0


def _lift(stdout: bytes) -> bytes:
    """Copy a nested verdict to the top level; leave anything else as it was."""
    try:
        verdict = json.loads(stdout.decode("utf-8-sig"))
    except ValueError:
        return stdout
    if not isinstance(verdict, dict):
        return stdout
    nested = verdict.get("hookSpecificOutput")
    if not isinstance(nested, dict):
        return stdout
    missing = [k for k in LIFTED if k in nested and k not in verdict]
    if not missing:
        return stdout
    for key in missing:
        verdict[key] = nested[key]
    return json.dumps(verdict).encode("utf-8")


def main(argv: list[str]) -> int:
    """Run the adapter; see the module docstring for the contract."""
    if len(argv) < 3 or argv[1] != "--":
        sys.stderr.write("usage: _native_adapter.py <event> -- <target command...>\n")
        return 2
    raw_event, target = argv[0], argv[2:]
    event = EVENTS.get(raw_event)
    if event is None:
        sys.stderr.write(f"AF native adapter: unknown event '{raw_event}'\n")
        return 2

    raw = sys.stdin.buffer.read()
    try:
        payload = json.loads(raw.decode("utf-8-sig"))
    except ValueError:
        payload = None
    if not isinstance(payload, dict):
        return _refuse(event, f"{event} payload is not a JSON object; the hook was not run")

    if any(marker in payload for marker in SNAKE_MARKERS):
        forwarded = raw
    else:
        translated = translate(payload, event)
        if event in TOOL_EVENTS and not translated.get("tool_name"):
            return _refuse(event, f"{event} payload carries no tool name; the hook was not run")
        forwarded = json.dumps(translated).encode("utf-8")

    try:
        done = subprocess.run(target, input=forwarded, capture_output=True, check=False)
    except OSError as exc:
        return _refuse(event, f"hook target could not start ({exc.__class__.__name__})")

    sys.stderr.buffer.write(done.stderr)
    sys.stdout.buffer.write(_lift(done.stdout))
    return done.returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
