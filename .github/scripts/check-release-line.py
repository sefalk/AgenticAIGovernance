#!/usr/bin/env python3
"""Refuse a pull request that carries commits of the other release line (#537).

`dev` (2.x, Copilot harness) and `release/local-1.28` (1.28.x, Local harness)
are worked by separate sessions. A merge between them carries one line's work
into the other unreviewed. A change both lines need gets one issue and is
implemented on each line separately -- a cherry-pick is a separate commit and
passes, a merge does not.

A pull request into one line fails when HEAD brings any commit that the other
line's tip can reach. The owner's explicit, urgent exception is a body line
`cross-line: <reason>` of at least 10 characters; HTML comments are stripped
first, so the template's commented-out line does not count.

Usage:
    check-release-line.py --base-ref BRANCH [--head REV] [--body-file FILE] [--remote NAME]

Exit 0 when nothing crosses, the crossing is declared, or the base is not a
release line; 1 when refused or when a ref cannot be resolved.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

OTHER_LINE = {"dev": "release/local-1.28", "release/local-1.28": "dev"}
MIN_REASON = 10
_MARKER = re.compile(r"(?m)^[ \t]*cross-line:[ \t]*(.*)$")


def _git(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", *args], capture_output=True, text=True, encoding="utf-8")


def _reachable(head: str, exclude: str) -> list[str] | None:
    proc = _git("rev-list", head, f"^{exclude}")
    return proc.stdout.split() if proc.returncode == 0 else None


def declared_reason(body: str) -> tuple[str, bool]:
    """Return (reason, marker_present) for the first `cross-line:` line long enough to count."""
    text = re.sub(r"(?s)<!--.*?-->", "", body)
    found = False
    for m in _MARKER.finditer(text):
        found = True
        reason = m.group(1).strip()
        if len(reason) >= MIN_REASON:
            return reason, True
    return "", found


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--base-ref", required=True, help="branch the pull request targets")
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--body-file", type=Path)
    parser.add_argument("--remote", default="origin")
    args = parser.parse_args(argv)

    other = OTHER_LINE.get(args.base_ref)
    if other is None:
        print(f"{args.base_ref} is not a release line -- nothing to check.")
        return 0
    base_rev, other_rev = f"{args.remote}/{args.base_ref}", f"{args.remote}/{other}"

    for rev in (base_rev, other_rev, args.head):
        if _git("rev-parse", "--verify", "--quiet", f"{rev}^{{commit}}").returncode != 0:
            print(f"::error::{rev} cannot be resolved. Failing rather than passing on an unanswered question.")
            return 1

    brought = _reachable(args.head, base_rev)
    on_other = _reachable(other_rev, base_rev)
    if brought is None or on_other is None:
        print("::error::Could not list the commits. Failing rather than passing on an unanswered question.")
        return 1
    other_commits = set(on_other)
    crossing = [sha for sha in brought if sha in other_commits]
    if not crossing:
        print(f"Into {args.base_ref}: no commit of {other}.")
        return 0

    body = args.body_file.read_text(encoding="utf-8") if args.body_file else ""
    reason, marker = declared_reason(body)
    print(f"This pull request brings {len(crossing)} commit(s) of {other} into {args.base_ref}:")
    for sha in crossing[:20]:
        print("  " + _git("log", "-1", "--format=%h %s", sha).stdout.strip())
    if reason:
        print(f"Crossing declared: {reason}")
        print("Declared by the owner, not reviewed by this gate.")
        return 0
    if marker:
        print(f"::error::The cross-line: line states no reason. Give one of at least {MIN_REASON} characters.")
        return 1
    print(
        f"::error::{args.base_ref} and {other} are separate release lines and do not merge into each other (#537). "
        "Implement the change on each line separately (an issue, then one pull request per line; a cherry-pick "
        "passes). Only an explicit, urgent owner decision may cross: add 'cross-line: <reason>' to the body."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
