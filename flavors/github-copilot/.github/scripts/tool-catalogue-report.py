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
import re
import sys
from pathlib import Path
from types import ModuleType
from typing import Any

HERE = Path(__file__).resolve().parent
BLOCKED = 2
BUILT_IN = "built-in"
DEFAULT_MODE = "default (no agent)"
# The editor's preamble to a custom agent's body; only the quoted name is taken.
# The dump's content is itself JSON, so the quotes usually arrive escaped.
MODE = re.compile(r'You are currently running in \\?"([^"\\\n]{1,64})\\?" mode')


def _load(path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(path.stem.replace("-", "_"), path)
    if spec is None or spec.loader is None:
        raise ImportError(path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _session_dumps(cost: ModuleType, session_dir: str) -> dict[str, tuple[dt.date, dict[str, int]]]:
    """Per readable tools dump: its date and the schema chars of each group in it.

    A group is dated by the dumps that carried it, not by the session: a server
    switched off mid-session is absent from the later dumps.
    """
    dumps = {}
    for path in glob.glob(os.path.join(session_dir, "tools_*.json")):
        name = os.path.basename(path)
        rows = cost.tool_entities(cost.dump_text(session_dir, name) or "")
        if rows is None:
            continue
        chars: dict[str, int] = {}
        for row in rows:
            chars[row["group"]] = chars.get(row["group"], 0) + row["chars"]
        dumps[name] = (dt.date.fromtimestamp(os.path.getmtime(path)), chars)
    return dumps


def _session_log(cost: ModuleType, session_dir: str) -> tuple[dict[str, int], list[tuple[str, str]]]:
    """Tool calls by group, and (agent mode, tools dump) per request, from the session's own and subagent logs.

    Reads span names and dump file names; from a system prompt only the mode name.
    """
    calls: dict[str, int] = {}
    requests: list[tuple[str, str]] = []
    modes: dict[Any, str] = {}
    for path in cost.log_files(session_dir):
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as handle:
            for line in handle:
                if b'"tool_call"' not in line and b'"llm_request"' not in line:
                    continue
                try:
                    event = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(event, dict):
                    continue
                if event.get("type") == "tool_call":
                    group = cost.tool_group(str(event.get("name") or ""))
                    calls[group] = calls.get(group, 0) + 1
                elif event.get("type") == "llm_request":
                    attrs = event.get("attrs") if isinstance(event.get("attrs"), dict) else {}
                    prompt, tools = attrs.get("systemPromptFile"), attrs.get("toolsFile")
                    if not isinstance(tools, str):
                        continue
                    if prompt not in modes:
                        match = MODE.search(cost.dump_text(session_dir, prompt) or "")
                        modes[prompt] = match.group(1) if match else DEFAULT_MODE
                    requests.append((modes[prompt], tools))
    return calls, requests


def scan(cost: ModuleType, roots: list[str]) -> tuple[list[dict[str, Any]], int]:
    """One record per session with a readable dump, and the count of sessions whose dumps were all unreadable."""
    sessions, unreadable = [], 0
    for root in roots:
        for session_dir in sorted(glob.glob(os.path.join(root, "*"))):
            if not glob.glob(os.path.join(session_dir, "tools_*.json")):
                continue
            dumps = _session_dumps(cost, session_dir)
            if not dumps:
                unreadable += 1
                continue
            date = max(d for d, _ in dumps.values())
            sessions.append({"dir": session_dir, "date": date, "dumps": dumps})
    return sessions, unreadable


def _verdict(group: str, in_window: bool, agent_only: bool, calls: int) -> str:
    if group == BUILT_IN:
        return "built-in (not a server)"
    if not in_window:
        return "agent tools only" if agent_only else "not delivered in window"
    return "in use" if calls else "candidate"


def _mode_table(mode_tokens: dict[str, list[float]]) -> list[str]:
    total = sum(len(v) for v in mode_tokens.values())
    lines = [
        "",
        "| agent mode | requests | share | mean catalogue tok/request |",
        "|---|---:|---:|---:|",
    ]
    for mode, values in sorted(mode_tokens.items(), key=lambda kv: (-len(kv[1]), kv[0])):
        share = round(100 * len(values) / total)
        lines.append(f"| {mode} | {len(values)} | {share} % | {round(sum(values) / len(values))} |")
    return lines


def report(cost: ModuleType, sessions: list[dict[str, Any]], unreadable: int, window_days: int) -> list[str]:
    newest = max(s["date"] for s in sessions)
    cutoff = newest - dt.timedelta(days=window_days)
    window = [s for s in sessions if s["date"] >= cutoff]
    tokens: dict[str, list[float]] = {}
    calls: dict[str, int] = {}
    last_seen: dict[str, dt.date] = {}
    agent_groups: set[str] = set()
    mode_tokens: dict[str, list[float]] = {}
    for s in sessions:
        for date, chars in s["dumps"].values():
            for group in chars:
                last_seen[group] = max(last_seen.get(group, date), date)
    for s in window:
        session_calls, requests = _session_log(cost, s["dir"])
        for group, count in session_calls.items():
            calls[group] = calls.get(group, 0) + count
        unrestricted = {t for m, t in requests if m == DEFAULT_MODE}
        # A dump only agent-mode requests used is that agent's tools: list, not the unrestricted catalogue.
        agent_only = {t for m, t in requests if m != DEFAULT_MODE} - unrestricted
        per_group: dict[str, list[int]] = {}
        for name, (date, chars) in s["dumps"].items():
            if date < cutoff:
                continue
            for group, size in chars.items():
                if name in agent_only:
                    agent_groups.add(group)
                else:
                    per_group.setdefault(group, []).append(size)
        for group, sizes in per_group.items():
            tokens.setdefault(group, []).append(sum(sizes) / len(sizes) / cost.CHARS_PER_TOKEN)
        for mode, name in requests:
            if name in s["dumps"]:
                size = sum(s["dumps"][name][1].values()) / cost.CHARS_PER_TOKEN
                mode_tokens.setdefault(mode, []).append(size)

    first = min(s["date"] for s in sessions)
    lines = [
        f"Corpus: {len(sessions)} sessions ({first} .. {newest}); "
        f"window: {len(window)} sessions ({min(s['date'] for s in window)} .. {newest}), last {window_days} days.",
    ]
    if unreadable:
        lines.append(f"Skipped: {unreadable} session(s) with only unreadable tool dumps.")
    if mode_tokens:
        lines += _mode_table(mode_tokens)
    lines += [
        "",
        "Servers on the unrestricted path; an agent's `tools:` list is its reviewed enablement.",
        "",
        "| group | sessions delivered | mean tok/request | calls | last seen | verdict |",
        "|---|---:|---:|---:|---|---|",
    ]

    def order(group: str) -> float:
        return -sum(tokens[group]) / len(tokens[group]) if group in tokens else 0.0

    for group in sorted(last_seen, key=lambda g: (order(g), g)):
        delivered = tokens.get(group, [])
        mean = round(sum(delivered) / len(delivered)) if delivered else "-"
        verdict = _verdict(group, bool(delivered), group in agent_groups, calls.get(group, 0))
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
