#!/usr/bin/env python3
"""Tool-catalogue corpus report: what each MCP server costs per request against how often it is called (#221).

The tool schemas delivered with every request depend on which MCP servers the
workstation has enabled, which no repo-scoped gate can see. The debug log dumps
them (``tools_N.json``) and records every ``tool_call``, so cost and use are
measurable after the fact -- but only across many sessions: one session measures
the sample, not the payload.

Read-only. It prints a report and writes nothing; it never disables a server.
A candidate is a server delivered in the window and never called there; whether
to turn it off is a human decision. Only tool names, sizes, counts and dates are
read -- never a call's arguments or result.

Run by hand (af-caller-ok: a human reads the report and decides; no hook acts on it).

Usage:
    tool-catalogue-report.py ROOT [ROOT ...] [--window-days N] [--min-sessions N]

ROOT is a ``debug-logs`` directory whose children are session directories, e.g.
``%APPDATA%/Code/User/workspaceStorage/<hash>/GitHub.copilot-chat/debug-logs``.

Exit codes: 0 report printed, 2 BLOCKED (no session data, or too few sessions in
the window to support a conclusion).
"""

from __future__ import annotations

import argparse
import datetime as dt
import glob
import importlib.util
import json
import os
import sys
from pathlib import Path
from types import ModuleType
from typing import Any

HERE = Path(__file__).resolve().parent
BLOCKED = 2
BUILT_IN = "built-in"


def _load(path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(path.stem.replace("-", "_"), path)
    if spec is None or spec.loader is None:
        raise ImportError(path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _session_catalogue(cost: ModuleType, session_dir: str) -> tuple[dict[str, float], dict[str, dt.date]] | None:
    """Mean tokens per request by group over a session's dumps, and the newest dump date per group.

    A group is dated by the dumps that carried it, not by the session: a server
    switched off mid-session is absent from the later dumps.
    """
    per_group: dict[str, list[int]] = {}
    dates: dict[str, dt.date] = {}
    for path in glob.glob(os.path.join(session_dir, "tools_*.json")):
        rows = cost.tool_entities(cost.dump_text(session_dir, os.path.basename(path)) or "")
        if rows is None:
            continue
        date = dt.date.fromtimestamp(os.path.getmtime(path))
        chars: dict[str, int] = {}
        for row in rows:
            chars[row["group"]] = chars.get(row["group"], 0) + row["chars"]
        for group, total in chars.items():
            per_group.setdefault(group, []).append(total)
            dates[group] = max(dates.get(group, date), date)
    if not dates:
        return None
    means = {g: sum(v) / len(v) / cost.CHARS_PER_TOKEN for g, v in per_group.items()}
    return means, dates


def _session_calls(cost: ModuleType, session_dir: str) -> dict[str, int]:
    """Tool calls by group in the session's own and subagent logs. Reads only the span name."""
    calls: dict[str, int] = {}
    for path in cost.log_files(session_dir):
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as handle:
            for line in handle:
                if b'"tool_call"' not in line:
                    continue
                try:
                    event = json.loads(line)
                except ValueError:
                    continue
                if isinstance(event, dict) and event.get("type") == "tool_call":
                    group = cost.tool_group(str(event.get("name") or ""))
                    calls[group] = calls.get(group, 0) + 1
    return calls


def scan(cost: ModuleType, roots: list[str]) -> tuple[list[dict[str, Any]], int]:
    """One record per session with a readable dump, and the count of sessions whose dumps were all unreadable."""
    sessions, unreadable = [], 0
    for root in roots:
        for session_dir in sorted(glob.glob(os.path.join(root, "*"))):
            if not glob.glob(os.path.join(session_dir, "tools_*.json")):
                continue
            catalogue = _session_catalogue(cost, session_dir)
            if catalogue is None:
                unreadable += 1
                continue
            means, dates = catalogue
            sessions.append({"dir": session_dir, "date": max(dates.values()), "tokens": means, "dates": dates})
    return sessions, unreadable


def _verdict(group: str, in_window: bool, calls: int) -> str:
    if group == BUILT_IN:
        return "built-in (not a server)"
    if not in_window:
        return "not delivered in window"
    return "in use" if calls else "candidate"


def report(cost: ModuleType, sessions: list[dict[str, Any]], unreadable: int, window_days: int) -> list[str]:
    newest = max(s["date"] for s in sessions)
    cutoff = newest - dt.timedelta(days=window_days)
    window = [s for s in sessions if s["date"] >= cutoff]
    tokens: dict[str, list[float]] = {}
    calls: dict[str, int] = {}
    last_seen: dict[str, dt.date] = {}
    for s in sessions:
        for group, date in s["dates"].items():
            last_seen[group] = max(last_seen.get(group, date), date)
    for s in window:
        for group, value in s["tokens"].items():
            if s["dates"][group] >= cutoff:
                tokens.setdefault(group, []).append(value)
        for group, count in _session_calls(cost, s["dir"]).items():
            calls[group] = calls.get(group, 0) + count

    first = min(s["date"] for s in sessions)
    lines = [
        f"Corpus: {len(sessions)} sessions ({first} .. {newest}); "
        f"window: {len(window)} sessions ({min(s['date'] for s in window)} .. {newest}), last {window_days} days.",
    ]
    if unreadable:
        lines.append(f"Skipped: {unreadable} session(s) with only unreadable tool dumps.")
    lines += [
        "",
        "| group | sessions delivered | mean tok/request | calls | last seen | verdict |",
        "|---|---:|---:|---:|---|---|",
    ]

    def order(group: str) -> float:
        return -sum(tokens[group]) / len(tokens[group]) if group in tokens else 0.0

    for group in sorted(last_seen, key=lambda g: (order(g), g)):
        delivered = tokens.get(group, [])
        mean = round(sum(delivered) / len(delivered)) if delivered else "-"
        verdict = _verdict(group, bool(delivered), calls.get(group, 0))
        lines.append(
            f"| {group} | {len(delivered)} | {mean} | {calls.get(group, 0)} | {last_seen[group]} | {verdict} |"
        )
    lines += [
        "",
        "Candidates only -- nothing is disabled. Turning a server off is a human decision;",
        "a server used only in rare workflows (release, deploy) can be a candidate and still be needed.",
    ]
    return lines


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("roots", nargs="+", help="debug-logs directories holding session directories")
    parser.add_argument("--window-days", type=int, default=30, help="judge only sessions this recent (default 30)")
    parser.add_argument("--min-sessions", type=int, default=10, help="fewer sessions in the window is BLOCKED")
    args = parser.parse_args(argv)

    missing = [r for r in args.roots if not os.path.isdir(r)]
    if missing:
        print(f"BLOCKED: root not found: {', '.join(missing)}")
        return BLOCKED
    cost = _load(HERE / "collect-session-cost.py")
    sessions, unreadable = scan(cost, args.roots)
    if not sessions:
        print(f"BLOCKED: no session data -- no readable tools_N.json under {', '.join(args.roots)}.")
        return BLOCKED
    newest = max(s["date"] for s in sessions)
    in_window = sum(1 for s in sessions if s["date"] >= newest - dt.timedelta(days=args.window_days))
    if in_window < args.min_sessions:
        print(
            f"BLOCKED: corpus too small -- {in_window} sessions in the last {args.window_days} days, "
            f"at least {args.min_sessions} needed to call a server unused."
        )
        return BLOCKED
    print("\n".join(report(cost, sessions, unreadable, args.window_days)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
