#!/usr/bin/env python3
"""Gate health: what every hook actually decided, per gate, from VS Code's hook log (#475).

A gate that stops gating is invisible. In #473 the producer test gates were
skipped in 15 of 15 live verdicts for a week, and every one of them read PASS.
`test-hooks-integration.ps1` asks whether hooks fire; this asks what they
decided, and flags the gates whose decisions show they are not gating.

Every count is measured from the log. The findings are inferences and say so:

  not-run       the gate reported that it did not run (`NOT RUN`, `skipped`,
                `not measurable`) in at least half of >= --min-runs runs
  never-decided a gate able to block/deny/ask did none of them in >= --quiet-runs
                runs. Often fine; listed so a reader can tell quiet from inert
  never-ran     declared in agent-hooks.json or agent frontmatter (--github-dir)
                but absent from every log read. SessionStart hooks are exempt: a
                log opened mid-session never holds them

Read-only. Prints a table, or JSON with --json. No hook calls it (af-caller-ok:
a report run by hand to audit the gates; the flight report, #476, is its first
planned programmatic caller).

Usage:
    gate-health.py [--log FILE ...] [--logs-root DIR] [--since YYYY-MM-DD]
                   [--github-dir DIR] [--min-runs N] [--quiet-runs N] [--json]

Exit codes: 0 report printed (findings or not), 2 no log found.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

LOG_NAME = "GitHub Copilot Chat Hooks.log"
# What each top-level field of the JSON report is (#477; logs/README.md). Rule ids
# of the inferred findings are defined there too.
FIELD_KINDS = {"logs": "meta", "since": "meta", "gates": "measured", "findings": "inferred", "kinds": "meta"}
LINE = re.compile(r"^(\d{4}-\d{2}-\d{2}) \d{2}:\d{2}:\d{2}\.\d+ \[info\] \[#(\d+)\] \[(\w+)\] (.*)$")
TIMEOUT = re.compile(r"^(\d{4}-\d{2}-\d{2}) .*\[HookExecutor\] Hook command timed out after (\d+)s: (.+)$")
SCRIPT = re.compile(r"hooks/scripts/([^/\s\"]+\.(?:ps1|sh))")
COMMAND = re.compile(r'"command":"((?:[^"\\]|\\.)*)"')

NOT_RUN = re.compile(r"NOT RUN|gate skipped|gates? skipped|not measurable|pytest not found", re.IGNORECASE)
# The loop guard skips on purpose after a block; that is not an inert gate.
GUARD = re.compile(r"stop_hook_active")
DECIDING = ("block", "deny", "ask")
OUTCOMES = (
    "silent",
    "allow",
    "ask",
    "deny",
    "block",
    "pass",
    "warn",
    "advisory",
    "not_run",
    "guard",
    "error",
    "timeout",
)


def script_of(text: str) -> str | None:
    match = COMMAND.search(text)
    command = match.group(1) if match else text
    found = SCRIPT.search(re.sub(r"\\+", "/", command))
    return found.group(1) if found else None


def classify(payload: str) -> str:
    """One hook's Output line -> outcome."""
    data = None
    for candidate in (payload, payload.replace('\\"', '"')):
        try:
            data = json.loads(candidate)
            break
        except ValueError:
            continue
    text = payload if data is None else json.dumps(data)
    if GUARD.search(text):
        return "guard"
    if isinstance(data, dict):
        specific = data.get("hookSpecificOutput")
        if isinstance(specific, dict):
            decision = specific.get("permissionDecision") or specific.get("decision")
            if decision in ("allow", "ask", "deny", "block"):
                return str(decision)
        if data.get("decision") == "block":
            return "block"
        message = str(data.get("systemMessage") or data.get("message") or "")
        if message and NOT_RUN.search(message):
            return "not_run"
        status = str(data.get("status") or "").upper()
        if status in ("WARN", "WARNING", "PENDING"):
            return "warn"
        if message or status:
            return "pass"
        if data.get("additionalContext") or isinstance(specific, dict):
            return "advisory"
        return "silent"
    return "not_run" if NOT_RUN.search(text) else "pass"


def find_logs(root: Path) -> list[Path]:
    return sorted(root.rglob(LOG_NAME)) if root.is_dir() else []


def default_root() -> Path:
    appdata = os.environ.get("APPDATA")
    return Path(appdata) / "Code" / "logs" if appdata else Path.home() / ".config" / "Code" / "logs"


def read_logs(paths: list[Path], since: str) -> dict[str, dict[str, int]]:
    """script -> outcome -> count, plus an 'events' tally per script."""
    stats: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    for path in paths:
        current: dict[tuple[str, str], str] = {}
        settled: set[tuple[str, str, str]] = set()
        try:
            handle = path.open(encoding="utf-8", errors="replace")
        except OSError:
            continue
        with handle:
            for raw in handle:
                line = raw.rstrip("\r\n")
                timed = TIMEOUT.match(line)
                if timed:
                    if timed.group(1) >= since:
                        name = script_of(timed.group(3)) or timed.group(3).strip()
                        stats[name]["timeout"] += 1
                    continue
                match = LINE.match(line)
                if not match:
                    continue
                day, seq, event, message = match.groups()
                if day < since:
                    continue
                key = (seq, event)
                # Anchored: a tool response quoting an earlier log line must not count as a run.
                if message.startswith("Running:"):
                    name = script_of(message)
                    if name:
                        current[key] = name
                        stats[name]["runs"] += 1
                        stats[name]["event:" + event] += 1
                    continue
                name = current.get(key)
                if not name:
                    continue
                unit = (seq, event, name)
                if message.startswith("Completed (Failure)"):
                    stats[name]["error"] += 1
                    settled.add(unit)
                elif message.startswith("Completed") and "no output" in message:
                    stats[name]["silent"] += 1
                    settled.add(unit)
                elif message.startswith("Output:") and unit not in settled:
                    stats[name][classify(message[len("Output:") :].strip())] += 1
                    settled.add(unit)
    return stats


def declared(github_dir: Path) -> dict[str, str]:
    """script -> where it is declared (global event or agent file)."""
    found: dict[str, str] = {}
    hooks_json = github_dir / "hooks" / "agent-hooks.json"
    try:
        data = json.loads(hooks_json.read_text(encoding="utf-8"))
        for event, entries in (data.get("hooks") or {}).items():
            for entry in entries or []:
                for key in ("windows", "command"):
                    name = script_of(json.dumps({"command": str(entry.get(key) or "")}))
                    if name:
                        found.setdefault(name, f"global {event}")
    except (OSError, ValueError, AttributeError):
        pass
    agents = github_dir / "agents"
    if agents.is_dir():
        for agent in sorted(agents.glob("*.agent.md")):
            try:
                text = agent.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            front = text.split("\n---", 1)[0] if text.startswith("---") else ""
            for name in SCRIPT.findall(front.replace("\\", "/")):
                found.setdefault(name, agent.name)
    return found


def findings(stats: dict, decl: dict[str, str], min_runs: int, quiet_runs: int) -> list[dict]:
    out: list[dict] = []
    for name, counts in sorted(stats.items()):
        runs = counts.get("runs", 0)
        not_run = counts.get("not_run", 0)
        if runs >= min_runs and not_run * 2 >= runs:
            out.append(
                {
                    "kind": "not-run",
                    "script": name,
                    "detail": f"reported NOT RUN/skipped in {not_run} of {runs} runs",
                    "basis": "inferred",
                    "rule": "not-run-half",
                }
            )
        able = any(token in name for token in ("-stop.", "pretooluse", "block-dangerous"))
        if able and runs >= quiet_runs and not any(counts.get(d, 0) for d in DECIDING):
            out.append(
                {
                    "kind": "never-decided",
                    "script": name,
                    "detail": f"{runs} runs, 0 block/deny/ask",
                    "basis": "inferred",
                    "rule": "quiet-gate",
                }
            )
    ran = {name.rsplit(".", 1)[0] for name, counts in stats.items() if counts.get("runs", 0)}
    seen: set[str] = set()
    for name, where in sorted(decl.items()):
        stem = name.rsplit(".", 1)[0]
        # One declaration names both dialects; only the host's one runs.
        if "SessionStart" in where or stem in ran or stem in seen:
            continue
        seen.add(stem)
        out.append(
            {
                "kind": "never-ran",
                "script": stem,
                "detail": f"declared in {where}",
                "basis": "inferred",
                "rule": "declared-unseen",
            }
        )
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--log", action="append", default=[], help="a hook log file (repeatable)")
    parser.add_argument("--logs-root", default="", help="search this directory for hook logs")
    parser.add_argument("--since", default="0000-00-00", help="ignore lines before this date (YYYY-MM-DD)")
    parser.add_argument("--github-dir", default="", help="also report declared hooks that never ran")
    parser.add_argument("--min-runs", type=int, default=3)
    parser.add_argument("--quiet-runs", type=int, default=20)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    paths = [Path(p) for p in args.log] or find_logs(Path(args.logs_root) if args.logs_root else default_root())
    paths = [p for p in paths if p.is_file()]
    if not paths:
        print("gate-health: no hook log found", file=sys.stderr)
        return 2

    stats = read_logs(paths, args.since)
    decl = declared(Path(args.github_dir)) if args.github_dir else {}
    found = findings(stats, decl, args.min_runs, args.quiet_runs)

    if args.json:
        report = {
            "logs": len(paths),
            "since": args.since,
            "gates": {name: {k: v for k, v in counts.items() if v} for name, counts in sorted(stats.items())},
            "findings": found,
            "kinds": FIELD_KINDS,
        }
        print(json.dumps(report, indent=2, sort_keys=True))
        return 0

    print(f"gate health -- {len(paths)} log(s), since {args.since} (counts measured, findings inferred)")
    header = f"  {'script':32} {'runs':>5} " + " ".join(f"{o[:7]:>7}" for o in OUTCOMES)
    print(header)
    for name, counts in sorted(stats.items()):
        cells = " ".join(f"{counts.get(o, 0) or '':>7}" for o in OUTCOMES)
        print(f"  {name:32} {counts.get('runs', 0):>5} {cells}")
    print()
    if not found:
        print("  no findings")
    for item in found:
        print(f"  {item['kind'].upper():14} {item['script']}: {item['detail']} ({item['basis']}: {item['rule']})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
