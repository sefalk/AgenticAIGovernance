"""Decision table for .github/scripts/changelog-fragments.py (#426).

Every pull request used to insert its entry at the top of `[Unreleased]` in
flavors/github-copilot/CHANGELOG.md. Two open pull requests therefore always
wrote the same lines, and whichever merged second conflicted -- by construction,
not by accident. A pull request now adds one file under
flavors/github-copilot/changelog.d/, and the release cut folds them into the
changelog in one step. Two files with different names cannot conflict.

`check` is the gate a pull request meets; `assemble` is the release cut. The
assembled changelog is run through the real check-changelog-headings.py, so a
fold that produced a duplicate `###` heading fails here, not at the next PR.

Usage:
    python .github/scripts/test-changelog-fragments.py
"""

# copilot:generated | coordinator | 2026-10-21

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from collections.abc import Callable
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TOOL = REPO / ".github/scripts/changelog-fragments.py"
HEADINGS = REPO / "flavors/github-copilot/.github/scripts/check-changelog-headings.py"

CHANGELOG = """# Changelog

Preamble.

## [Unreleased]

### Changed

- Already in Unreleased (#1).

## [1.0.0] -- 2026-01-01

### Added

- First release.
"""

# The arrow is deliberate: the real changelog is not ASCII, and a Windows
# console encoding crashed the first dry run on it.
ADDED_100 = "### Added\n\n- Hundred (#100) \u2192 now.\n  continued line.\n"
FIXED_99 = "### Fixed\n\n- Ninety-nine (#99).\n\n### Added\n\n- Ninety-nine added (#99).\n"


def run(work: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(TOOL), *args, "--root", str(work)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        env={**os.environ, "PYTHONIOENCODING": ""},
    )


def seed(work: Path, fragments: dict[str, str], version: str = "1.0.7") -> Path:
    (work / "changelog.d").mkdir(parents=True)
    (work / "changelog.d/README.md").write_text("# How to write a fragment\n", encoding="utf-8")
    for name, text in fragments.items():
        (work / "changelog.d" / name).write_text(text, encoding="utf-8", newline="\n")
    (work / "CHANGELOG.md").write_text(CHANGELOG, encoding="utf-8", newline="\n")
    (work / "VERSION").write_text(version + "\n", encoding="utf-8", newline="\n")
    return work


def read(work: Path, name: str) -> str:
    return (work / name).read_text(encoding="utf-8")


# Each case: (name, fragments, args, want_exit, check(work, output) -> problem or "")
def nothing(_work: Path, _out: str) -> str:
    return ""


def mentions(*texts: str) -> Callable[[Path, str], str]:
    def check(_work: Path, out: str) -> str:
        missing = [t for t in texts if t not in out]
        return f"output lacks {missing}" if missing else ""

    return check


def untouched(work: Path, out: str) -> str:
    if read(work, "CHANGELOG.md") != CHANGELOG:
        return "CHANGELOG.md was written"
    if read(work, "VERSION") != "1.0.7\n":
        return "VERSION was written"
    if not (work / "changelog.d/100-hundred.md").is_file():
        return "a fragment was deleted"
    return ""


def assembled(work: Path, out: str) -> str:
    text = read(work, "CHANGELOG.md")
    want = (
        "## [Unreleased]\n\n"
        "## [1.1.0] -- 2026-10-21\n\n"
        "### Added\n\n"
        "- Ninety-nine added (#99).\n\n"
        "- Hundred (#100) \u2192 now.\n  continued line.\n\n"
        "### Changed\n\n"
        "- Already in Unreleased (#1).\n\n"
        "### Fixed\n\n"
        "- Ninety-nine (#99).\n\n"
        "## [1.0.0] -- 2026-01-01\n"
    )
    if want not in text:
        return f"release section not as expected:\n{text}"
    if not text.startswith("# Changelog\n\nPreamble.\n\n"):
        return "the file preamble moved"
    if read(work, "VERSION") != "1.1.0\n":
        return f"VERSION is {read(work, 'VERSION')!r}"
    left = sorted(p.name for p in (work / "changelog.d").iterdir())
    if left != ["README.md"]:
        return f"changelog.d still holds {left}"
    gate = subprocess.run([sys.executable, str(HEADINGS), str(work / "CHANGELOG.md")], capture_output=True, text=True)
    if gate.returncode != 0:
        return f"check-changelog-headings rejects the result:\n{gate.stdout}{gate.stderr}"
    return ""


def dry_run_printed(work: Path, out: str) -> str:
    problem = untouched(work, out)
    if problem:
        return problem
    return (
        ""
        if "## [1.1.0] -- 2026-10-21" in out and "- Hundred (#100) \u2192 now." in out
        else "dry run printed no section"
    )


GOOD = {"100-hundred.md": ADDED_100, "99-ninety-nine.md": FIXED_99}
ASSEMBLE = ("assemble", "--version", "1.1.0", "--date", "2026-10-21")

CASES: list[tuple[str, dict[str, str], tuple[str, ...], int, Callable[[Path, str], str]]] = [
    ("check_passes_well_formed_fragments", GOOD, ("check",), 0, mentions("2 fragment(s)")),
    ("check_passes_an_empty_directory", {}, ("check",), 0, nothing),
    ("check_ignores_the_readme", {}, ("check",), 0, mentions("0 fragment(s)")),
    ("check_rejects_a_name_without_an_issue", {"hundred.md": ADDED_100}, ("check",), 1, mentions("F001", "hundred.md")),
    ("check_rejects_an_uppercase_slug", {"100-Hundred.md": ADDED_100}, ("check",), 1, mentions("F001")),
    ("check_rejects_text_before_the_first_kind", {"1-x.md": "Intro.\n" + ADDED_100}, ("check",), 1, mentions("F002")),
    ("check_rejects_a_fragment_with_no_kind", {"1-x.md": "- loose entry\n"}, ("check",), 1, mentions("F002")),
    ("check_rejects_an_unknown_kind", {"1-x.md": "### Improved\n\n- x\n"}, ("check",), 1, mentions("F003", "Improved")),
    (
        "check_rejects_a_repeated_kind",
        {"1-x.md": ADDED_100 + "\n" + ADDED_100},
        ("check",),
        1,
        mentions("F004", "Added"),
    ),
    ("check_rejects_a_release_heading", {"1-x.md": ADDED_100 + "\n## [2.0.0]\n"}, ("check",), 1, mentions("F005")),
    ("check_rejects_an_empty_kind", {"1-x.md": "### Added\n\n### Fixed\n\n- y\n"}, ("check",), 1, mentions("F006")),
    ("assemble_folds_unreleased_and_fragments", GOOD, ASSEMBLE, 0, assembled),
    ("assemble_dry_run_writes_nothing", GOOD, (*ASSEMBLE, "--dry-run"), 0, dry_run_printed),
    (
        "assemble_refuses_invalid_fragments",
        {**GOOD, "1-x.md": "### Improved\n\n- x\n"},
        ASSEMBLE,
        1,
        untouched,
    ),
    ("assemble_refuses_a_version_not_above_VERSION", GOOD, ("assemble", "--version", "1.0.7"), 1, untouched),
    ("assemble_refuses_a_non_semver_version", GOOD, ("assemble", "--version", "1.1"), 1, untouched),
]


def git(work: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-c", "user.name=af-test", "-c", "user.email=af-test@example.invalid", *args],
        cwd=work,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


# `check --against <ref>` is the CI half of the pre-commit refusal: hooks run
# only in a clone that enabled them, so the pull request is checked as well.
# The flavor sits one directory down, as in the real repository, so a pathspec
# resolved against the wrong directory would see nothing and pass.
def against(edit: Callable[[Path], None], want_exit: int, want_text: str) -> str:
    with tempfile.TemporaryDirectory() as tmp:
        top = Path(tmp)
        git(top, "init", "-q", "-b", "dev")
        work = seed(top / "flavor", {})
        git(top, "add", "--", "flavor")
        git(top, "commit", "-q", "--no-verify", "-m", "base")
        git(top, "switch", "-q", "-c", "feature")
        edit(work)
        git(top, "add", "--", "flavor")
        git(top, "commit", "-q", "--no-verify", "-m", "change")
        proc = run(work, "check", "--against", "dev")
        out = proc.stdout + proc.stderr
        if proc.returncode != want_exit or want_text not in out:
            return f"exit={proc.returncode} (want {want_exit}), want {want_text!r} in: {out}"
        return ""


def top_insert(work: Path) -> None:
    (work / "CHANGELOG.md").write_text(CHANGELOG + "\n- appended\n", encoding="utf-8", newline="\n")


def release_cut(work: Path) -> None:
    top_insert(work)
    (work / "VERSION").write_text("1.1.0\n", encoding="utf-8", newline="\n")


def add_fragment(work: Path) -> None:
    (work / "changelog.d/426-x.md").write_text(ADDED_100, encoding="utf-8", newline="\n")


AGAINST: list[tuple[str, Callable[[], str]]] = [
    ("against_refuses_a_CHANGELOG_edit_without_VERSION", lambda: against(top_insert, 1, "F007")),
    ("against_passes_a_release_cut", lambda: against(release_cut, 0, "fragment(s) ok")),
    ("against_passes_a_fragment", lambda: against(add_fragment, 0, "1 fragment(s) ok")),
]


def nothing_to_release() -> str:
    """A cut with no fragments and an empty [Unreleased] has nothing to say."""
    with tempfile.TemporaryDirectory() as tmp:
        work = seed(Path(tmp), {})
        (work / "CHANGELOG.md").write_text(
            "# Changelog\n\n## [Unreleased]\n\n## [1.0.0] -- 2026-01-01\n\n### Added\n\n- x\n",
            encoding="utf-8",
            newline="\n",
        )
        proc = run(work, *ASSEMBLE)
        if proc.returncode != 1 or "nothing to release" not in proc.stdout + proc.stderr:
            return f"exit={proc.returncode}: {proc.stdout}{proc.stderr}"
        return ""


def main() -> int:
    if not TOOL.is_file():
        print(f"FAIL: {TOOL} does not exist.")
        return 1

    failures = 0
    for name, fragments, args, want_exit, check in CASES:
        with tempfile.TemporaryDirectory() as tmp:
            work = seed(Path(tmp), fragments)
            proc = run(work, *args)
            out = proc.stdout + proc.stderr
            problem = "" if proc.returncode == want_exit else f"exit={proc.returncode} (want {want_exit})"
            problem = problem or check(work, out)
        failures += 1 if problem else 0
        print(f"[{'FAIL' if problem else 'PASS'}] {name}")
        if problem:
            for line in (problem + "\n" + out).splitlines():
                if line.strip():
                    print(f"        | {line.rstrip()}")

    problem = nothing_to_release()
    failures += 1 if problem else 0
    print(f"[{'FAIL' if problem else 'PASS'}] assemble_refuses_when_there_is_nothing_to_release")
    if problem:
        print(f"        | {problem}")

    for name, case in AGAINST:
        problem = case()
        failures += 1 if problem else 0
        print(f"[{'FAIL' if problem else 'PASS'}] {name}")
        if problem:
            for line in problem.splitlines():
                print(f"        | {line.rstrip()}")

    total = len(CASES) + 1 + len(AGAINST)
    print()
    print(f"=== {total - failures}/{total} passed ===")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
