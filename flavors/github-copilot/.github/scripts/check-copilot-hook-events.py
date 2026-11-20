"""Verify workspace-bound Copilot hook lifecycle evidence without exposing inputs."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections.abc import Iterator
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

REQUIRED_HOOKS = {"sessionStart", "preToolUse", "postToolUse"}
KNOWN_HOOKS = REQUIRED_HOOKS | {
    "sessionEnd",
    "userPromptSubmitted",
    "userPromptTransformed",
    "preMcpToolCall",
    "postToolUseFailure",
    "subagentStart",
    "subagentStop",
    "agentStop",
    "errorOccurred",
}
LIMITS = {
    "verdicts": "not_observable",
    "script_identity": "not_observable",
    "timeouts": "not_observable",
    "authenticity": "local_unsigned_evidence",
}
SESSION_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]{0,127}\Z")


class EvidenceError(ValueError):
    """An explicit non-pass with a static, privacy-safe diagnostic code."""


class EvidenceParser(argparse.ArgumentParser):
    """Keep argument errors out of stderr, including caller-supplied paths."""

    def error(self, message: str) -> None:
        """Raise a privacy-safe diagnostic rather than echoing arguments."""
        raise EvidenceError("invalid_arguments")


@dataclass
class _Activity:
    hooks: dict[str, Any] = field(default_factory=dict)
    pending: dict[str, tuple[str, datetime]] = field(default_factory=dict)
    seen: set[str] = field(default_factory=set)
    failures: int = 0
    unmatched_ends: int = 0


def _records(path: Path) -> Iterator[dict[str, Any]]:
    with path.open(encoding="utf-8-sig") as handle:
        for line in handle:
            if not line.strip():
                continue
            row = json.loads(line)
            if not isinstance(row, dict) or not isinstance(row.get("type"), str):
                raise EvidenceError("invalid_record")
            yield row


def _workspace(value: Any) -> str:
    if not isinstance(value, str) or not value or not Path(value).is_absolute():
        raise EvidenceError("invalid_workspace")
    try:
        return os.path.normcase(str(Path(value).resolve()))
    except (ValueError, RuntimeError) as exc:
        raise EvidenceError("invalid_workspace") from exc


def _header(row: dict[str, Any]) -> tuple[str, str]:
    if row.get("type") != "session.start":
        raise EvidenceError("missing_session_start")
    data = row.get("data")
    if not isinstance(data, dict) or not isinstance(data.get("context"), dict):
        raise EvidenceError("invalid_session_start")
    session_id = data.get("sessionId")
    if not isinstance(session_id, str) or not SESSION_ID.fullmatch(session_id):
        raise EvidenceError("invalid_session_identity")
    return session_id, _workspace(data["context"].get("cwd"))


def _matches(folder: Path, workspace: str) -> bool:
    if not folder.is_dir() or not SESSION_ID.fullmatch(folder.name):
        return False
    try:
        first = next(_records(folder / "events.jsonl"), None)
        return first is not None and _header(first) == (folder.name, workspace)
    except (EvidenceError, OSError, UnicodeError, json.JSONDecodeError, RecursionError):
        # Unidentified/foreign sessions cannot supply workspace evidence.
        return False


def _select(root: Path, workspace: str, session_id: str | None) -> Path:
    if session_id is not None:
        if not SESSION_ID.fullmatch(session_id):
            raise EvidenceError("invalid_session_id")
        return root / session_id / "events.jsonl"
    matches = [folder / "events.jsonl" for folder in root.iterdir() if _matches(folder, workspace)]
    if len(matches) != 1:
        raise EvidenceError("ambiguous_sessions" if matches else "no_matching_session")
    return matches[0]


def _timestamp(row: dict[str, Any]) -> datetime:
    value = row.get("timestamp")
    if not isinstance(value, str):
        raise EvidenceError("missing_timestamp")
    try:
        parsed = datetime.fromisoformat(value.removesuffix("Z") + ("+00:00" if value.endswith("Z") else ""))
    except ValueError as exc:
        raise EvidenceError("invalid_timestamp") from exc
    if parsed.utcoffset() is None:
        raise EvidenceError("timestamp_without_timezone")
    return parsed


def _invocation(data: dict[str, Any]) -> tuple[str, str]:
    identity, kind = data.get("hookInvocationId"), data.get("hookType")
    if not isinstance(identity, str) or not identity or not isinstance(kind, str) or not kind:
        raise EvidenceError("invalid_hook_identity")
    return identity, kind


def _hook_counts(activity: _Activity, kind: str) -> dict[str, Any]:
    public_kind = kind if kind in KNOWN_HOOKS else "other"
    return activity.hooks.setdefault(
        public_kind, {"started": 0, "completed": 0, "failed": 0, "duration_ms": {"total": 0.0, "max": 0.0}}
    )


def _start_hook(activity: _Activity, identity: str, kind: str, stamp: datetime) -> None:
    if identity in activity.seen:
        raise EvidenceError("duplicate_hook_start")
    activity.seen.add(identity)
    activity.pending[identity] = kind, stamp
    _hook_counts(activity, kind)["started"] += 1


def _end_hook(activity: _Activity, data: dict[str, Any], stamp: datetime) -> None:
    identity, kind = _invocation(data)
    if type(data.get("success")) is not bool:
        raise EvidenceError("invalid_hook_success")
    start = activity.pending.pop(identity, None)
    if start is None:
        if identity in activity.seen:
            raise EvidenceError("duplicate_hook_end")
        activity.unmatched_ends += 1
        activity.seen.add(identity)
        return
    if kind != start[0]:
        raise EvidenceError("hook_type_mismatch")
    elapsed = (stamp - start[1]).total_seconds() * 1000
    if elapsed < 0:
        raise EvidenceError("negative_duration")
    counts = _hook_counts(activity, kind)
    counts["completed"] += 1
    counts["duration_ms"]["total"] += elapsed
    counts["duration_ms"]["max"] = max(counts["duration_ms"]["max"], elapsed)
    if not data["success"]:
        counts["failed"] += 1
        activity.failures += 1


def _is_ask(data: dict[str, Any]) -> bool:
    request = data.get("permissionRequest")
    return isinstance(request, dict) and request.get("kind") == "hook"


def _report(
    activity: _Activity, session_id: str, first_time: datetime, last_time: datetime, asks: int
) -> tuple[dict[str, Any], int]:
    complete = REQUIRED_HOOKS.issubset(activity.hooks) and not activity.pending and not activity.unmatched_ends
    code = 2 if not complete else (1 if activity.failures else 0)
    reason = ("complete_lifecycle", "observed_hook_failure", "incomplete_lifecycle")[code]
    return {
        "status": ("pass", "fail", "inconclusive")[code],
        "reason": reason,
        "session_id": session_id,
        "observed_from": first_time.isoformat(),
        "observed_until": last_time.isoformat(),
        "hooks": activity.hooks,
        "failure_count": activity.failures,
        "unmatched_starts": len(activity.pending),
        "unmatched_ends": activity.unmatched_ends,
        "ask_requests": asks,
        "limits": LIMITS,
    }, code


def _selected_records(path: Path, workspace: str) -> tuple[Iterator[dict[str, Any]], str, datetime]:
    rows = _records(path)
    first = next(rows, None)
    if first is None:
        raise EvidenceError("empty_session")
    session_id, actual_workspace = _header(first)
    if session_id != path.parent.name or actual_workspace != workspace:
        raise EvidenceError("session_workspace_mismatch")
    return rows, session_id, _timestamp(first)


def _analyse(path: Path, workspace: str) -> tuple[dict[str, Any], int]:
    rows, session_id, first_time = _selected_records(path, workspace)
    last_time = first_time
    activity = _Activity()
    asks = 0
    for row in rows:
        event = row["type"]
        if event == "session.start":
            raise EvidenceError("duplicate_session_start")
        if event not in {"hook.start", "hook.end", "permission.requested"}:
            continue
        data = row.get("data")
        if not isinstance(data, dict):
            raise EvidenceError("invalid_event_data")
        if event == "permission.requested":
            asks += _is_ask(data)
            continue
        stamp = _timestamp(row)
        first_time, last_time = min(first_time, stamp), max(last_time, stamp)
        if event == "hook.start":
            identity, kind = _invocation(data)
            _start_hook(activity, identity, kind, stamp)
        else:
            _end_hook(activity, data, stamp)
    return _report(activity, session_id, first_time, last_time, asks)


def main(argv: list[str] | None = None) -> int:
    """Print one privacy-safe JSON report; return 0/1/2 for pass/fail/inconclusive."""
    try:
        parser = EvidenceParser(description=__doc__)
        parser.add_argument("--workspace", required=True)
        # af-caller-ok: live caller test-hooks-integration.ps1 is excluded by the checker's test-name rule.
        parser.add_argument("--session-state-root", type=Path, default=Path.home() / ".copilot" / "session-state")
        # af-caller-ok: live caller test-hooks-integration.ps1 is excluded by the checker's test-name rule.
        parser.add_argument("--session-id")
        args = parser.parse_args(argv)
        workspace = _workspace(args.workspace)
        report, code = _analyse(_select(args.session_state_root, workspace, args.session_id), workspace)
    except EvidenceError as exc:
        report, code = {"status": "inconclusive", "reason": str(exc), "limits": LIMITS}, 2
    except (OSError, UnicodeError, json.JSONDecodeError, RecursionError, OverflowError):
        report, code = {"status": "inconclusive", "reason": "unreadable_or_malformed_evidence", "limits": LIMITS}, 2
    print(json.dumps(report, allow_nan=False))
    return code


if __name__ == "__main__":
    sys.exit(main())
