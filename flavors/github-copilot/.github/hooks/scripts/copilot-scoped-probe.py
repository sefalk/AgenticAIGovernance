"""Record Copilot role routes without executing gates or emitting decisions."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

_EVENTS = ("preToolUse", "postToolUse", "subagentStop", "agentStop")
_IDENTIFIER = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]{0,127}\Z")
_STOP_ROUTES = {
    "coordinator": "coordinator-postmerge",
    "implementer": "implementer-stop",
    "test-writer": "test-writer-stop",
    "refactorer": "refactorer-stop",
    "documenter": "documenter-stop",
    "compliance-checker": "compliance-checker-stop",
}


def _field(payload: dict[str, object], camel: str, snake: str) -> str | None:
    values: list[str] = []
    for key in (camel, snake):
        if key not in payload:
            continue
        value = payload[key]
        if not isinstance(value, str) or not _IDENTIFIER.fullmatch(value):
            raise ValueError(f"Invalid {camel}/{snake} identity field.")
        values.append(value)
    if len(values) == 2 and values[0] != values[1]:
        raise ValueError(f"Conflicting {camel}/{snake} identity fields.")
    if not values:
        return None
    return values[0]


def _route(event: str, role: str | None) -> tuple[str | None, str]:
    if role is None:
        return None, "main-unscoped"
    if role not in _STOP_ROUTES:
        return None, "role-not-allowlisted"
    if event == "subagentStop":
        return _STOP_ROUTES[role], "routed"
    if role == "coordinator":
        if event == "preToolUse":
            return "coordinator-pretooluse", "routed"
        if event == "postToolUse":
            return "coordinator-posttooluse", "routed"
    return None, "event-unscoped"


def _record(event: str, raw: bytes) -> dict[str, object]:
    record: dict[str, object] = {
        "probe": "AF541_NATIVE_EXEC",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "event": event,
        "agent_type": None,
        "session_id": None,
        "agent_id": None,
        "parent_agent_id": None,
        "route": None,
        "status": "error",
        "error": None,
    }
    try:
        payload = json.loads(raw.decode("utf-8-sig"))
        if not isinstance(payload, dict):
            raise ValueError("Hook payload must be a JSON object.")
        role = _field(payload, "agentType", "agent_type")
        identities = {
            "session_id": _field(payload, "sessionId", "session_id"),
            "agent_id": _field(payload, "agentId", "agent_id"),
            "parent_agent_id": _field(payload, "parentAgentId", "parent_agent_id"),
        }
        route, status = _route(event, role)
        record.update(identities)
        record.update(agent_type=role, route=route, status=status)
    except ValueError as exc:
        record["error"] = "invalid-input"
        print(f"AF541 routing error: {exc}", file=sys.stderr)
    return record


def _main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event", choices=_EVENTS, required=True)
    parser.add_argument("--log", type=Path, required=True)
    args = parser.parse_args()
    record = _record(args.event, sys.stdin.buffer.read())
    code = 0
    try:
        args.log.parent.mkdir(parents=True, exist_ok=True)
        with args.log.open("a", encoding="utf-8", newline="\n") as audit:
            audit.write(json.dumps(record, separators=(",", ":")) + "\n")
    except OSError:
        print("AF541 audit error: could not persist routing metadata.", file=sys.stderr)
        code = 1
    print("{}")
    return code


if __name__ == "__main__":
    sys.exit(_main())
