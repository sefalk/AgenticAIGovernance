"""Global Stop hook core: lift this turn's actionable gate verdicts to the top level (#478).

Probed 2026-11-02: every hook systemMessage renders as a collapsed "Warning
from Stop hook", but a subagent's verdict sits inside the coordinator's
collapsed thinking and then inside the collapsed subagent block. So
"implementer:Stop -- Green gate NOT RUN" stayed unseen for a week (#473). A
global Stop hook renders under the answer itself, so this one repeats there
the verdicts of this turn that need a human: NOT RUN, block, deny, error.
A clean turn prints nothing, so the warning badge keeps its meaning.

Source: the `hook` spans of the session's own debug logs -- main.jsonl and each
subagent log -- which carry the command and its output. Not VS Code's
Hooks.log: it is per window, mixes every session, and has to be located by
launch folder (the newest one can be empty; #492). The turn is
everything after the session's previous Stop. ``AF_SESSION_DIR`` points the
hook at a fixture session. Advisory: any failure prints ``{}``.
"""

from __future__ import annotations

import importlib.util
import json
import os
import sys
import time
from collections import Counter
from datetime import datetime
from pathlib import Path
from types import ModuleType

ACTIONABLE = ("not_run", "block", "deny", "error")
LABEL = {"not_run": "NOT RUN"}
HOOK_SPAN = b'"type":"hook"'
# Hooks of one Stop event share its timestamp; an earlier Stop is a previous turn.
SAME_EVENT_MS = 1000


def _gate_health() -> ModuleType:
    path = Path(__file__).resolve().parents[2] / "scripts" / "gate-health.py"
    spec = importlib.util.spec_from_file_location("gate_health", path)
    if spec is None or spec.loader is None:
        raise ImportError(path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def session_dir(payload: dict) -> Path | None:
    override = os.environ.get("AF_SESSION_DIR")
    if override:
        return Path(override)
    sid = str(payload.get("session_id") or "")
    transcript = str(payload.get("transcript_path") or "")
    if not sid or not transcript or any(c in sid for c in "/\\:"):
        return None
    # <ws>/GitHub.copilot-chat/transcripts/<sid>.jsonl -> .../debug-logs/<sid>
    return Path(transcript).parent.parent / "debug-logs" / sid


def hook_spans(directory: Path) -> list[dict]:
    spans = []
    for log in sorted(directory.glob("*.jsonl")):
        with log.open("rb") as handle:
            for raw in handle:
                if HOOK_SPAN not in raw:
                    continue
                try:
                    span = json.loads(raw)
                except ValueError:
                    continue
                if isinstance(span, dict) and span.get("type") == "hook" and isinstance(span.get("ts"), int):
                    spans.append(span)
    return spans


def _ms(stamp: object) -> int:
    try:
        return int(datetime.fromisoformat(str(stamp).replace("Z", "+00:00")).timestamp() * 1000)
    except ValueError:
        return int(time.time() * 1000)


def findings(spans: list[dict], now: int, health: ModuleType) -> Counter:
    earlier_stops = [s["ts"] for s in spans if s.get("name") == "Stop" and s["ts"] < now - SAME_EVENT_MS]
    since = max(earlier_stops, default=None)
    hits: Counter = Counter()
    for span in spans:
        ts, event = span["ts"], span.get("name")
        if (since is not None and ts <= since) or (event == "Stop" and ts >= now - SAME_EVENT_MS):
            continue
        attrs = span.get("attrs") or {}
        outcome = "error" if span.get("status") not in (None, "ok") else health.classify(str(attrs.get("output") or ""))
        if outcome not in ACTIONABLE:
            continue
        script = health.script_of(json.dumps({"command": str(attrs.get("command") or "")})) or str(event)
        hits[(script.rsplit(".", 1)[0], LABEL.get(outcome, outcome))] += 1
    return hits


def main() -> int:
    try:
        payload = json.loads(sys.stdin.read() or "{}")
        directory = session_dir(payload) if isinstance(payload, dict) else None
        if directory is not None and directory.is_dir():
            hits = findings(hook_spans(directory), _ms(payload.get("timestamp")), _gate_health())
            if hits:
                parts = [f"{script} {what}" + (f" x{n}" if n > 1 else "") for (script, what), n in sorted(hits.items())]
                print(json.dumps({"systemMessage": "turn findings (#478): " + "; ".join(parts)}))
                return 0
    except (OSError, ValueError, ImportError, AttributeError):
        pass
    print("{}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
