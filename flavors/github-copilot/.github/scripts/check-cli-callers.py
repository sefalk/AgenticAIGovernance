#!/usr/bin/env python3
"""Static guard: a CLI option that only tests use is not a shipped capability.

The durable cost artifacts of #217 were built, documented and covered by
eleven assertions -- and never written, because nothing but the test suite
ever passed ``--facts-out``. That failure mode is silent by construction: the
feature works, its tests pass, and the product does not have it.

This checker turns that silence into a failure. For every long option a Python
CLI under ``<scripts-dir>`` defines, at least one *production* file must name
it: a hook, a workflow, another script. Test harnesses do not count -- they
are the thing being distrusted.

Usage:
    check-cli-callers.py <scripts-dir> [<caller-dir> ...]

With no caller directory the parent of ``<scripts-dir>`` is searched. Exits
non-zero if any option has no production caller.

Escape hatch: put ``af-caller-ok`` in a comment on the ``add_argument`` line,
or on the line directly above it, together with a reason -- an option kept for
humans at a terminal is a legitimate case, but it should be a stated one. A
whole CLI that no hook is meant to invoke opts out by carrying the same marker
in its module docstring.
"""

from __future__ import annotations

import ast
import re
import sys
from pathlib import Path

ESCAPE_HATCH = "af-caller-ok"

# Long options only. A short flag is too small a token to search for without
# matching half the corpus.
OPTION_DEF = re.compile(r"""add_argument\(\s*["'](--[a-z0-9][a-z0-9-]*)["']""")

# Where a caller can plausibly live. Documentation is deliberately absent:
# a flag described in a README is documented, not called.
CALLER_SUFFIXES = {".sh", ".ps1", ".py", ".yml", ".yaml", ".cmd", ".bat"}

# The suites are what this guard exists to distrust, so they cannot vouch for
# an option. `conftest`-style helpers ride along on the same prefix rule.
TEST_PREFIXES = ("test-", "test_")

# A run's own output can quote the command line that produced it. That is a
# record of a call, not a caller: it proves nothing about the next run.
DATA_DIRS = {"logs", "retros"}

# Options that argparse itself understands, or that every CLI offers for the
# human running it. Neither says anything about a shipped capability.
UNIVERSAL = {"--help", "--version"}


def is_test_file(path: Path) -> bool:
    return path.name.startswith(TEST_PREFIXES) or "tests" in path.parts


def is_data_file(path: Path) -> bool:
    return any(part in DATA_DIRS for part in path.parts)


def module_exempt(text: str) -> bool:
    """True if the module docstring declares the whole CLI human-invoked.

    Read from the docstring rather than from a line budget, so the declaration
    cannot be smuggled in as a comment next to the code it exempts.
    """
    try:
        doc = ast.get_docstring(ast.parse(text)) or ""
    except SyntaxError:
        doc = ""
    return ESCAPE_HATCH in doc


def collect_options(script: Path) -> list[tuple[int, str]]:
    """Return the (line number, option) pairs the script defines."""
    text = script.read_text(encoding="utf-8", errors="replace")
    if module_exempt(text):
        return []
    lines = text.splitlines()
    found: list[tuple[int, str]] = []
    for number, line in enumerate(lines, 1):
        previous = lines[number - 2] if number > 1 else ""
        if ESCAPE_HATCH in line or ESCAPE_HATCH in previous:
            continue
        for match in OPTION_DEF.finditer(line):
            option = match.group(1)
            if option not in UNIVERSAL:
                found.append((number, option))
    return found


def caller_texts(roots: list[Path], exclude: Path) -> list[str]:
    texts: list[str] = []
    for root in roots:
        for path in sorted(root.rglob("*")):
            if not path.is_file() or path.suffix not in CALLER_SUFFIXES:
                continue
            if is_test_file(path) or is_data_file(path) or path.resolve() == exclude.resolve():
                continue
            texts.append(path.read_text(encoding="utf-8", errors="replace"))
    return texts


def main(argv: list[str]) -> int:
    if not argv:
        sys.stderr.write(__doc__ or "")
        return 2

    scripts_dir = Path(argv[0])
    if not scripts_dir.is_dir():
        sys.stderr.write(f"not a directory: {scripts_dir}\n")
        return 2

    caller_roots = [Path(p) for p in argv[1:]] or [scripts_dir.parent]
    missing_roots = [str(p) for p in caller_roots if not p.is_dir()]
    if missing_roots:
        sys.stderr.write(f"not a directory: {', '.join(missing_roots)}\n")
        return 2

    violations: list[str] = []
    for script in sorted(scripts_dir.glob("*.py")):
        if is_test_file(script):
            continue
        options = collect_options(script)
        if not options:
            continue
        # Read the corpus once per script: the script itself is excluded, so
        # a CLI cannot vouch for its own option by mentioning it in a docstring.
        texts = caller_texts(caller_roots, exclude=script)
        for number, option in options:
            if not any(option in text for text in texts):
                violations.append(
                    f"{script}:{number}: {option} has no production caller "
                    f"-- only tests would ever pass it"
                )

    for line in violations:
        print(line)
    if violations:
        print(f"\n{len(violations)} option(s) defined but never called outside the test suite.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
