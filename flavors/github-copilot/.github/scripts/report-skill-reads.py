#!/usr/bin/env python3
"""Count, per skill, how many workflows actually read it (issue #348).

#306 had to decide whether activated skills were still consumed and could
only scan chat transcripts: local to one workspace, a lower bound, never
shipped. `documenter-stop` now stamps `agent_invocations.skills_read` into each
workflow log from the editor's own `read_file` calls, so the question is a
query over `.github/logs/`.

Reported per skill: the number of workflow logs in which any agent read it,
and which agents did. Every active skill (`skills/<name>/SKILL.md`, not under
`_available/`) is listed, so a skill nobody reads shows up as 0 instead of
being absent. The header states how many logs carried the block at all:
logs written before #348, or by a session whose debug log was gone, cannot
be counted, and a reader must not mistake them for "read nothing".

Read-only, stdlib only. Invoked by a human or a reviewing agent, never by a
hook (af-caller-ok: a query tool, run by hand for a staleness review like #306).

Usage:
    report-skill-reads.py [--logs DIR] [--skills DIR]
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

GITHUB_DIR = Path(__file__).resolve().parent.parent
ENTRY = re.compile(r"^    (?P<agent>[\w.-]+):\s*\[(?P<skills>[^\]]*)\]\s*$")


def skills_block(text: str) -> dict[str, list[str]] | None:
    """The `skills_read:` mapping inside `agent_invocations`, or None if absent."""
    found: dict[str, list[str]] | None = None
    inside = False
    for line in text.splitlines():
        if line.startswith("agent_invocations:"):
            inside = True
            continue
        if inside and line and not line.startswith(" "):
            break
        if inside and line.rstrip() == "  skills_read:":
            found = {}
            continue
        if found is not None:
            match = ENTRY.match(line)
            if not match:
                if line.strip() and not line.startswith("    "):
                    break
                continue
            names = [s.strip() for s in match.group("skills").split(",") if s.strip()]
            found[match.group("agent")] = names
    return found


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--logs", type=Path, default=GITHUB_DIR / "logs")
    parser.add_argument("--skills", type=Path, default=GITHUB_DIR / "skills")
    args = parser.parse_args(argv)

    logs = sorted(p for p in args.logs.glob("*.y*ml") if p.suffix in (".yaml", ".yml"))
    workflows: dict[str, int] = {}
    agents: dict[str, set[str]] = {}
    measured = 0
    for log in logs:
        block = skills_block(log.read_text(encoding="utf-8", errors="replace"))
        if block is None:
            continue
        measured += 1
        seen: set[str] = set()
        for agent, names in block.items():
            for name in names:
                agents.setdefault(name, set()).add(agent)
                seen.add(name)
        for name in seen:
            workflows[name] = workflows.get(name, 0) + 1

    active = sorted(p.parent.name for p in args.skills.glob("*/SKILL.md"))
    rows = sorted(set(active) | set(workflows), key=lambda n: (-workflows.get(n, 0), n))

    out = [
        f"skill reads: measured in {measured} of {len(logs)} workflow logs "
        f"({len(logs) - measured} without a skills_read block, not counted)",
        f"{'skill':32} {'workflows':>9}  agents",
    ]
    for name in rows:
        who = ", ".join(sorted(agents.get(name, ()))) or "-"
        mark = "" if name in active else "  (not active)"
        out.append(f"{name:32} {workflows.get(name, 0):>9}  {who}{mark}")
    sys.stdout.write("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
