#!/usr/bin/env python3
"""Validate a workflow log against the schema the documenter is given, and
derive the counters the documenter should never have been asked to write.

Issue #137. `agents/documenter.agent.md` defines a Workflow Log Schema.
Nothing has ever checked a log against it, so the schema described what the
documenter *should* write while the corpus recorded what it *did*: measured
over 55 logs, 25 of 53 readable ones carry a `summary` that contradicts their
own `steps`, six verdicts fall outside the MANIFEST closed set, and two files
are not valid YAML at all.

Two different problems, deliberately given two different mechanisms.

VOCABULARY is a choice the documenter makes and can correct, so it is
reported as a violation: `status` must be one of the schema's values and a step
`verdict` must be in the MANIFEST closed set or explicitly absent.

COUNTERS are not a choice. `summary.retries` and `summary.escalations` are
mechanically derivable from `steps`, which is exactly what
`scripts/analyze-retry-economy.py` does when it reads a corpus. Asking a
language model to author a number it can get wrong, then validating the number,
is strictly worse than not asking. `--fix-counters` computes both from the
steps and rewrites them, on the same principle that already stamps `started:`
and `completed:` in `documenter-stop` (issue #91: a documenter wrote a
`completed:` six and a half hours into the future in the same output that
declared zero fabricated data).

The retry definition here MUST match `analyze-retry-economy.py`: an agent
appearing more than once in one `steps` list. Two tools disagreeing about what
a retry is would be worse than neither existing.

Stdlib only, on purpose -- a gate that needs `pip install` stops being run.
The structural rules are checked by a line scanner rather than a YAML parser,
so there is exactly one implementation of each rule. PyYAML is used only to
answer "does this file parse at all", and when it is absent that single rule
reports `unknown` rather than passing (issue #59: an unrun verification is not
a pass).

Usage:
    check-workflow-log.py --log .github/logs/<id>.yaml
    check-workflow-log.py --log <path> --fix-counters

Exit codes:
    0  the log satisfies every rule that could be checked
    1  at least one violation
    2  the log cannot be checked at all (missing, unreadable)
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

TAG = "[workflow-log]"
OVERRIDE = "ALLOW_WORKFLOW_LOG_SCHEMA"

# agents/documenter.agent.md -- `status: "COMPLETED"  # COMPLETED | FAILED | ESCALATED`
STATUS_VALUES = ("COMPLETED", "FAILED", "ESCALATED")

# MANIFEST § 13, Inter-Agent Contracts -> Verdict Format.
VERDICT_VALUES = ("APPROVED", "REJECTED", "ESCALATE", "RESOLVED", "COMPROMISE")

# A step that was not reviewed says so. These are absence, not vocabulary.
VERDICT_ABSENT = ("", "NULL", "NONE", "~")

KEY = re.compile(r"^(?P<indent>\s*)(?:-\s+)?(?P<key>[A-Za-z_][\w-]*)\s*:(?P<rest>.*)$")
LIST_ITEM = re.compile(r"^(?P<indent>\s*)-\s")
BLOCK_SCALAR = re.compile(r"^[|>][+-]?\d*\s*$")


def _value(rest: str) -> str:
    """The scalar after a `key:`, with quotes and any trailing comment removed."""
    text = rest.strip()
    if text[:1] in ("'", '"'):
        quote = text[0]
        end = text.find(quote, 1)
        return text[1:end] if end > 0 else text[1:]
    return text.split(" #", 1)[0].strip()


def _lines(text: str) -> list[tuple[int, str]]:
    """Line numbers and content, with block-scalar bodies dropped.

    A `description: |` body can contain anything, including a line that looks
    like `verdict: "PROCEEDED"`. Scanning it would invent violations.
    """
    kept: list[tuple[int, str]] = []
    skip_below: int | None = None
    for number, line in enumerate(text.splitlines(), start=1):
        indent = len(line) - len(line.lstrip())
        if skip_below is not None:
            if line.strip() and indent > skip_below:
                continue
            skip_below = None
        kept.append((number, line))
        match = KEY.match(line)
        if match and BLOCK_SCALAR.match(match.group("rest").strip()):
            skip_below = len(match.group("indent"))
    return kept


def _sections(lines: list[tuple[int, str]]) -> dict[str, list[tuple[int, str]]]:
    """Split the document at its top-level keys.

    `verdict` outside `steps` is not a step verdict, and `retries` outside
    `summary` is not the counter. Both distinctions need the boundaries.
    """
    sections: dict[str, list[tuple[int, str]]] = {}
    current: str | None = None
    for number, line in lines:
        match = KEY.match(line)
        if match and not match.group("indent") and not line.lstrip().startswith("-"):
            current = match.group("key")
            sections.setdefault(current, [])
            sections[current].append((number, line))
        elif current is not None:
            sections[current].append((number, line))
    return sections


def _keys(block: list[tuple[int, str]], name: str) -> list[tuple[int, str]]:
    """Every `name:` in a block, as (line number, value)."""
    found = []
    for number, line in block:
        match = KEY.match(line)
        if match and match.group("key") == name:
            found.append((number, _value(match.group("rest"))))
    return found


def _step_agents(steps: list[tuple[int, str]]) -> list[str]:
    return [value for _, value in _keys(steps, "agent")]


def _derive(sections: dict[str, list[tuple[int, str]]]) -> tuple[int, int]:
    """Retries and escalations, counted the way analyze-retry-economy.py counts."""
    steps = sections.get("steps", [])
    seen: set[str] = set()
    retries = 0
    for agent in _step_agents(steps):
        if agent in seen:
            retries += 1
        seen.add(agent)

    escalations = sum(1 for _, verdict in _keys(steps, "verdict") if verdict.strip().upper().startswith("ESCALATE"))
    # A recorded `escalation:` block is an escalation the steps may not carry a
    # verdict for -- a deferral to a human reads as prose, not as ESCALATE. The
    # two kinds are conflated here rather than one of them being lost, and the
    # analyser conflates them identically so the tools cannot disagree.
    if len(sections.get("escalation", [])) > 1:
        escalations = max(escalations, 1)
    return retries, escalations


def _parses(text: str) -> tuple[bool | None, str]:
    try:
        import yaml
    except ImportError:
        return None, "PyYAML absent -- the parse rule was not run"
    try:
        yaml.safe_load(text)
    except yaml.YAMLError as exc:
        return False, f"not parsable as YAML ({type(exc).__name__})"
    return True, ""


def _findings(text: str) -> tuple[list[str], list[str]]:
    """Violations, and rules that could not be run."""
    violations: list[str] = []
    unchecked: list[str] = []

    parsed, reason = _parses(text)
    if parsed is False:
        violations.append(f"{reason} -- nothing downstream can read it")
    elif parsed is None:
        unchecked.append(reason)

    lines = _lines(text)
    sections = _sections(lines)

    if "status" not in sections:
        violations.append("no top-level `status:` -- the schema requires one")
    else:
        number, value = _keys(sections["status"], "status")[0]
        if value.upper() not in STATUS_VALUES:
            violations.append(
                f"line {number}: status {value!r} is outside the schema's set ({' | '.join(STATUS_VALUES)})"
            )

    steps = sections.get("steps", [])
    if not steps:
        violations.append("no `steps:` section -- a workflow with no recorded steps")

    for number, value in _keys(steps, "verdict"):
        upper = value.strip().upper()
        if upper in VERDICT_ABSENT:
            continue
        # `APPROVED (Attempt 2)` is the verdict with a note; `APPROVED-WITH-ISSUES`
        # is a different word. analyze-retry-economy.py draws the line here too.
        if not any(upper == name or upper.startswith((name + " ", name + "(")) for name in VERDICT_VALUES):
            violations.append(
                f"line {number}: verdict {value!r} is outside the MANIFEST closed set ({'/'.join(VERDICT_VALUES)})"
            )

    return violations, unchecked


def _rewrite_counters(path: Path, text: str) -> list[str]:
    """Replace summary.retries and summary.escalations with the counted values."""
    lines = _lines(text)
    sections = _sections(lines)
    if not sections.get("steps"):
        return []

    retries, escalations = _derive(sections)
    summary = sections.get("summary", [])
    if not summary:
        return []

    raw = text.splitlines()
    changed: list[str] = []
    for name, counted in (("retries", retries), ("escalations", escalations)):
        for number, value in _keys(summary, name):
            index = number - 1
            indent = raw[index][: len(raw[index]) - len(raw[index].lstrip())]
            if value.strip() == str(counted):
                continue
            raw[index] = f"{indent}{name}: {counted}"
            changed.append(f"summary.{name}: {value or 'unset'} -> {counted} (counted from steps)")

    if changed:
        ending = "\r\n" if "\r\n" in text else "\n"
        path.write_text(ending.join(raw) + ending, encoding="utf-8")
    return changed


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", required=True, help="path to the workflow log")
    parser.add_argument(
        "--fix-counters",
        action="store_true",
        help="rewrite summary.retries and summary.escalations from the steps",
    )
    args = parser.parse_args(argv)

    path = Path(args.log)
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        print(f"{TAG} CANNOT CHECK -- {path}: {exc}")
        return 2

    violations, unchecked = _findings(text)

    if args.fix_counters:
        for note in _rewrite_counters(path, text):
            print(f"{TAG} derived {note}")

    for note in unchecked:
        print(f"{TAG} NOT CHECKED -- {note}")

    if violations:
        if os.environ.get(OVERRIDE, "").lower() in ("1", "true", "yes"):
            print(f"{TAG} {path.name}: {len(violations)} violation(s), stood down by {OVERRIDE}")
            for note in violations:
                print(f"{TAG}   {note}")
            return 0
        print(f"{TAG} {path.name}: {len(violations)} schema violation(s)")
        for note in violations:
            print(f"{TAG}   {note}")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
