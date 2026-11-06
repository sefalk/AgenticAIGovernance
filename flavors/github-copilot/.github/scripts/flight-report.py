#!/usr/bin/env python3
"""Flight report: one offline HTML page per chat session (#476).

Joins three records AF already keeps, on one time axis:

  lanes   one per session log (main + each subagent): span, requests, edits
  gates   one cell per hook verdict that names this session (gate-health.py)
  cost    credits by agent x model (collect-session-cost.py), with its coverage
  log     spawns, ends, edits and the gate verdicts that decided or did not run

Read-only. It writes its one output file and nothing else, loads nothing from
the network, and copies no prompt, argument or tool text: only names, counts
and timestamps. Every panel declares its kind (logs/README.md, #477).

Run by hand to inspect a session (af-caller-ok: no hook invokes it; the
documenter may link the file it writes).

Usage:
    flight-report.py --session-dir DIR [--log FILE ...] [--out FILE]

Exit codes: 0 report written, 2 no session (directory or main.jsonl missing).
"""

from __future__ import annotations

import argparse
import html
import importlib.util
import os
import sys
from pathlib import Path
from types import ModuleType
from typing import Any

HERE = Path(__file__).resolve().parent
NANO_AIU_PER_CREDIT = 1_000_000_000
# Verdicts worth a log line; silent passes are on the strip, not in the log.
LOGGED = ("deny", "block", "ask", "not_run", "error", "timeout")


def _load(path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(path.stem.replace("-", "_"), path)
    if spec is None or spec.loader is None:
        raise ImportError(path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def lanes(cost: ModuleType, agentlog: ModuleType, session_dir: str, facts: list[dict[str, Any]]) -> list[dict]:
    out = []
    for path in cost.log_files(session_dir):
        if not os.path.isfile(path):
            continue
        first, last, edited = agentlog.scan_edits(path)
        log = os.path.basename(path)
        mine = [f for f in facts if f.get("log") == log]
        out.append(
            {
                "agent": cost.agent_from(path),
                "log": log,
                "start": first,
                "end": last,
                "requests": len(mine),
                "credits": round(sum(f["nano_aiu"] or 0 for f in mine) / NANO_AIU_PER_CREDIT, 3),
                "edits": len(edited),
            }
        )
    return sorted(out, key=lambda lane: (lane["start"] is None, lane["start"] or 0, lane["agent"]))


def cost_rows(facts: list[dict[str, Any]]) -> list[dict]:
    buckets: dict[tuple[str, str], dict] = {}
    for fact in facts:
        if not fact.get("billed"):
            continue
        row = buckets.setdefault((fact["agent"], fact["model"]), {"requests": 0, "nano": 0})
        row["requests"] += 1
        row["nano"] += fact["nano_aiu"] or 0
    rows = [
        {"agent": a, "model": m, "requests": b["requests"], "credits": round(b["nano"] / NANO_AIU_PER_CREDIT, 3)}
        for (a, m), b in buckets.items()
    ]
    return sorted(rows, key=lambda r: (-r["credits"], r["agent"], r["model"]))


def gate_cells(health: ModuleType, logs: list[Path], session: str) -> list[dict]:
    cells = [
        r
        for r in health.iter_runs(logs)
        if r["type"] == "outcome" and r["session"] == session and r["outcome"] != "timeout"
    ]
    return sorted(cells, key=lambda c: (c["ts"] is None, c["ts"] or 0))


def render(
    session: str,
    lane_rows: list[dict],
    cells: list[dict],
    cost: dict[str, Any],
    rows: list[dict],
    series: dict[str, dict[str, Any]] | None = None,
) -> str:
    e = html.escape
    stamps = [x for lane in lane_rows for x in (lane["start"], lane["end"]) if x is not None]
    stamps += [c["ts"] for c in cells if c["ts"] is not None]
    lo, hi = (min(stamps), max(stamps)) if stamps else (0, 1)
    span = max(hi - lo, 1)

    def pct(value: int) -> float:
        return round(100.0 * (value - lo) / span, 2)

    coverage = cost.get("coverage") or "unavailable"
    cost_kind = "measured" if coverage == "full" else "lower_bound"

    out = [
        "<!doctype html>",
        '<html lang="en"><head><meta charset="utf-8">',
        f"<title>Flight report {e(session)}</title>",
        "<style>",
        "body{font:13px system-ui,sans-serif;margin:1.5em;color:#222}",
        "h2{font-size:15px;margin:1.2em 0 .4em}.kind{color:#666;font-weight:normal}",
        ".axis{position:relative;height:18px;background:#f4f4f4;margin:2px 0}",
        ".bar{position:absolute;top:2px;height:14px;background:#5b8def;min-width:2px}",
        ".label{display:inline-block;width:14em}",
        ".cell{display:inline-block;width:10px;height:14px;margin:1px;background:#ccc}",
        ".allow,.pass,.silent,.advisory{background:#7cc47f}.ask,.warn{background:#e6c34a}",
        ".deny,.block,.error{background:#d9534f}.not_run,.guard{background:#9b59b6}",
        "table{border-collapse:collapse}td,th{padding:2px 8px;border-bottom:1px solid #eee;text-align:left}",
        "</style></head><body>",
        f"<h1>Flight report <code>{e(session)}</code></h1>",
        "<p>Kinds: <b>measured</b> read from a record, <b>inferred</b> by a named rule,"
        " <b>lower_bound</b> known incomplete (logs/README.md, #477).</p>",
        '<section class="panel" data-panel="lanes" data-kind="measured">',
        '<h2>Subagent lanes <span class="kind">measured</span></h2>',
    ]
    for lane in lane_rows:
        start, end = lane["start"], lane["end"]
        left = pct(start) if start is not None else 0
        width = max(pct(end) - left, 0.3) if start is not None and end is not None else 0
        out.append(
            f'<div class="lane" data-lane="{e(lane["agent"])}" data-log="{e(lane["log"])}"'
            f' data-start="{start or 0}" data-end="{end or 0}" data-requests="{lane["requests"]}"'
            f' data-credits="{lane["credits"]}" data-edits="{lane["edits"]}">'
            f'<span class="label">{e(lane["agent"])} &middot; {lane["requests"]} req &middot; '
            f"{lane['edits']} edits</span>"
            f'<div class="axis"><div class="bar" style="left:{left}%;width:{width}%"></div></div></div>'
        )
    out.append("</section>")

    out.extend(_context_panel(lane_rows, series or {}, lo, span))

    out.append('<section class="panel" data-panel="gates" data-kind="measured">')
    out.append(f'<h2>Gate strip <span class="kind">measured, {len(cells)} verdicts</span></h2><div>')
    for c in cells:
        title = f"{c['script']} {c['event']} {c['outcome']}"
        out.append(
            f'<span class="cell {e(c["outcome"])}" data-script="{e(c["script"])}" data-event="{e(c["event"] or "")}"'
            f' data-ts="{c["ts"] or 0}" title="{e(title)}"></span>'
        )
    out.append("</div></section>")

    note = "" if coverage == "full" else f" (coverage {e(coverage)}: at least these credits, never a total)"
    out.append(f'<section class="panel" data-panel="cost" data-kind="{cost_kind}" data-coverage="{e(coverage)}">')
    out.append(f'<h2>Cost by agent &times; model <span class="kind">{cost_kind}{note}</span></h2>')
    out.append("<table><tr><th>agent</th><th>model</th><th>requests</th><th>credits</th></tr>")
    for r in rows:
        out.append(
            f'<tr data-agent="{e(r["agent"])}" data-model="{e(r["model"])}" data-requests="{r["requests"]}"'
            f' data-credits="{r["credits"]}"><td>{e(r["agent"])}</td><td>{e(r["model"])}</td>'
            f"<td>{r['requests']}</td><td>{r['credits']}</td></tr>"
        )
    out.append("</table></section>")

    events: list[tuple[int, str, str]] = []
    for lane in lane_rows:
        if lane["start"] is not None:
            events.append((lane["start"], "start", f"{lane['agent']} starts"))
        if lane["end"] is not None:
            events.append((lane["end"], "end", f"{lane['agent']} ends, {lane['edits']} file(s) edited"))
    for c in cells:
        if c["outcome"] in LOGGED and c["ts"] is not None:
            events.append((c["ts"], c["outcome"].replace("_", "-"), f"{c['script']} {c['outcome']}"))
    events.sort(key=lambda item: item[0])
    out.append('<section class="panel" data-panel="log" data-kind="measured">')
    out.append('<h2>Log <span class="kind">measured</span></h2><ol>')
    for ts, what, text in events:
        out.append(f'<li data-ts="{ts}" data-what="{e(what)}">+{(ts - lo) / 1000:.1f}s {e(text)}</li>')
    out.append("</ol></section></body></html>")
    return "\n".join(out) + "\n"


def _context_panel(lane_rows: list[dict], series: dict[str, dict[str, Any]], lo: int, span: int) -> list[str]:
    """Input tokens per request, one line per lane; drops are inferred compactions (#479)."""
    e = html.escape
    top = max((s["max"] for s in series.values()), default=1) or 1
    out = [
        '<section class="panel" data-panel="context" data-kind="measured">',
        '<h2>Context per request <span class="kind">measured input tokens;'
        f" drops inferred: a fall of more than half (#479); scale 0..{top}</span></h2>",
    ]
    for lane in lane_rows:
        s = series.get(lane["log"])
        if not s:
            continue
        coords = " ".join(
            f"{round(600 * ((ts or lo) - lo) / span, 1)},{round(40 - 38 * size / top, 1)}"
            for ts, size, _ in s["points"]
        )
        floor = s["floor"] if s["floor"] is not None else "missing"
        note = "" if s["floor"] is not None else " &middot; floor missing: the log lost its head"
        out.append(
            f'<div><span class="label">{e(lane["agent"])} &middot; floor {floor} &middot; median {s["median"]}'
            f" &middot; max {s['max']}{note}</span>"
            '<svg width="600" height="42" style="background:#f4f4f4">'
            f'<polyline class="ctx" data-lane="{e(lane["agent"])}" data-floor="{floor}" data-median="{s["median"]}"'
            f' data-max="{s["max"]}" data-drops="{len(s["drops"])}" points="{coords}"'
            ' fill="none" stroke="#5b8def" stroke-width="1.5"/>'
        )
        for drop in s["drops"]:
            x = round(600 * ((drop["ts"] or lo) - lo) / span, 1)
            out.append(
                f'<circle class="drop" data-kind="inferred" cx="{x}" cy="21" r="4" fill="#d9534f">'
                f"<title>{drop['from']} -> {drop['to']} tokens</title></circle>"
            )
        out.append("</svg></div>")
    out.append("</section>")
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--session-dir", required=True, help="the chat session's debug-log directory")
    parser.add_argument("--log", action="append", default=[], help="a hook log file (repeatable)")
    parser.add_argument("--out", default="", help="output file (default .github/logs/flight-<session>.html)")
    args = parser.parse_args()

    session_dir = os.path.normpath(args.session_dir)
    if not os.path.isfile(os.path.join(session_dir, "main.jsonl")):
        print(f"flight-report: no session at {session_dir}", file=sys.stderr)
        return 2
    session = os.path.basename(session_dir)

    cost_mod = _load(HERE / "collect-session-cost.py")
    health = _load(HERE / "gate-health.py")
    agentlog = _load(HERE.parent / "hooks" / "scripts" / "_agentlog.py")

    cost = cost_mod.collect(session_dir, None)
    facts = cost.get("facts") or []
    logs = [Path(p) for p in args.log] or health.find_logs(health.default_root())

    page = render(
        session,
        lanes(cost_mod, agentlog, session_dir, facts),
        gate_cells(health, [p for p in logs if p.is_file()], session),
        cost,
        cost_rows(facts),
        cost_mod.context_series(facts, head_lost=cost.get("coverage") == "truncated"),
    )
    out = Path(args.out) if args.out else Path(".github") / "logs" / f"flight-{session}.html"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(page, encoding="utf-8")
    print(f"flight-report: wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
