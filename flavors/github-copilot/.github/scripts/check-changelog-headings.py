#!/usr/bin/env python3
"""Fail when a CHANGELOG section repeats a `###` heading kind (issue #322).

The five duplicate headings this guard was written for were not five mistakes.
They are the visible end of a loop: the correct way to add an entry is to
append under the existing `### Changed`, but in a 6,800-line file nothing tells
an author that the heading already exists 1,300 lines up, so a second one is
created. The next author then faces two equally plausible "existing" headings,
picks one, and the file drifts further. `[1.22.0]` reached six `### Changed`
that way. Removing the six by hand fixes six instances and prevents none.

Two rules:

  CH001  a `###` kind appears more than once inside one `## ` section
  CH002  a `###` kind is not one of the six Keep a Changelog kinds

Two strictnesses, because the two kinds of section are not the same object:

  [Unreleased]       strict -- any finding fails. This is the only section
                     anyone writes into, so this is where the loop is cut.
  released sections  ratchet -- findings are counted against a ceiling that
                     may fall and never rise. A released section records what
                     shipped; restructuring it is a separate decision from
                     preventing the next duplicate.

Enforcing only `[Unreleased]` was considered and rejected: `[1.22.0]`
accumulated its six *while it was* `[Unreleased]`, and a rule that stops
asserting the moment a release is cut would not have caught them. Under the
split above it would have -- and a section enters the ratchet at zero, so the
ceiling is a one-way door.

Usage:
    check-changelog-headings.py CHANGELOG.md [more.md ...]
    check-changelog-headings.py --print-baseline

Exit 0 clean, 1 on any finding that is not covered by the ceilings.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# Recorded on 2026-09-23 against flavors/github-copilot/CHANGELOG.md. These are
# ceilings for RELEASED sections only; `[Unreleased]` contributes nothing to
# them and never may. MAY ONLY SHRINK -- raising either one means a new
# duplicate was written, which is the defect this file exists to stop.
LEGACY_DUPLICATE_SECTIONS = 4
LEGACY_NONSTANDARD_KINDS = 19

KEEP_A_CHANGELOG_KINDS = frozenset({"Added", "Changed", "Deprecated", "Removed", "Fixed", "Security"})

_SECTION = re.compile(r"^##\s+(?P<title>\S.*?)\s*$")
_KIND = re.compile(r"^###\s+(?P<kind>\S.*?)\s*$")
_FENCE = re.compile(r"^\s*(```|~~~)")

# A section with no `## ` above it is malformed rather than released, so it is
# held to the strict rule instead of being quietly counted.
_ORPHAN = "(outside any release section)"


class Section:
    def __init__(self, title: str, line: int) -> None:
        self.title = title
        self.line = line
        self.kinds: dict[str, list[int]] = {}

    @property
    def is_unreleased(self) -> bool:
        return self.title.lower().lstrip("[").startswith("unreleased")


def parse_sections(text: str) -> list[Section]:
    """Split a CHANGELOG into `## ` sections and the `### ` kinds inside them.

    Fenced blocks are skipped: a changelog documents code, and code samples
    contain lines that start with `### `. Counting those would produce
    findings nobody can act on.
    """
    sections: list[Section] = []
    current: Section | None = None
    in_fence = False

    for number, line in enumerate(text.splitlines(), start=1):
        if _FENCE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue

        match = _SECTION.match(line)
        if match:
            current = Section(match.group("title"), number)
            sections.append(current)
            continue

        match = _KIND.match(line)
        if match:
            if current is None:
                current = Section(_ORPHAN, number)
                sections.append(current)
            current.kinds.setdefault(match.group("kind"), []).append(number)

    return sections


def check(path: Path) -> tuple[list[str], int, int]:
    """Return (findings, released sections with a duplicate, released odd kinds)."""
    findings: list[str] = []
    duplicate_sections = 0
    nonstandard_kinds = 0

    for section in parse_sections(path.read_text(encoding="utf-8")):
        strict = section.is_unreleased or section.title == _ORPHAN
        has_duplicate = False

        for kind, lines in section.kinds.items():
            if len(lines) > 1:
                has_duplicate = True
                if strict:
                    where = ", ".join(str(n) for n in lines)
                    findings.append(f"CH001 {section.title} '### {kind}' appears {len(lines)} times (lines {where})")
            if kind not in KEEP_A_CHANGELOG_KINDS:
                if strict:
                    where = ", ".join(str(n) for n in lines)
                    findings.append(
                        f"CH002 {section.title} '### {kind}' is not a Keep a Changelog kind (lines {where})"
                    )
                else:
                    nonstandard_kinds += len(lines)

        if has_duplicate and not strict:
            duplicate_sections += 1

    return findings, duplicate_sections, nonstandard_kinds


def main(argv: list[str]) -> int:
    if "--print-baseline" in argv:
        print(f"duplicate-sections={LEGACY_DUPLICATE_SECTIONS}")
        print(f"nonstandard-kinds={LEGACY_NONSTANDARD_KINDS}")
        return 0

    paths = [Path(a) for a in argv if not a.startswith("-")]
    if not paths:
        print("usage: check-changelog-headings.py CHANGELOG.md [more.md ...]")
        return 1

    findings: list[str] = []
    duplicate_sections = 0
    nonstandard_kinds = 0

    for path in paths:
        # A guard that cannot read its input refuses rather than waves through
        # (#251) -- but it says why in one line instead of a stack trace.
        if not path.is_file():
            print(f"CH000 cannot read '{path}'")
            return 1
        found, dupes, odd = check(path)
        findings.extend(found)
        duplicate_sections += dupes
        nonstandard_kinds += odd

    over_ceiling = duplicate_sections > LEGACY_DUPLICATE_SECTIONS or nonstandard_kinds > LEGACY_NONSTANDARD_KINDS

    for finding in findings:
        print(finding)
    if over_ceiling:
        print(
            "CH003 released sections got worse, not better: the ceilings in check-changelog-headings.py may only shrink"
        )

    print(f"measured-duplicate-sections={duplicate_sections} ceiling={LEGACY_DUPLICATE_SECTIONS}")
    print(f"measured-nonstandard-kinds={nonstandard_kinds} ceiling={LEGACY_NONSTANDARD_KINDS}")

    return 1 if findings or over_ceiling else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
