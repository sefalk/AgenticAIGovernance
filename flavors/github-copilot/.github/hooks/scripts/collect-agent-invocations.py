#!/usr/bin/env python3
"""Record which subagents actually ran, from the editor's own debug logs.

Issue #173. A Deep-tier workflow log carried a complete `agent: arbiter` step
-- action, verdict, review findings -- for an arbiter that was never invoked,
alongside `escalations: 1` for a workflow with zero escalations. Only the
coordinator's cross-check caught it. Every field in `steps[]` is authored by a
language model, and nothing downstream could tell an account of a run from an
account of a plausible run.

The editor writes one `runSubagent-{agent}-{toolcallid}.jsonl` per subagent
invocation, beside `main.jsonl`. That naming is a machine-written record of
which agents ran, and it never passes through a model. This tool reads the
directory and emits what it found, on the same principle that already stamps
`started:`/`completed:` and appends the cost block in `documenter-stop`
(issue #91): a value a model can get wrong should be measured, not requested.

WHAT THIS IS NOT. The count covers ONE chat session. A workflow spanning
several sessions -- or resumed after a window closed -- records only the
session that finalised it, so `observed` is a LOWER BOUND and is labelled as
one in the emitted block. For the same reason nothing here blocks: a watchdog
that fails a legitimate multi-session workflow gets switched off, and a hook
nobody runs protects nothing (issue #108).

What it does instead is make the contradiction explicit rather than merely
discoverable. When `--log` is given, any agent named in `steps[]` that has no
invocation log is listed under `claimed_without_invocation`. A reader who sees
that key does not have to reconstruct anything -- and when the whole workflow
ran in one session, that list is exactly the set of fabricated steps.

Stdlib only, on purpose -- a gate that needs `pip install` stops being run.

Usage:
    collect-agent-invocations.py --session-dir <dir> [--log <workflow-log>]

Exit codes:
    0  a block was written to stdout
    1  nothing measurable (no session dir, or no subagent logs in it)
"""

from __future__ import annotations

import argparse
import os
import re
import sys

# `runSubagent-ado-pr-manager-toolu_011DEuS1yqmhJkPQa1qmtY3U.jsonl`
# The agent name itself contains hyphens, so the split is on the LAST one:
# the trailing segment is the tool-call id (observed 2026-08-21: `toolu_` plus
# alphanumerics, no hyphen). A future id format carrying hyphens would move the
# boundary, which is why a non-matching name falls back to the whole stem
# rather than being dropped -- an unparsed name must not become a silent zero.
SUBAGENT = re.compile(r"^runSubagent-(?P<agent>.+)-(?P<call>[^-]+)\.jsonl$")

KEY = re.compile(r"^(?P<indent>\s*)(?:-\s+)?(?P<key>[A-Za-z_][\w-]*)\s*:(?P<rest>.*)$")
BLOCK_SCALAR = re.compile(r"^[|>][+-]?\d*\s*$")


def agent_from(filename: str) -> str:
    match = SUBAGENT.match(filename)
    if match:
        return match.group("agent")
    return filename[len("runSubagent-") : -len(".jsonl")]


def observed(session_dir: str) -> dict[str, int]:
    """Invocations per agent, counted from the log filenames."""
    counts: dict[str, int] = {}
    try:
        names = os.listdir(session_dir)
    except OSError:
        return counts
    for name in sorted(names):
        if name.startswith("runSubagent-") and name.endswith(".jsonl"):
            agent = agent_from(name)
            counts[agent] = counts.get(agent, 0) + 1
    return counts


def claimed(log_path: str) -> list[str]:
    """Agent names appearing in the log's `steps:` section, in order.

    A line scanner rather than a YAML parse: the same choice
    `check-workflow-log.py` makes, and for the same reason -- PyYAML may be
    absent, and a gate that needs an install stops being run. Block-scalar
    bodies are skipped, because a `description: |` may legitimately contain a
    line that reads `agent: arbiter` and scanning it would invent a finding.
    """
    try:
        with open(log_path, encoding="utf-8", errors="replace") as handle:
            text = handle.read()
    except OSError:
        return []

    names: list[str] = []
    in_steps = False
    skip_below: int | None = None
    for line in text.splitlines():
        indent = len(line) - len(line.lstrip())
        if skip_below is not None:
            if line.strip() and indent > skip_below:
                continue
            skip_below = None

        match = KEY.match(line)
        if match and not match.group("indent") and not line.lstrip().startswith("-"):
            in_steps = match.group("key") == "steps"
            continue
        if not match:
            continue
        if BLOCK_SCALAR.match(match.group("rest").strip()):
            skip_below = len(match.group("indent"))
            continue
        if in_steps and match.group("key") == "agent":
            value = match.group("rest").strip().strip("'\"").split(" #", 1)[0].strip()
            if value and value not in names:
                names.append(value)
    return names


def render(counts: dict[str, int], missing: list[str]) -> str:
    lines = [
        "# Measured by documenter-stop from the editor's subagent debug logs,",
        "# so these counts never passed through a language model (issue #173).",
        "# One chat session: a workflow resumed in a later session records only",
        "# the finalising one, which makes `observed` a lower bound.",
        "agent_invocations:",
        "  observed:",
    ]
    for agent in sorted(counts):
        lines.append(f"    {agent}: {counts[agent]}")
    if missing:
        lines.append("  # Named in steps[] with no invocation log in this session. If the")
        lines.append("  # whole workflow ran in one session, these steps did not happen.")
        lines.append("  claimed_without_invocation:")
        for agent in missing:
            lines.append(f"    - {agent}")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Record which subagents actually ran.")
    parser.add_argument("--session-dir", required=True)
    parser.add_argument("--log", default=None, help="workflow log to cross-check steps[] against")
    args = parser.parse_args(argv)

    counts = observed(args.session_dir)
    if not counts:
        # No subagent log is not "no subagent ran" -- it is also what an absent
        # session directory looks like. Neither is worth a block that asserts
        # zero, so nothing is written (issue #59: an unrun check is not a pass).
        return 1

    missing = [a for a in claimed(args.log) if a not in counts] if args.log else []
    sys.stdout.write(render(counts, missing) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
