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
import re
import sys
from typing import Any, Iterator

SCHEMA_VERSION = 2
COLLECTOR_VERSION = 2

NANO_AIU_PER_CREDIT = 1_000_000_000

# Name of the bucket holding the parent session. Deliberately not `coordinator`:
# the file records which log a request came from, not which agent authored it,
# and a session that never delegated has no coordinator in it at all.
PARENT = "main"

# `runSubagent-ado-pr-manager-toolu_011DEuS1yqmhJkPQa1qmtY3U.jsonl`. Split on
# the LAST hyphen -- agent names contain hyphens, the tool-call id does not.
# Same parse as collect-agent-invocations.py; an unmatched name keeps its whole
# stem so a future id format shows up as an odd bucket instead of a lost one.
SUBAGENT = re.compile(r"^runSubagent-(?P<agent>.+)-(?P<call>[^-]+)\.jsonl$")

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


def agent_from(path: str) -> str:
    """Bucket name for a log file: the parent, or the subagent that wrote it."""
    name = os.path.basename(path)
    if name == "main.jsonl":
        return PARENT
    match = SUBAGENT.match(name)
    if match:
        return match.group("agent")
    return name[: -len(".jsonl")] if name.endswith(".jsonl") else name


class Totals:
    """Billed aggregate. Unbilled requests are counted, never summed."""

    def __init__(self) -> None:
        self.requests = 0
        self.unbilled = 0
        self.input_uncached = 0
        self.cached = 0
        self.output = 0
        self.nano_aiu = 0
        self.invocations = 0
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
    per_agent: dict[str, Totals] = {}
    parsed = 0

    for path in log_files(session_dir):
        if not os.path.isfile(path):
            continue
        # Counted from the filename, so an invocation that produced no billed
        # request still shows up as one -- it happened either way.
        agent = per_agent.setdefault(agent_from(path), Totals())
        agent.invocations += 1
        for event in iter_events(path):
            parsed += 1
            kind = event.get("type")
            if kind == "session_start" and session_start is None:
                session_start = event
            elif kind == "llm_request":
                attrs = event.get("attrs") or {}
                try:
                    totals.add(attrs)
                    agent.add(attrs)
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
        # The per-agent split inherits that bias and is withheld with it.
        result["coverage"] = "truncated"
        result["totals"] = None
        result["by_agent"] = None
        return result

    started = session_start.get("ts")
    if workflow_start is not None and isinstance(started, int) and started > workflow_start:
        result["coverage"] = "partial"
    else:
        result["coverage"] = "full"
    result["totals"] = totals
    result["by_agent"] = per_agent
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
    lines.extend(_by_agent(result.get("by_agent")))
    lines.append(f"  environment: {{ vscode: {_scalar(env['vscode'])}, copilot_chat: {_scalar(env['copilot_chat'])} }}")
    return "\n".join(lines) + "\n"


def _by_agent(per_agent: dict[str, Totals] | None) -> list[str]:
    """Which log each request came from, keyed by agent (issue #212).

    `totals` carries the same fields as the session totals so the split
    reconciles against them, and `by_model` resolves the two axes jointly:
    "the implementer is expensive" and "opus is expensive" are different
    findings, and only the crossing says which agent to move off which model.
    """
    if per_agent is None:
        # Withheld, not empty: `{}` would read as "no agent consumed anything".
        return ["  by_agent: null"]
    if not per_agent:
        return ["  by_agent: {}"]
    lines = ["  by_agent:"]
    # Most expensive first: the block exists to be acted on, and the reader
    # who stops after two lines should have read the two that matter.
    order = sorted(per_agent.items(), key=lambda kv: (-kv[1].nano_aiu, kv[0]))
    for agent, bucket in order:
        lines.append(f"    {agent}:")
        lines.append(
            f"      totals: {{ invocations: {bucket.invocations}, requests: {bucket.requests}, "
            f"unbilled_requests: {bucket.unbilled}, input_uncached: {bucket.input_uncached}, "
            f"cached: {bucket.cached}, output: {bucket.output}, credits: {bucket.credits} }}"
        )
        if not bucket.by_model:
            lines.append("      by_model: {}")
            continue
        lines.append("      by_model:")
        for model, sub in sorted(bucket.by_model.items()):
            credits = round(sub["nano_aiu"] / NANO_AIU_PER_CREDIT, 3)
            lines.append(f"        {model}: {{ requests: {sub['requests']}, credits: {credits} }}")
    return lines


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
