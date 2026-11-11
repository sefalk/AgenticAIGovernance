"""Tell the coordinator, as its subagent returns, which guard runs failed open (#515).

A guard hook that ends in error or timeout lets its tool call through unchecked.
The turn receipt names that at the coordinator's Stop, which is after the
coordinator has already acted on the subagent's result. The coordinator's own
PostToolUse on `runSubagent` is the one channel that reaches the model at the
moment it reads that result (`additionalContext`). Advisory: any failure is None.
"""

from __future__ import annotations

import json
import os
from collections import Counter
from pathlib import Path

from _agentlog import GUARD_HOOKS
from _context_fill import context_line

FAILED = ("error", "non_blocking_error", "timeout")


def _receipt_session_dir(payload: dict) -> Path | None:
    override = os.environ.get("AF_SESSION_DIR")
    if override:
        return Path(override)
    sid = str(payload.get("session_id") or "")
    transcript = str(payload.get("transcript_path") or "")
    if not sid or not transcript or any(c in sid for c in "/\\:"):
        return None
    return Path(transcript).parent.parent / "debug-logs" / sid


def _subagent_log(directory: Path, agent: str, call: str) -> Path | None:
    exact = directory / f"runSubagent-{agent}-{call}.jsonl"
    if agent and exact.is_file():
        return exact
    matches = sorted(directory.glob(f"runSubagent-*-{call}.jsonl"))
    return matches[0] if matches else None


def fail_open_counts(log: Path) -> Counter:
    counts: Counter = Counter()
    with log.open("rb") as handle:
        for line in handle:
            if b'"hook"' not in line:
                continue
            try:
                span = json.loads(line)
            except ValueError:
                continue
            attrs = span.get("attrs") or {}
            if span.get("type") != "hook":
                continue
            failed = span.get("status") not in (None, "ok") or attrs.get("resultKind") in FAILED
            command = str(attrs.get("command") or "")
            guard = next((g for g in GUARD_HOOKS if g in command), None)
            if failed and guard:
                counts[guard] += 1
    return counts


def subagent_receipt(payload: dict) -> dict | None:
    """PostToolUse context for a returning subagent: fail-open guards (#515) and context fill (#519)."""
    if payload.get("tool_name") != "runSubagent":
        return None
    tool_input = payload.get("tool_input") if isinstance(payload.get("tool_input"), dict) else {}
    agent = str(tool_input.get("agentName") or "")
    call = str(payload.get("tool_use_id") or "").split("__vscode-")[0]
    directory = _receipt_session_dir(payload)
    if not call or directory is None or not directory.is_dir():
        return None
    texts = []
    log = _subagent_log(directory, agent, call)
    counts = fail_open_counts(log) if log is not None else {}
    if counts:
        parts = ", ".join(f"{guard} x{n}" for guard, n in sorted(counts.items()))
        texts.append(
            f"FAIL-OPEN guard (#515): in subagent {agent or call}, {parts} ended in error or timeout, "
            "so those tool calls ran unchecked. Treat what they did as unverified, and re-check any "
            "write or terminal command among them before relying on it."
        )
    fill = context_line(directory)
    if fill:
        texts.append(fill)
    if not texts:
        return None
    return {"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "\n\n".join(texts)}}
