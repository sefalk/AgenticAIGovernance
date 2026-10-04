"""Decision table for check-issue-drift.py.

The detector reads git history and tracked source, so a test needs a repository
rather than a stub. Each case below builds a throwaway repository with commits
and files chosen to exercise one classification rule, runs the real script
against it, and checks which strength group the issue landed in.

Testing it against this repository's own history would assert facts that change
with every merge, so the fixture is synthetic and the expectations are fixed.

Usage:
    python .github/scripts/test-issue-drift.py
"""

from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / ".github/scripts/check-issue-drift.py"

# Subjects committed onto the fixture's default branch, oldest first.
SUBJECTS = [
    "chore: unrelated groundwork",
    "fix: repair the widget (#101)",
    "Closes #102 by rewriting the loader",
    "feat: add the thing (#103)",
    "fix: repair something already closed (#104)",
]

# path -> contents. One line each carries the reference under test.
FILES = {
    "flavors/github-copilot/.github/hooks/pre-commit.ps1": "# See #105 for why this exists\nWrite-Output 'hi'\n",
    "flavors/github-copilot/.github/scripts/run.sh": 'echo "issue #106 is unrelated"\n',
    ".github/scripts/tool.py": "# carried over from #107\nprint(1)\n",
    "README.md": "# Fixture\n\nMentions #108 outside the scanned paths.\n",
}

OPEN_ISSUES = [101, 102, 103, 105, 106, 107, 108]

# issue, expected groups. An empty set means the issue must not be reported.
CASES: list[tuple[str, int, set[str]]] = [
    ("fix_verb_with_reference_is_strong", 101, {"strong"}),
    ("closes_verb_with_reference_is_strong", 102, {"strong"}),
    ("reference_without_verb_is_medium", 103, {"medium"}),
    ("closed_issue_is_not_reported", 104, set()),
    ("comment_mention_is_weak", 105, {"weak"}),
    ("string_literal_mention_is_ignored", 106, set()),
    ("comment_in_repo_own_scripts_is_weak", 107, {"weak"}),
    ("file_outside_scanned_paths_is_ignored", 108, set()),
]

EXPECTED_CHECK_TOTAL = len(CASES) + 5


def git(repo: Path, *args: str) -> None:
    proc = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True)
    if proc.returncode != 0:
        raise SystemExit(f"fixture setup failed: git {' '.join(args)}: {proc.stderr.strip()}")


def build_fixture(root: Path) -> Path:
    repo = root / "fixture"
    repo.mkdir()
    git(repo, "init", "-q", "-b", "main")
    git(repo, "config", "user.email", "fixture@example.invalid")
    git(repo, "config", "user.name", "Fixture")
    for relative, contents in FILES.items():
        path = repo / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")
    git(repo, "add", "--", *FILES)
    git(repo, "commit", "-q", "-m", SUBJECTS[0])
    for subject in SUBJECTS[1:]:
        git(repo, "commit", "-q", "--allow-empty", "-m", subject)
    return repo


def run_detector(repo: Path, open_issues: Path, ref: str = "main") -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "--repo",
            str(repo),
            "--ref",
            ref,
            "--open-issues",
            str(open_issues),
        ],
        capture_output=True,
        text=True,
    )


def parse_groups(output: str) -> dict[str, set[int]]:
    groups: dict[str, set[int]] = {"strong": set(), "medium": set(), "weak": set()}
    current: str | None = None
    for line in output.splitlines():
        if line.startswith("--- "):
            current = next((key for key in groups if line.startswith(f"--- {key}:")), None)
            continue
        match = re.fullmatch(r"  #(\d+)", line)
        if current and match:
            groups[current].add(int(match.group(1)))
    return groups


def check(name: str, passed: bool, detail: str = "") -> int:
    print(f"[{'PASS' if passed else 'FAIL'}] {name}")
    if not passed and detail:
        for line in detail.splitlines():
            print(f"        | {line.rstrip()}")
    return 0 if passed else 1


def main() -> int:
    failures = 0
    checks = 0
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        repo = build_fixture(root)
        open_file = root / "open.txt"
        open_file.write_text("\n".join(str(n) for n in OPEN_ISSUES) + "\n", encoding="utf-8")

        proc = run_detector(repo, open_file)
        checks += 1
        failures += check("detector_exits_zero", proc.returncode == 0, proc.stdout + proc.stderr)
        groups = parse_groups(proc.stdout)

        for name, issue, expected in CASES:
            found = {key for key, numbers in groups.items() if issue in numbers}
            checks += 1
            failures += check(
                name, found == expected, f"#{issue} in {found or '{}'}, expected {expected or '{}'}\n{proc.stdout}"
            )

        checks += 1
        failures += check(
            "reports_the_scanned_file_count",
            "files scanned for comment mentions: 3" in proc.stdout,
            proc.stdout,
        )

        status = subprocess.run(["git", "-C", str(repo), "status", "--porcelain"], capture_output=True, text=True)
        checks += 1
        failures += check("leaves_the_repository_untouched", status.stdout.strip() == "", status.stdout)

        empty = root / "empty.txt"
        empty.write_text("", encoding="utf-8")
        proc_empty = run_detector(repo, empty)
        checks += 1
        failures += check(
            "empty_open_set_is_refused",
            proc_empty.returncode != 0 and "empty" in (proc_empty.stdout + proc_empty.stderr),
            proc_empty.stdout + proc_empty.stderr,
        )

        proc_ref = run_detector(repo, open_file, ref="no-such-branch")
        checks += 1
        failures += check(
            "unknown_ref_is_refused",
            proc_ref.returncode != 0 and "No such ref" in (proc_ref.stdout + proc_ref.stderr),
            proc_ref.stdout + proc_ref.stderr,
        )

    print()
    if checks != EXPECTED_CHECK_TOTAL:
        print(f"FAIL: ran {checks} checks, expected {EXPECTED_CHECK_TOTAL}.")
        print("A check was added or lost without updating EXPECTED_CHECK_TOTAL.")
        return 1
    print(f"=== {checks - failures}/{checks} passed ===")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
