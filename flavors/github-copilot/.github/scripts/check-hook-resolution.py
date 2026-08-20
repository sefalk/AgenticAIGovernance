#!/usr/bin/env python3
"""Static drift guard for hook path, config and interpreter resolution.

A shared preamble removes the duplication, but it does not stop the *next*
hook from being written the old way -- and the old way fails silently, which
is precisely why it survived across ~20 files. This checker turns that silence
into a test failure.

Usage:
    check-hook-resolution.py <path> [<path> ...]

Each path may be a file or a directory (scanned recursively for ``*.sh`` and
``*.ps1``). Exits non-zero if any violation is found.

Escape hatch: append ``af-resolution-ok`` in a comment on the offending line
together with a reason. Deliberate exceptions should be visible, not silent.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# Files that legitimately contain the raw resolution logic.
EXEMPT_NAMES = {"_common.sh", "_common.ps1"}

ESCAPE_HATCH = "af-resolution-ok"

# Any of these on the same line proves the path is anchored to the script
# location rather than to the current working directory.
ROOT_ANCHORS = re.compile(
    r"AF_MAIN_ROOT|AF_CODE_ROOT|AF_CONF\b|AfMainRoot|AfCodeRoot|AfConfPath"
    r"|MAIN_ROOT|CODE_ROOT|mainRoot|codeRoot|SCRIPT_DIR|PSScriptRoot"
)

# The config file name also appears in user-facing messages ("add X to
# WEB_FETCH_ALLOWLIST in .github/af-env.conf"). Those are not path resolution.
# Only flag the literal where the line actually consumes it as a path or
# assigns it to a config variable.
PATH_USE = re.compile(
    r"grep|awk|sed|cat\s|Get-Content|Select-String|Test-Path|Join-Path"
    r"|-f\s|-e\s|source\s|(?i:conf\w*|config\w*)\s*="
)

RULES: list[tuple[str, re.Pattern[str], str]] = [
    (
        "AF001",
        re.compile(r"\.github[/\\]af-env\.conf"),
        ("config path is not anchored to the script location -- source _common and use af_conf_get / Get-AfConfig"),
    ),
    (
        "AF002",
        re.compile(r"Join-Path\s+\(Get-Location\)|Join-Path\s+\$PWD|\$\(pwd\)"),
        ("path built from the current working directory -- hooks do not control the cwd they are invoked from"),
    ),
    (
        "AF003",
        re.compile(r"rev-parse\s+--show-toplevel"),
        (
            "repo root taken from git -- resolves to the wrong repo when the "
            "agent process sits elsewhere; use AF_MAIN_ROOT / $AfMainRoot"
        ),
    ),
    (
        "AF004",
        re.compile(r"command\s+-v\s+python|which\s+python|Get-Command\s+['\"]?python"),
        (
            "interpreter taken from a bare PATH lookup -- a resolvable "
            "interpreter is not a working one; use AF_PYTHON / $AfPython"
        ),
    ),
    (
        "AF005",
        # Command position only: `| python3`, `$(python3 ...)`, a bare call at
        # line start. `python3` as a *datum* -- an entry in an interpreter
        # name list, an alternative inside a grep pattern, a candidate in a
        # probe loop -- is not an invocation.
        re.compile(r"(?:^\s*|[|;&]\s+|\$\(\s*)python3\b"),
        (
            "python3 invoked directly -- on Windows that is an App Execution "
            'Alias which runs nothing; call "$AF_PYTHON" / $AfPython'
        ),
    ),
]


def is_comment(line: str, suffix: str) -> bool:
    """Return True if the line is a pure comment for the given file type."""
    stripped = line.strip()
    if suffix == ".ps1":
        return stripped.startswith("#")
    return stripped.startswith("#")


def check_file(path: Path) -> list[str]:
    """Return a list of human-readable violations for one file."""
    if path.name in EXEMPT_NAMES:
        return []
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:  # unreadable file is a real problem, report it
        return [f"{path}: cannot read ({exc})"]

    found: list[str] = []
    for lineno, line in enumerate(text.splitlines(), start=1):
        if ESCAPE_HATCH in line or is_comment(line, path.suffix):
            continue
        for code, pattern, hint in RULES:
            if not pattern.search(line):
                continue
            if code == "AF001" and (ROOT_ANCHORS.search(line) or not PATH_USE.search(line)):
                continue
            found.append(f"{path}:{lineno}: {code} {hint}\n    {line.strip()}")
    return found


def iter_targets(paths: list[str]) -> list[Path]:
    """Expand the given paths into the shell and PowerShell files to scan."""
    targets: list[Path] = []
    for raw in paths:
        p = Path(raw)
        if p.is_dir():
            targets.extend(sorted(q for q in p.rglob("*") if q.suffix in (".sh", ".ps1")))
        elif p.is_file():
            targets.append(p)
    return targets


def main(argv: list[str]) -> int:
    """Scan the given paths and report resolution drift."""
    if len(argv) < 2:
        print("usage: check-hook-resolution.py <path> [<path> ...]", file=sys.stderr)
        return 2

    violations: list[str] = []
    for target in iter_targets(argv[1:]):
        violations.extend(check_file(target))

    if violations:
        # Findings go to stdout, not stderr: the exit code is the machine
        # signal, and native-command stderr turns into a terminating error in
        # PowerShell 5.1 when $ErrorActionPreference = 'Stop' -- even when the
        # caller redirects it away. Only the usage error stays on stderr.
        print("Hook resolution drift detected:\n")
        for v in violations:
            print(f"  {v}")
        print(
            f"\n{len(violations)} violation(s). Source hooks/scripts/_common.{{sh,ps1}} "
            "and resolve from the script location, or annotate the line with "
            f"'{ESCAPE_HATCH}' plus a reason."
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
