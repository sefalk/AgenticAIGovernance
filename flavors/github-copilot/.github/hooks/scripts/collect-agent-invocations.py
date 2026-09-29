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
import json
import os
import re
import sys

from _agentlog import agent_from

KEY = re.compile(r"^(?P<indent>\s*)(?:-\s+)?(?P<key>[A-Za-z_][\w-]*)\s*:(?P<rest>.*)$")
BLOCK_SCALAR = re.compile(r"^[|>][+-]?\d*\s*$")

# `.github/skills/<name>/SKILL.md`, active or parked under `_available/`.
SKILL_PATH = re.compile(r"skills[\\/]+(?:_available[\\/]+)?([\w.-]+)[\\/]+SKILL\.md", re.IGNORECASE)
DECLARED = re.compile(r"Skills Read\W*:\W*(?P<rest>[^\n]*)", re.IGNORECASE)


def _reads_and_declaration(path: str) -> tuple[set[str], set[str] | None]:
    """Skills opened with `read_file` in one log, and the skills its last return declares.

    Only `read_file` arguments count (issue #348). A `grep_search` hit or a path
    quoted in a tool result is not a read. The declaration is None when the
    return carries no `Skills Read:` line -- cut off by the editor's 5000-character
    cap in 289 of 305 truncated returns measured, so absence proves nothing.
    """
    reads: set[str] = set()
    last_response = None
    try:
        with open(path, "rb") as handle:
            for raw in handle:
                if b'"tool_call"' in raw and b"read_file" in raw:
                    try:
                        record = json.loads(raw.decode("utf-8", "replace"))
                    except ValueError:
                        continue
                    if record.get("type") == "tool_call" and record.get("name") == "read_file":
                        args = (record.get("attrs") or {}).get("args")
                        reads.update(m.group(1).lower() for m in SKILL_PATH.finditer(str(args)))
                elif b'"agent_response"' in raw:
                    try:
                        record = json.loads(raw.decode("utf-8", "replace"))
                    except ValueError:
                        continue
                    if record.get("type") == "agent_response":
                        last_response = (record.get("attrs") or {}).get("response")
    except OSError:
        return reads, None

    match = DECLARED.search(last_response) if isinstance(last_response, str) else None
    if not match:
        return reads, None
    # JSON-escaped when the return was truncated and could not be parsed.
    rest = match.group("rest").replace("\\\\", "/").split("\\n", 1)[0]
    return reads, {m.lower() for m in re.findall(r"([\w.-]+)[\\/]+SKILL\.md", rest)}


def skills_read(session_dir: str) -> tuple[dict[str, list[str]], dict[str, list[str]]]:
    """Per agent: skills read, and skills declared in a return but never read."""
    read: dict[str, set[str]] = {}
    declared_only: dict[str, set[str]] = {}
    try:
        names = sorted(os.listdir(session_dir))
    except OSError:
        return {}, {}
    for name in names:
        if name == "main.jsonl":
            agent = "main"
        elif name.startswith("runSubagent-") and name.endswith(".jsonl"):
            agent = agent_from(name)
        else:
            continue
        reads, declared = _reads_and_declaration(os.path.join(session_dir, name))
        read.setdefault(agent, set()).update(reads)
        if declared is not None and declared - reads:
            declared_only.setdefault(agent, set()).update(declared - reads)
    # Read in another invocation of the same agent is still read.
    unread = {a: sorted(s - read.get(a, set())) for a, s in declared_only.items() if s - read.get(a, set())}
    return {a: sorted(s) for a, s in read.items()}, unread


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


def render(
    counts: dict[str, int],
    missing: list[str],
    read: dict[str, list[str]] | None = None,
    unread: dict[str, list[str]] | None = None,
) -> str:
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
    if read:
        lines.append("  # Every read_file of a SKILL.md, per agent -- measured, not declared (#348).")
        lines.append("  # A lower bound: a skill that reached context another way is not seen.")
        lines.append("  skills_read:")
        for agent in sorted(read):
            lines.append(f"    {agent}: [{', '.join(read[agent])}]")
    if unread:
        lines.append("  # Declared under `Skills Read:` in a return, never opened with read_file.")
        lines.append("  skills_declared_not_read:")
        for agent in sorted(unread):
            lines.append(f"    {agent}: [{', '.join(unread[agent])}]")
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
    read, unread = skills_read(args.session_dir)
    sys.stdout.write(render(counts, missing, read, unread) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
