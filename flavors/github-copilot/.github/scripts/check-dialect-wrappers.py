#!/usr/bin/env python3
"""Drift guard for the dialect-wrapper architecture (issue #287).

AF ships gates in two shells. #287 measured what that costs: not line count,
but that every gate is written, tested and reviewed twice -- and drifts. The
`scan-secrets` twins disagreed on three of four payloads, in both directions,
for months, in a gate whose whole job is to catch secrets.

The answer is one Python core with wrappers too thin to hold logic. A rule in
a README does not stop the next gate from being written the old way, which is
exactly how the twins drifted in the first place. This checker turns the rule
into a test failure.

Rules:
    DW001  a wrapper that has a Python core carries logic instead of
           delegating (too many effective lines)
    DW002  a wrapper that has a Python core never names it
    DW003  a NEW twin pair ships with no Python core at all

DW003 is the ratchet. LEGACY_PAIRS lists the pairs that predate the rule; it
may only shrink, and `test-dialect-wrappers.ps1` holds the ceiling that makes
that binding. Anything not on that list must be Python-backed, so the defect
class cannot come back by simply writing the next gate the old way.

Usage:
    check-dialect-wrappers.py <path> [<path> ...]
    check-dialect-wrappers.py --print-baseline

Escape hatch: put ``af-dialect-ok`` in a comment in BOTH wrappers together
with a reason. Deliberate exceptions should be visible, not silent.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# Pairs that predate the rule. MAY ONLY SHRINK -- see the module docstring.
LEGACY_PAIRS = {
    "block-dangerous",
    "coordinator-postmerge",
    "coordinator-posttooluse",
    "coordinator-pretooluse",
    "documenter-stop",
    "implementer-stop",
    "planner-pretooluse",
    "refactorer-pretooluse",
    "refactorer-stop",
    "researcher-pretooluse",
    "session-context",
    "session-mcp-readiness",
    "stop-tests",
    "test-writer-pretooluse",
    "test-writer-stop",
}

ESCAPE_HATCH = "af-dialect-ok"

# A delegating wrapper resolves an interpreter, marshals stdin and exits. Ten
# lines is comfortable; twenty-five leaves room for an honest degraded-mode
# branch without leaving room for a second implementation.
MAX_EFFECTIVE_LINES = 25

_BLOCK_OPEN = re.compile(r"^\s*<#")
_BLOCK_CLOSE = re.compile(r"#>\s*$")


def effective_lines(text: str) -> int:
    """Lines that carry code: blank lines and comments do not count."""
    count = 0
    in_block = False
    for line in text.splitlines():
        stripped = line.strip()
        if in_block:
            if _BLOCK_CLOSE.search(stripped):
                in_block = False
            continue
        if _BLOCK_OPEN.match(stripped):
            if not _BLOCK_CLOSE.search(stripped):
                in_block = True
            continue
        if not stripped or stripped.startswith("#"):
            continue
        count += 1
    return count


def has_reasoned_hatch(text: str) -> bool:
    """Whether the file carries the escape hatch together with a reason."""
    for line in text.splitlines():
        idx = line.find(ESCAPE_HATCH)
        if idx == -1:
            continue
        reason = line[idx + len(ESCAPE_HATCH) :].lstrip(" :;-\t")
        if len(reason.strip()) >= 10:
            return True
    return False


def collect_pairs(root: Path) -> dict[str, dict[str, Path]]:
    """Stems that ship both a .ps1 and a .sh, mapped to their files."""
    found: dict[str, dict[str, Path]] = {}
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.suffix not in (".ps1", ".sh", ".py"):
            continue
        # Shared libraries are not gates and have no core of their own.
        if path.stem.startswith("_"):
            continue
        found.setdefault(path.stem, {})[path.suffix] = path
    return {stem: files for stem, files in found.items() if ".ps1" in files and ".sh" in files}


def check_pair(stem: str, files: dict[str, Path]) -> list[str]:
    texts = {suffix: path.read_text(encoding="utf-8", errors="replace") for suffix, path in files.items()}
    wrappers = {s: p for s, p in files.items() if s in (".ps1", ".sh")}

    if all(has_reasoned_hatch(texts[s]) for s in wrappers):
        return []

    core = files.get(".py")
    if core is None:
        if stem in LEGACY_PAIRS:
            return []
        return [
            f"{files['.ps1']}: DW003 new dialect twin pair ships with no Python core -- "
            f"put the logic in {stem}.py and reduce {stem}.ps1/{stem}.sh to interpreter "
            f"resolution and stdin marshalling (issue #287)"
        ]

    violations: list[str] = []
    for suffix, path in sorted(wrappers.items()):
        text = texts[suffix]
        if core.name not in text:
            violations.append(
                f"{path}: DW002 wrapper never names its core {core.name} -- it is not delegating, it is a stub"
            )
        count = effective_lines(text)
        if count > MAX_EFFECTIVE_LINES:
            violations.append(
                f"{path}: DW001 wrapper carries logic ({count} effective lines, "
                f"limit {MAX_EFFECTIVE_LINES}) -- move it into {core.name}"
            )
    return violations


def main(argv: list[str]) -> int:
    if "--print-baseline" in argv:
        for stem in sorted(LEGACY_PAIRS):
            print(stem)
        return 0

    targets = [Path(a) for a in argv if not a.startswith("--")]
    if not targets:
        print(__doc__ or "", file=sys.stderr)
        return 2

    violations: list[str] = []
    for target in targets:
        if not target.exists():
            print(f"{target}: not found", file=sys.stderr)
            return 2
        root = target if target.is_dir() else target.parent
        for stem, files in sorted(collect_pairs(root).items()):
            violations.extend(check_pair(stem, files))

    for line in violations:
        print(line)
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
