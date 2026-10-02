"""Guard the shape of generated skill indexes, not just their contents.

`validate-skills.py` already cross-referenced `INDEX.md` against the skill
directories, and #112 shipped anyway: the index listed exactly the right
skills and was malformed at the same time -- a duplicated table header stood
above the first heading and rendered as an empty table. Listing and layout are
different properties, and only the first one had an owner.

Two things had to be true for that to reach consumers, so this guards both:

1. Nothing ran `validate-skills.py` in CI. It was reachable only by a human or
   an agent invoking `/af-validate-framework`, so the payload was never
   checked on the pull request that changed it. Step one runs it here.
2. Even once it runs, a layout check can be quietly emptied and the suite
   would still pass, because a check that finds nothing is indistinguishable
   from a check that cannot find anything. Step two feeds it a known-bad
   index and requires it to object.

Step three asserts the property over the rest of the payload's records, since
nothing makes `INDEX.md` the only file an agent writes a table into.
Templates are excluded by design: a template's empty table is a blank form
waiting to be filled in, which is the one place the shape is correct.
"""

from __future__ import annotations

import importlib.util
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PAYLOAD = REPO / "flavors" / "github-copilot" / ".github"
VALIDATOR = PAYLOAD / "scripts" / "validate-skills.py"
SKILLS_ROOT = PAYLOAD / "skills"

TABLE_SEPARATOR = re.compile(r"^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)+\|?\s*$")
TABLE_ROW = re.compile(r"^\s*\|")

# A template is a blank to be completed; an empty table there is the point.
EXCLUDED_DIRS = {"templates"}

# Anti-vacuity floor. A glob that silently stops matching reports zero
# violations, which is the same output as a clean payload.
MIN_RECORDS = 100

BAD_INDEX = """# Skill Index

> Auto-generated index of all AF skills.

| # | Skill | Description | Referenced by |
|---|-------|-------------|---------------|
## Active Skills

| # | Skill | Description | Referenced by |
|---|-------|-------------|---------------|
| 1 | `example` | An example. | someone |
"""

failures: list[str] = []
checks = 0


def check(label: str, condition: bool, detail: str = "") -> None:
    global checks
    checks += 1
    if not condition:
        failures.append(f"{label}{': ' + detail if detail else ''}")


def empty_tables(path: Path) -> list[int]:
    """Return the 1-based line numbers of table headers introducing no rows."""
    hits: list[int] = []
    fenced = False
    lines = path.read_text(encoding="utf-8").splitlines()

    for i, line in enumerate(lines):
        if line.lstrip().startswith("```"):
            fenced = not fenced
            continue
        if fenced or not TABLE_SEPARATOR.match(line):
            continue
        following = lines[i + 1] if i + 1 < len(lines) else ""
        if not TABLE_ROW.match(following):
            hits.append(i)

    return hits


def load_validator():
    """Import the payload validator despite its non-importable filename."""
    spec = importlib.util.spec_from_file_location("af_validate_skills", VALIDATOR)
    if spec is None or spec.loader is None:
        return None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    # A gate whose failure message cannot be printed reports a traceback
    # instead of the fault it found. Windows consoles here are cp1252 and the
    # payload legitimately contains characters it has no code point for.
    sys.stdout.reconfigure(errors="backslashreplace")  # type: ignore[union-attr]

    check("the payload validator exists", VALIDATOR.is_file(), str(VALIDATOR))
    if not VALIDATOR.is_file():
        print("\n".join(f"FAIL {f}" for f in failures))
        return 1

    # 1. The shipped payload passes its own validator. The child writes to a
    # pipe, so without this it would encode its output in the locale codec
    # and the text read back here would be mojibake in the one situation that
    # matters -- the report of a real failure.
    child_env = {**os.environ, "PYTHONIOENCODING": "utf-8"}
    result = subprocess.run(
        [sys.executable, str(VALIDATOR), "--root", str(PAYLOAD)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=child_env,
    )
    check(
        "the shipped skill index passes validate-skills.py",
        result.returncode == 0,
        (result.stdout + result.stderr).strip()[:800],
    )

    # 2. The layout check objects to a known-bad index.
    module = load_validator()
    check("the payload validator is importable", module is not None)
    layout = getattr(module, "validate_index_layout", None) if module else None
    check(
        "validate-skills.py still owns an index layout check",
        callable(layout),
        "validate_index_layout is missing -- the mechanism for #112 was removed",
    )

    if callable(layout):
        with tempfile.TemporaryDirectory() as tmp:
            planted = Path(tmp) / "INDEX.md"
            planted.write_text(BAD_INDEX, encoding="utf-8")
            reported = layout(planted)
        check(
            "the layout check reports a table header that introduces no rows",
            len(reported) >= 1,
            "a planted empty table header went unreported -- the check is vacuous",
        )

    # 3. No payload record carries an empty table header.
    records = [p for p in PAYLOAD.rglob("*.md") if not EXCLUDED_DIRS & set(p.relative_to(PAYLOAD).parts)]
    check(
        "the payload record scan found files",
        len(records) >= MIN_RECORDS,
        f"scanned {len(records)}, floor {MIN_RECORDS} -- raise it as the payload grows",
    )
    for record in records:
        hits = empty_tables(record)
        check(
            f"no empty table header in {record.relative_to(REPO).as_posix()}",
            not hits,
            f"table header at line(s) {', '.join(str(h) for h in hits)}",
        )

    if failures:
        print("\n".join(f"FAIL {f}" for f in failures))
        print(f"\n{len(failures)} of {checks} checks failed")
        return 1
    print(f"OK  skill index layout: {checks} checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
