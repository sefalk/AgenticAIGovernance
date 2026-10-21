"""Decision table for the VERSION/CHANGELOG part of .githooks/pre-commit (#426).

The hook used to bump the patch number of flavors/github-copilot/VERSION on
every framework commit. Every pull request therefore changed the same line, and
any two open at once conflicted on it -- together with the CHANGELOG top-insert,
that made parallel pull requests conflict by construction. VERSION now moves
only at a release cut, and an entry goes into changelog.d/ as a fragment.

The hook enforces the second half: a commit that stages CHANGELOG.md without
staging VERSION is a top-insert, and is refused with the way out. A release
cut stages both. Resolving a merge that touched CHANGELOG.md is not authoring
an entry, so a commit with MERGE_HEAD present passes.

The real hook is copied verbatim into a throwaway repository and executed
there, like test-precommit-format-gate.py does for the formatting half.

Usage:
    python .github/scripts/test-precommit-version-gate.py
"""

# copilot:generated | coordinator | 2026-10-21

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from collections.abc import Callable
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
HOOK = REPO / ".githooks/pre-commit"
FLAVOR = "flavors/github-copilot"


def find_bash() -> str | None:
    git_bash = Path(r"C:\Program Files\Git\bin\bash.exe")
    if git_bash.is_file():
        return str(git_bash)
    return shutil.which("bash")


def git(work: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-c", "user.name=af-test", "-c", "user.email=af-test@example.invalid", *args],
        cwd=work,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


def write(work: Path, name: str, text: str) -> None:
    target = work / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8", newline="\n")


def make_repo(work: Path) -> None:
    git(work, "init", "-q", "-b", "main")
    (work / ".githooks").mkdir()
    shutil.copyfile(HOOK, work / ".githooks/pre-commit")
    write(work, f"{FLAVOR}/VERSION", "1.0.7\n")
    write(work, f"{FLAVOR}/CHANGELOG.md", "# Changelog\n\n## [Unreleased]\n")
    write(work, f"{FLAVOR}/README.md", "readme\n")
    git(work, "add", "--", FLAVOR)
    git(work, "commit", "-q", "--no-verify", "-m", "seed")


def case_source_edit(work: Path) -> None:
    write(work, f"{FLAVOR}/README.md", "readme, edited\n")
    git(work, "add", "--", f"{FLAVOR}/README.md")


def case_fragment(work: Path) -> None:
    write(work, f"{FLAVOR}/changelog.d/426-x.md", "### Fixed\n\n- x\n")
    git(work, "add", "--", f"{FLAVOR}/changelog.d/426-x.md")


def case_changelog_top_insert(work: Path) -> None:
    write(work, f"{FLAVOR}/CHANGELOG.md", "# Changelog\n\n## [Unreleased]\n\n### Fixed\n\n- x\n")
    git(work, "add", "--", f"{FLAVOR}/CHANGELOG.md")


def case_release_cut(work: Path) -> None:
    case_changelog_top_insert(work)
    write(work, f"{FLAVOR}/VERSION", "1.1.0\n")
    git(work, "add", "--", f"{FLAVOR}/VERSION")


def case_merge_resolution(work: Path) -> None:
    case_changelog_top_insert(work)
    (work / ".git/MERGE_HEAD").write_text(git(work, "rev-parse", "HEAD") + "\n", encoding="utf-8")


def case_other_changelog(work: Path) -> None:
    write(work, "core/GOVERNANCE_CHANGELOG.md", "# Governance changelog\n\n- x\n")
    git(work, "add", "--", "core/GOVERNANCE_CHANGELOG.md")


def version_unchanged(work: Path, _out: str) -> str:
    text = (work / f"{FLAVOR}/VERSION").read_text(encoding="utf-8")
    staged = git(work, "diff", "--cached", "--name-only")
    if text != "1.0.7\n":
        return f"VERSION was rewritten to {text!r}"
    if f"{FLAVOR}/VERSION" in staged.splitlines():
        return "VERSION was staged"
    return ""


def names_the_way_out(_work: Path, out: str) -> str:
    return "" if "changelog.d/" in out else "the refusal does not point at changelog.d/"


def nothing(_work: Path, _out: str) -> str:
    return ""


CASES: list[tuple[str, Callable[[Path], None], int, Callable[[Path, str], str]]] = [
    ("a_framework_commit_leaves_VERSION_alone", case_source_edit, 0, version_unchanged),
    ("a_fragment_passes", case_fragment, 0, version_unchanged),
    ("a_CHANGELOG_top_insert_is_refused", case_changelog_top_insert, 1, names_the_way_out),
    ("a_release_cut_stages_both_and_passes", case_release_cut, 0, nothing),
    ("resolving_a_merge_passes", case_merge_resolution, 0, version_unchanged),
    ("another_changelog_is_not_guarded", case_other_changelog, 0, version_unchanged),
]


def main() -> int:
    bash = find_bash()
    if bash is None:
        print("FAIL: no bash found -- the hook cannot be executed, so nothing here is proven.")
        return 2
    if not HOOK.is_file():
        print(f"FAIL: {HOOK} does not exist.")
        return 2

    failures = 0
    for name, setup, want_exit, check in CASES:
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            make_repo(work)
            setup(work)
            proc = subprocess.run([bash, ".githooks/pre-commit"], cwd=work, capture_output=True, text=True)
            out = proc.stdout + proc.stderr
            problem = "" if proc.returncode == want_exit else f"exit={proc.returncode} (want {want_exit})"
            problem = problem or check(work, out)
        failures += 1 if problem else 0
        print(f"[{'FAIL' if problem else 'PASS'}] {name}")
        if problem:
            for line in (problem + "\n" + out).splitlines():
                if line.strip():
                    print(f"        | {line.rstrip()}")

    print()
    print(f"=== {len(CASES) - failures}/{len(CASES)} passed ===")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
