#!/usr/bin/env python3
"""Changelog fragments: one file per pull request, folded in at the release cut (#426).

Every pull request used to insert its entry at the top of `[Unreleased]`, so any
two open pull requests wrote the same lines and the second to merge conflicted.
A pull request now adds `changelog.d/<issue>-<slug>.md` instead; files with
different names cannot conflict. The release cut runs `assemble`, which moves
`[Unreleased]` and every fragment into one new version section and sets VERSION.

A fragment is the body of a changelog section, nothing else:

    ### Fixed

    - **What changed, for whom (#426).** Why it matters.

Rules (`check`):

  F001  name is `<issue>-<slug>.md`, slug lowercase `a-z0-9-` (README.md exempt)
  F002  the first non-blank line is a `### ` heading
  F003  each `### ` kind is one of the six Keep a Changelog kinds
  F004  a kind appears at most once in one fragment
  F005  no `## ` heading -- release sections belong to `assemble`
  F006  no kind is empty
  F007  (`--against REF`) CHANGELOG.md changed since REF without VERSION --
        a top-insert; the CI half of the refusal in .githooks/pre-commit

Usage:
    changelog-fragments.py check [--against REF] [--root DIR]
    changelog-fragments.py assemble --version X.Y.Z [--date YYYY-MM-DD] [--dry-run] [--root DIR]

`--root` is the flavor directory holding CHANGELOG.md, VERSION and changelog.d/
(default: flavors/github-copilot of this repository). Exit 0 ok, 1 on a finding
or a refused cut.
"""

# copilot:generated | coordinator | 2026-10-21

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

DEFAULT_ROOT = Path(__file__).resolve().parents[2] / "flavors" / "github-copilot"
KINDS = ("Added", "Changed", "Deprecated", "Removed", "Fixed", "Security")

_NAME = re.compile(r"^(?P<issue>\d+)-[a-z0-9][a-z0-9-]*\.md$")
_KIND = re.compile(r"^###\s+(?P<kind>\S.*?)\s*$")
_SECTION = re.compile(r"^##\s")
_SEMVER = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")


def _strip_blank(lines: list[str]) -> list[str]:
    start, end = 0, len(lines)
    while start < end and not lines[start].strip():
        start += 1
    while end > start and not lines[end - 1].strip():
        end -= 1
    return lines[start:end]


def parse_fragment(path: Path) -> tuple[dict[str, list[str]], list[str]]:
    """Return ``(kind -> body lines, findings)`` for one fragment."""
    findings: list[str] = []
    if not _NAME.match(path.name):
        findings.append(f"F001 {path.name}: name must be <issue>-<slug>.md with a lowercase a-z0-9- slug")
    sections: dict[str, list[str]] = {}
    current: list[str] | None = None
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if _SECTION.match(line):
            findings.append(f"F005 {path.name}:{number}: '## ' heading -- release sections are written by assemble")
            continue
        m = _KIND.match(line)
        if m:
            kind = m.group("kind")
            if kind not in KINDS:
                findings.append(f"F003 {path.name}:{number}: '### {kind}' is not one of {', '.join(KINDS)}")
            if kind in sections:
                findings.append(f"F004 {path.name}:{number}: '### {kind}' appears twice -- merge the two lists")
            current = sections.setdefault(kind, [])
            continue
        if current is None:
            if line.strip():
                findings.append(f"F002 {path.name}:{number}: text before the first '### ' heading")
            continue
        current.append(line)
    if not sections and not any(f.startswith("F002") for f in findings):
        findings.append(f"F002 {path.name}: no '### ' heading")
    for kind, body in sections.items():
        if not _strip_blank(body):
            findings.append(f"F006 {path.name}: '### {kind}' has no entry")
    return {k: _strip_blank(v) for k, v in sections.items()}, findings


def fragment_paths(root: Path) -> list[Path]:
    folder = root / "changelog.d"
    if not folder.is_dir():
        return []
    paths = [p for p in folder.iterdir() if p.is_file() and p.suffix == ".md" and p.name != "README.md"]

    def order(p: Path) -> tuple[int, str]:
        m = _NAME.match(p.name)
        return (int(m.group("issue")) if m else sys.maxsize, p.name)

    return sorted(paths, key=order)


def _changed_since(root: Path, ref: str, name: str) -> bool:
    """Whether ``name`` (relative to ``root``) differs between merge-base(ref, HEAD) and HEAD.

    Three dots: what this branch changed, not what ``ref`` moved on to since.
    """
    proc = subprocess.run(
        ["git", "-C", str(root), "diff", "--quiet", f"{ref}...HEAD", "--", name],
        capture_output=True,
        text=True,
    )
    if proc.returncode not in (0, 1):
        raise RuntimeError(f"git diff against {ref!r} failed: {proc.stderr.strip()}")
    return proc.returncode == 1


def check(root: Path, against: str | None = None) -> int:
    paths = fragment_paths(root)
    findings = [f for p in paths for f in parse_fragment(p)[1]]
    if against:
        try:
            if _changed_since(root, against, "CHANGELOG.md") and not _changed_since(root, against, "VERSION"):
                findings.append(
                    f"F007 CHANGELOG.md changed since {against} without VERSION -- write the entry as "
                    "changelog.d/<issue>-<slug>.md; only a release cut edits CHANGELOG.md (#426)"
                )
        except RuntimeError as exc:
            print(exc)
            return 1
    for f in findings:
        print(f)
    if findings:
        print(f"{len(findings)} finding(s) in {len(paths)} fragment(s). See changelog.d/README.md.")
        return 1
    print(f"{len(paths)} fragment(s) ok.")
    return 0


def _split_unreleased(lines: list[str]) -> tuple[int, int]:
    start = next((i for i, line in enumerate(lines) if re.match(r"^##\s+\[Unreleased\]\s*$", line)), -1)
    if start < 0:
        raise ValueError("CHANGELOG.md has no '## [Unreleased]' section")
    end = next((i for i in range(start + 1, len(lines)) if _SECTION.match(lines[i])), len(lines))
    return start, end


def _parse_block(lines: list[str]) -> tuple[list[str], dict[str, list[str]]]:
    preamble: list[str] = []
    sections: dict[str, list[str]] = {}
    current = preamble
    for line in lines:
        m = _KIND.match(line)
        if m:
            current = sections.setdefault(m.group("kind"), [])
            if current:
                current.append("")
            continue
        current.append(line)
    return _strip_blank(preamble), {k: _strip_blank(v) for k, v in sections.items()}


def assemble(root: Path, version: str, day: str, dry_run: bool) -> int:
    m = _SEMVER.match(version)
    if not m:
        print(f"--version {version!r} is not X.Y.Z.")
        return 1
    version_file = root / "VERSION"
    current = version_file.read_text(encoding="utf-8").strip() if version_file.is_file() else "0.0.0"
    cm = _SEMVER.match(current)
    if cm and tuple(map(int, m.groups())) <= tuple(map(int, cm.groups())):
        print(f"--version {version} is not above VERSION {current}.")
        return 1

    paths = fragment_paths(root)
    parsed = [(p, *parse_fragment(p)) for p in paths]
    findings = [f for _, _, fs in parsed for f in fs]
    if findings:
        for f in findings:
            print(f)
        print("Refusing to cut a release over invalid fragments.")
        return 1

    changelog = root / "CHANGELOG.md"
    lines = changelog.read_text(encoding="utf-8").splitlines()
    try:
        start, end = _split_unreleased(lines)
    except ValueError as exc:
        print(exc)
        return 1
    preamble, sections = _parse_block(lines[start + 1 : end])
    for _, frag, _ in parsed:
        for kind, body in frag.items():
            target = sections.setdefault(kind, [])
            target.extend([""] if target else [])
            target.extend(body)

    if not preamble and not any(sections.values()):
        print("nothing to release: [Unreleased] is empty and changelog.d/ holds no fragment.")
        return 1

    release = [f"## [{version}] -- {day}", ""]
    if preamble:
        release += [*preamble, ""]
    for kind in [*KINDS, *(k for k in sections if k not in KINDS)]:
        if sections.get(kind):
            release += [f"### {kind}", "", *sections[kind], ""]

    if dry_run:
        print("\n".join(release))
        return 0

    out = [*lines[: start + 1], "", *release, *lines[end:]]
    changelog.write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")
    version_file.write_text(version + "\n", encoding="utf-8", newline="\n")
    for p in paths:
        p.unlink()
    print(f"Released {version}: {len(paths)} fragment(s) folded into CHANGELOG.md, VERSION set.")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    p_check = sub.add_parser("check", help="validate every fragment")
    p_check.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    p_check.add_argument("--against", help="base ref; refuse a CHANGELOG.md change without VERSION since it")
    p_asm = sub.add_parser("assemble", help="release cut: fold [Unreleased] and fragments into a version")
    p_asm.add_argument("--version", required=True)
    p_asm.add_argument("--date", default=date.today().isoformat())
    p_asm.add_argument("--dry-run", action="store_true")
    p_asm.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    args = parser.parse_args(argv)
    # The changelog is not ASCII; a Windows console defaults to cp1252.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if args.command == "check":
        return check(args.root, args.against)
    return assemble(args.root, args.version, args.date, args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
