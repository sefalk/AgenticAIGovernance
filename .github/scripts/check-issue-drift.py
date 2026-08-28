"""List issues that landed work claims to have fixed but that are still open.

Nothing in this repository reconciles merged commits with tracker state, so
fixes land and their issues stay open until someone notices by hand -- the
defect recorded in #231. This script produces that reconciliation on demand.

It reads live repository state and changes nothing. Every line it prints is a
candidate for a human to verify, never a verdict: a commit subject saying it
fixes an issue is a claim, and claims are wrong often enough that closing on
one would be worse than the drift it cures.

Three signals, in descending strength:

  strong  a commit subject on the scanned ref claims a fix (fix/resolve/close)
          and names an issue that is still open
  medium  a commit subject names a still-open issue without claiming a fix --
          work touched it, which is weaker evidence than a fix claim
  weak    a source comment in the hooks and scripts names a still-open issue --
          the code remembers the issue; the tracker may not

The open-issue set comes from `gh issue list` when the GitHub CLI is available,
otherwise from a file given with --open-issues, one issue number per line:

    gh issue list --state open --limit 1000 --json number --jq '.[].number' > open.txt
    python .github/scripts/check-issue-drift.py --open-issues open.txt

Usage:
    python .github/scripts/check-issue-drift.py [--ref origin/main] [--open-issues FILE]
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

CLAIM_VERB = re.compile(r"\b(fix|fixes|fixed|resolve|resolves|resolved|close|closes|closed)\b", re.IGNORECASE)
ISSUE_REF = re.compile(r"#(\d+)\b")
COMMENT_MARKER = re.compile(r"#|//|<!--|<#")

# Where a source comment may name an issue. Directories, so git lists their
# tracked contents and untracked noise such as __pycache__ never appears.
SCAN_PATHS = (
    "flavors/github-copilot/.github/hooks",
    "flavors/github-copilot/.github/scripts",
    ".github/scripts",
)


def git(repo: Path, *args: str) -> str:
    proc = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True)
    if proc.returncode != 0:
        raise SystemExit(f"git {' '.join(args)} failed: {proc.stderr.strip()}")
    return proc.stdout


def resolve_ref(repo: Path, ref: str) -> str:
    for candidate in (ref, ref.split("/")[-1]):
        proc = subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "--verify", "--quiet", f"{candidate}^{{commit}}"],
            capture_output=True,
            text=True,
        )
        if proc.returncode == 0:
            return candidate
    raise SystemExit(f"No such ref: {ref}. Fetch the default branch, or pass --ref.")


def parse_issue_numbers(text: str) -> set[int]:
    numbers: set[int] = set()
    for line in text.splitlines():
        match = re.search(r"\d+", line)
        if match:
            numbers.add(int(match.group()))
    return numbers


def load_open_issues(path: str | None) -> set[int]:
    if path:
        return parse_issue_numbers(Path(path).read_text(encoding="utf-8"))
    try:
        proc = subprocess.run(
            ["gh", "issue", "list", "--state", "open", "--limit", "1000", "--json", "number", "--jq", ".[].number"],
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        raise SystemExit(
            "No open-issue source. The GitHub CLI is not installed, so pass a file:\n"
            "  python .github/scripts/check-issue-drift.py --open-issues open.txt\n"
            "with one issue number per line."
        ) from None
    if proc.returncode != 0:
        raise SystemExit(f"gh issue list failed: {proc.stderr.strip()}")
    return parse_issue_numbers(proc.stdout)


def commit_signals(repo: Path, ref: str, open_issues: set[int]) -> tuple[dict, dict, int]:
    strong: dict[int, list[str]] = {}
    medium: dict[int, list[str]] = {}
    log = git(repo, "log", "--format=%h%x00%s", ref)
    scanned = 0
    for line in log.splitlines():
        if "\x00" not in line:
            continue
        scanned += 1
        short, subject = line.split("\x00", 1)
        claimed = bool(CLAIM_VERB.search(subject))
        for raw in ISSUE_REF.findall(subject):
            number = int(raw)
            if number not in open_issues:
                continue
            bucket = strong if claimed else medium
            bucket.setdefault(number, []).append(f"{short} {subject}")
    return strong, medium, scanned


def comment_signals(repo: Path, open_issues: set[int]) -> tuple[dict, int]:
    mentions: dict[int, list[str]] = {}
    files = [f for f in git(repo, "ls-files", "--", *SCAN_PATHS).splitlines() if f]
    for relative in files:
        path = repo / relative
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for number_line, line in enumerate(text.splitlines(), start=1):
            for match in ISSUE_REF.finditer(line):
                # A comment marker must open before the reference, so "#123"
                # inside a string literal is not mistaken for a mention.
                if not COMMENT_MARKER.search(line[: match.start()]):
                    continue
                number = int(match.group(1))
                if number in open_issues:
                    mentions.setdefault(number, []).append(f"{relative}:{number_line}")
    return mentions, len(files)


def report(title: str, candidates: dict[int, list[str]]) -> None:
    print()
    print(f"--- {title} ({len(candidates)} issues) ---")
    if not candidates:
        print("    none")
        return
    for number in sorted(candidates):
        print(f"  #{number}")
        for evidence in candidates[number]:
            print(f"      {evidence}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Reconcile landed fix claims against open issues.")
    parser.add_argument("--repo", default=str(REPO), help="repository to inspect (default: this one)")
    parser.add_argument("--ref", default="origin/main", help="ref whose history is scanned (default: origin/main)")
    parser.add_argument("--open-issues", metavar="FILE", help="file of open issue numbers, one per line")
    args = parser.parse_args(argv)

    repo = Path(args.repo).resolve()
    ref = resolve_ref(repo, args.ref)
    open_issues = load_open_issues(args.open_issues)
    if not open_issues:
        raise SystemExit("The open-issue set is empty; every signal would be silently dropped.")

    strong, medium, scanned = commit_signals(repo, ref, open_issues)
    weak, file_count = comment_signals(repo, open_issues)

    print("=== Issue drift candidates ===")
    print(f"ref: {ref} ({git(repo, 'rev-parse', '--short', ref).strip()})")
    print(f"open issues supplied: {len(open_issues)}")
    print(f"commits scanned: {scanned}")
    print(f"files scanned for comment mentions: {file_count}")

    report("strong: a commit subject claims a fix, the issue is open", strong)
    report("medium: a commit subject names the issue without claiming a fix", medium)
    report("weak: a source comment names the issue", weak)

    print()
    print("Each entry is a claim to check, not a verdict. Verify the issue's acceptance")
    print("criteria against the current code before closing anything. This script changes")
    print("no issue state.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
