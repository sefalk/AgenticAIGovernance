#!/usr/bin/env python3
"""Collect the billed cost of one chat session from the agent debug log.

Emits a YAML `cost:` block on stdout for the documenter to append to
`.github/logs/{workflow-id}.yaml`. It writes no file itself, so the documenter
stays the only writer of the workflow log and this script stays testable
without a workflow.

Exit codes:
    0  a block was emitted -- including ``available: false``
    2  usage error (argparse)

A vendor setting being off is not a failure of this framework, so an absent or
unusable log is a normal outcome, never a non-zero exit. The block is
ADVISORY: nothing downstream may gate on it.

The session directory is handed in (VS Code resolves it as
``VSCODE_TARGET_SESSION_LOG``) rather than discovered. Picking a session by
modification time would misattribute silently whenever parallel worktrees run
concurrent sessions. That variable resolves even when logging is disabled and
without checking that the directory exists, so it is a pointer, never
evidence -- everything below is verified here.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys
from typing import Any, Iterator

SCHEMA_VERSION = 1
COLLECTOR_VERSION = 1

NANO_AIU_PER_CREDIT = 1_000_000_000

# Fields a billed request must carry. Missing any of them means the log schema
# moved; these are preview fields under no compatibility promise.
REQUIRED_REQUEST_ATTRS = ("model", "inputTokens", "cachedTokens", "outputTokens")

BILLING_ATTR = "copilotUsageNanoAiu"


class Drift(Exception):
    """The log no longer carries the fields this collector depends on."""


def iter_events(path: str) -> Iterator[dict[str, Any]]:
    """Yield parsed JSONL entries, skipping unparseable lines.

    Streams the file: a single session log reached 25 MB within a few hours.
    """
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except (ValueError, TypeError):
                continue
            if isinstance(event, dict):
                yield event


def log_files(session_dir: str) -> list[str]:
    """Return the parent log plus every subagent log in the same directory.

    Subagent turns are never in ``main.jsonl`` and run a different model, so
    reading only the parent understates every workflow that delegates.
    """
    files = [os.path.join(session_dir, "main.jsonl")]
    files.extend(sorted(glob.glob(os.path.join(session_dir, "runSubagent-*.jsonl"))))
    return files


class Totals:
    """Billed aggregate. Unbilled requests are counted, never summed."""

    def __init__(self) -> None:
        self.requests = 0
        self.unbilled = 0
        self.input_uncached = 0
        self.cached = 0
        self.output = 0
        self.nano_aiu = 0
        self.by_model: dict[str, dict[str, int]] = {}

    def add(self, attrs: dict[str, Any]) -> None:
        for field in REQUIRED_REQUEST_ATTRS:
            if attrs.get(field) is None:
                raise Drift(field)

        nano = attrs.get(BILLING_ATTR)
        if nano is None:
            # Absent means *not billed* (measured: only `backgroundTodoAgent`
            # infrastructure calls), not lost. Never default it to zero.
            self.unbilled += 1
            return

        model = str(attrs["model"])
        input_tokens = int(attrs["inputTokens"])
        cached = int(attrs["cachedTokens"])

        self.requests += 1
        # inputTokens already includes cachedTokens -- adding both double-counts.
        self.input_uncached += input_tokens - cached
        self.cached += cached
        self.output += int(attrs["outputTokens"])
        self.nano_aiu += int(nano)

        bucket = self.by_model.setdefault(model, {"requests": 0, "nano_aiu": 0})
        bucket["requests"] += 1
        bucket["nano_aiu"] += int(nano)

    @property
    def credits(self) -> float:
        return round(self.nano_aiu / NANO_AIU_PER_CREDIT, 3)


def collect(session_dir: str, workflow_start: int | None) -> dict[str, Any]:
    """Validate the session directory and aggregate it, or explain why not."""
    if not os.path.isdir(session_dir):
        return {"available": False, "reason": "session_dir_missing"}

    main = os.path.join(session_dir, "main.jsonl")
    if not os.path.isfile(main):
        return {"available": False, "reason": "main_log_missing"}

    session_start: dict[str, Any] | None = None
    totals = Totals()
    parsed = 0

    for path in log_files(session_dir):
        if not os.path.isfile(path):
            continue
        for event in iter_events(path):
            parsed += 1
            kind = event.get("type")
            if kind == "session_start" and session_start is None:
                session_start = event
            elif kind == "llm_request":
                try:
                    totals.add(event.get("attrs") or {})
                except Drift:
                    return {"available": False, "reason": "schema_drift"}

    if parsed == 0:
        return {"available": False, "reason": "log_unparseable"}

    result: dict[str, Any] = {
        "available": True,
        "sessions": [os.path.basename(os.path.normpath(session_dir))],
        "environment": _environment(session_start),
    }

    if session_start is None:
        # The size cap drops the OLDEST entries, i.e. the plan and Red phases.
        # A total would look complete while being biased downward, so emit none.
        result["coverage"] = "truncated"
        result["totals"] = None
        return result

    started = session_start.get("ts")
    if workflow_start is not None and isinstance(started, int) and started > workflow_start:
        result["coverage"] = "partial"
    else:
        result["coverage"] = "full"
    result["totals"] = totals
    return result


def _environment(session_start: dict[str, Any] | None) -> dict[str, str | None]:
    attrs = (session_start or {}).get("attrs") or {}
    return {
        "vscode": attrs.get("vscodeVersion"),
        "copilot_chat": attrs.get("copilotVersion"),
    }


def _scalar(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    return f'"{value}"'


def render(result: dict[str, Any]) -> str:
    """Render the block. Only numbers and short identifiers are ever emitted.

    No field is copied from the log unless it is constructed here: request
    payloads carry whatever was pasted into chat.
    """
    lines = [
        "cost:",
        f"  schema_version: {SCHEMA_VERSION}",
        f'  collector: "collect-session-cost.py@{COLLECTOR_VERSION}"',
        f"  available: {_scalar(result['available'])}",
    ]
    if not result["available"]:
        lines.append(f"  reason: {result['reason']}")
        return "\n".join(lines) + "\n"

    sessions = ", ".join(_scalar(s) for s in result["sessions"])
    totals: Totals | None = result["totals"]
    env = result["environment"]

    lines.append(f"  coverage: {result['coverage']}")
    lines.append(f"  sessions: [{sessions}]")
    lines.append(f"  requests: {_scalar(totals.requests if totals else None)}")
    lines.append(f"  unbilled_requests: {_scalar(totals.unbilled if totals else None)}")
    lines.append(
        "  tokens: {{ input_uncached: {0}, cached: {1}, output: {2} }}".format(
            _scalar(totals.input_uncached if totals else None),
            _scalar(totals.cached if totals else None),
            _scalar(totals.output if totals else None),
        )
    )
    lines.append(f"  credits: {_scalar(totals.credits if totals else None)}")
    lines.append("  by_model:")
    for model, bucket in sorted((totals.by_model if totals else {}).items()):
        credits = round(bucket["nano_aiu"] / NANO_AIU_PER_CREDIT, 3)
        lines.append(f"    {model}: {{ requests: {bucket['requests']}, credits: {credits} }}")
    if not (totals and totals.by_model):
        lines[-1] = "  by_model: {}"
    lines.append(f"  environment: {{ vscode: {_scalar(env['vscode'])}, copilot_chat: {_scalar(env['copilot_chat'])} }}")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Collect billed session cost from the agent debug log.",
    )
    parser.add_argument(
        "--session-dir",
        required=True,
        help="Session log directory (VS Code: VSCODE_TARGET_SESSION_LOG).",
    )
    parser.add_argument(
        "--workflow-start",
        type=int,
        default=None,
        help="Workflow start as epoch milliseconds; enables partial-coverage detection.",
    )
    args = parser.parse_args(argv)

    sys.stdout.write(render(collect(args.session_dir, args.workflow_start)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
