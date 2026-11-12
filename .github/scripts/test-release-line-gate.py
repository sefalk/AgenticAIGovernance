"""Decision table for .github/scripts/check-release-line.py (#537).

`dev` (2.x, Copilot harness) and `release/local-1.28` (1.28.x, Local harness)
are worked by separate sessions. A merge between them carries one line's work
into the other unreviewed, so a pull request into either line fails when it
brings a commit the other line's tip can reach. The owner's explicit exception
is a `cross-line: <reason>` line in the body.

Each case builds a throwaway repository with both lines as `origin/*` refs, so
the script resolves them exactly as it does on the runner.

Usage:
    python .github/scripts/test-release-line-gate.py
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from collections.abc import Callable
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TOOL = REPO / ".github/scripts/check-release-line.py"
RELEASE = "release/local-1.28"


def git(work: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-c", "user.name=af-test", "-c", "user.email=af-test@example.invalid", *args],
        cwd=work,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


def commit(work: Path, name: str) -> None:
    (work / f"{name}.txt").write_text(name + "\n", encoding="utf-8")
    git(work, "add", "--", f"{name}.txt")
    git(work, "commit", "-q", "--no-verify", "-m", f"commit {name}")


def lines(work: Path, *, publish_release: bool = True) -> None:
    """A shared base, then one commit on each line, published as origin/* refs."""
    git(work, "init", "-q", "-b", "dev")
    commit(work, "base")
    git(work, "switch", "-q", "-c", RELEASE)
    commit(work, "hotfix-on-release")
    git(work, "switch", "-q", "dev")
    commit(work, "feature-on-dev")
    git(work, "update-ref", "refs/remotes/origin/dev", "dev")
    if publish_release:
        git(work, "update-ref", f"refs/remotes/origin/{RELEASE}", RELEASE)


def own_work(base: str) -> Callable[[Path], None]:
    def build(work: Path) -> None:
        git(work, "switch", "-q", "-c", "pr", base)
        commit(work, "own")

    return build


def merges(base: str, other: str) -> Callable[[Path], None]:
    def build(work: Path) -> None:
        git(work, "switch", "-q", "-c", "pr", base)
        git(work, "merge", "-q", "--no-ff", "--no-edit", other)

    return build


def cherry_picks(base: str, other: str) -> Callable[[Path], None]:
    def build(work: Path) -> None:
        git(work, "switch", "-q", "-c", "pr", base)
        git(work, "cherry-pick", other)

    return build


def run(work: Path, base_ref: str, body: str | None) -> subprocess.CompletedProcess[str]:
    args = [sys.executable, str(TOOL), "--base-ref", base_ref]
    if body is not None:
        (work.parent / "body.txt").write_text(body, encoding="utf-8")
        args += ["--body-file", str(work.parent / "body.txt")]
    return subprocess.run(args, cwd=work, capture_output=True, text=True, encoding="utf-8")


DECLARED = "Summary.\n\ncross-line: owner approved, urgent security hotfix\n"

# (name, build, base_ref, body, publish_release, want_exit, want_text)
CASES: list[tuple[str, Callable[[Path], None], str, str | None, bool, int, str]] = [
    ("dev_passes_its_own_work", own_work("dev"), "dev", "", True, 0, "no commit"),
    ("dev_refuses_a_merge_from_release", merges("dev", RELEASE), "dev", "", True, 1, "commit hotfix-on-release"),
    ("dev_refusal_names_the_marker", merges("dev", RELEASE), "dev", "", True, 1, "cross-line:"),
    ("dev_refuses_without_a_body_file", merges("dev", RELEASE), "dev", None, True, 1, "commit hotfix-on-release"),
    ("dev_passes_a_declared_merge", merges("dev", RELEASE), "dev", DECLARED, True, 0, "owner approved"),
    (
        "dev_refuses_a_reason_under_ten_characters",
        merges("dev", RELEASE),
        "dev",
        "cross-line: urgent\n",
        True,
        1,
        "reason",
    ),
    (
        "dev_refuses_a_declaration_inside_an_html_comment",
        merges("dev", RELEASE),
        "dev",
        "<!--\ncross-line: owner approved, urgent security hotfix\n-->\n",
        True,
        1,
        "commit hotfix-on-release",
    ),
    ("dev_passes_a_cherry_pick", cherry_picks("dev", RELEASE), "dev", "", True, 0, "no commit"),
    ("release_passes_its_own_work", own_work(RELEASE), RELEASE, "", True, 0, "no commit"),
    ("release_refuses_a_merge_from_dev", merges(RELEASE, "dev"), RELEASE, "", True, 1, "commit feature-on-dev"),
    ("other_base_is_not_gated", merges("dev", RELEASE), "main", "", True, 0, "not a release line"),
    ("missing_other_line_fails_closed", own_work("dev"), "dev", "", False, 1, f"origin/{RELEASE}"),
]


def main() -> int:
    if not TOOL.is_file():
        print(f"FAIL: {TOOL} does not exist.")
        return 1

    failures = 0
    for name, build, base_ref, body, publish_release, want_exit, want_text in CASES:
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp) / "repo"
            work.mkdir()
            lines(work, publish_release=publish_release)
            build(work)
            proc = run(work, base_ref, body)
            out = proc.stdout + proc.stderr
        problem = ""
        if proc.returncode != want_exit:
            problem = f"exit={proc.returncode} (want {want_exit})"
        elif want_text not in out:
            problem = f"output lacks {want_text!r}"
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
