"""Decision table for close-delivered-issues.ps1 (#160).

`Closes #N` fires only on the default branch, so issues delivered to `dev`
stayed open until somebody remembered them. The script closes them instead,
and a wrong close is costly: it hides work that was deliberately left open.
So every case below is about what must NOT be closed as much as what must.

The script runs as-is against a stubbed `gh` that records every call; the
assertions read the recorded writes, not the script's own report.

Usage:
    python .github/scripts/test-close-delivered-issues.py
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / ".github" / "scripts" / "close-delivered-issues.ps1"
SINCE = "2026-10-07T00:00:00Z"
AFTER = "2026-10-07T09:00:00Z"
BEFORE = "2026-10-06T09:00:00Z"


def pr(number: int, body: str, merged_at: str | None = AFTER) -> dict:
    return {"number": number, "merged_at": merged_at, "merge_commit_sha": f"{number:040x}", "body": body}


OPEN = {"state": "open", "is_pr": False}
CLOSED = {"state": "closed", "is_pr": False}
A_PR = {"state": "open", "is_pr": True}

# name, merged pulls, issue states, extra args, fail writes, want exit, want closed, want text
CASES: list[tuple[str, list[dict], dict[int, dict], list[str], bool, int, list[int], str]] = [
    ("plain_closes_line_closes_the_issue", [pr(500, "Closes #10.\n\n## What\n")], {10: OPEN}, [], False, 0, [10], ""),
    (
        "fixes_and_resolves_count_too",
        [pr(501, "fixes #11\nResolves #12")],
        {11: OPEN, 12: OPEN},
        [],
        False,
        0,
        [11, 12],
        "",
    ),
    ("an_already_closed_issue_is_left_alone", [pr(502, "Closes #13")], {13: CLOSED}, [], False, 0, [], ""),
    ("a_pr_merged_before_the_cutoff_is_ignored", [pr(503, "Closes #14", BEFORE)], {14: OPEN}, [], False, 0, [], ""),
    ("an_unmerged_pr_is_ignored", [pr(504, "Closes #15", None)], {15: OPEN}, [], False, 0, [], ""),
    (
        "a_keyword_in_an_html_comment_is_ignored",
        [pr(505, "<!-- Closes #16 -->\nbody")],
        {16: OPEN},
        [],
        False,
        0,
        [],
        "",
    ),
    ("a_keyword_in_a_code_fence_is_ignored", [pr(506, "```\nCloses #17\n```")], {17: OPEN}, [], False, 0, [], ""),
    (
        "a_keyword_in_a_multiline_template_comment_is_ignored",
        [pr(513, "## Closes\n\n<!--\nCloses #25\n-->\n")],
        {25: OPEN},
        [],
        False,
        0,
        [],
        "",
    ),
    ("a_failed_close_fails_the_run", [pr(514, "Closes #26")], {26: OPEN}, [], True, 1, [26], "::error::"),
    (
        "a_keyword_mid_sentence_is_ignored",
        [pr(507, "This PR never closes #18 by design.")],
        {18: OPEN},
        [],
        False,
        0,
        [],
        "",
    ),
    (
        "only_the_named_issue_not_a_related_one",
        [pr(508, "Closes #19. Related: #20")],
        {19: OPEN, 20: OPEN},
        [],
        False,
        0,
        [19],
        "",
    ),
    ("part_of_does_not_close", [pr(509, "Part of #21")], {21: OPEN}, [], False, 0, [], ""),
    ("a_pull_request_target_is_not_closed", [pr(510, "Closes #22")], {22: A_PR}, [], False, 0, [], ""),
    ("dry_run_writes_nothing", [pr(511, "Closes #23")], {23: OPEN}, ["-DryRun"], False, 0, [], "would close #23"),
    ("a_failed_write_fails_the_run", [pr(512, "Closes #24")], {24: OPEN}, [], True, 1, [], "::error::"),
]


# Cases whose stub fails only the close, so a note-then-failed-close is caught too.
FAIL_CLOSE_ONLY = {"a_failed_close_fails_the_run"}


def stub(pulls: list[dict], issues: dict[int, dict], log: Path, fail_writes: bool, close_only: bool = False) -> str:
    """A `gh` function answering the three reads and recording every call."""
    pull_lines = "\n".join(json.dumps(p) for p in pulls)
    issue_map = "; ".join(f"'{n}' = \"{s['state']}`t{str(s['is_pr']).lower()}\"" for n, s in issues.items())
    return (
        "$ErrorActionPreference = 'Stop'\n"
        f"$STUB_LOG = '{log}'\n"
        "$STUB_PULLS = @'\n" + pull_lines + "\n'@\n"
        f"$STUB_ISSUES = @{{ {issue_map} }}\n"
        f"$STUB_FAIL = ${str(fail_writes).lower()}\n"
        f"$STUB_CLOSE_ONLY = ${str(close_only).lower()}\n"
        "function gh {\n"
        "    $joined = $args -join ' '\n"
        "    Add-Content -Path $STUB_LOG -Value $joined -Encoding UTF8\n"
        "    $global:LASTEXITCODE = 0\n"
        "    if ($joined -match '-X (POST|PATCH)') {\n"
        "        if ($STUB_FAIL -and -not ($STUB_CLOSE_ONLY -and $joined -match '-X POST')) {\n"
        "            Write-Error 'HTTP 403: Resource not accessible by integration'\n"
        "            $global:LASTEXITCODE = 1; return\n"
        "        }\n"
        "        return '{}'\n"
        "    }\n"
        "    if ($joined -match '/pulls\\?') { return $STUB_PULLS -split \"`n\" | Where-Object { $_ } }\n"
        "    if ($joined -match '/issues/(\\d+)( |$)') { return $STUB_ISSUES[$Matches[1]] }\n"
        '    Write-Error "HTTP 404: unexpected call $joined"; $global:LASTEXITCODE = 1\n'
        "}\n\n"
    )


def main() -> int:
    if not SCRIPT.is_file():
        print(f"FAIL: {SCRIPT.relative_to(REPO)} does not exist.")
        return 1

    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        for name, pulls, issues, extra, fail_writes, want_exit, want_closed, want_text in CASES:
            log = work / f"{name}.log"
            log.write_text("", encoding="utf-8")
            args = f"-Repo 'sefalk/AgenticAIGovernance' -Since '{SINCE}' {' '.join(extra)}"
            call = f"& '{SCRIPT}' {args}\nexit $LASTEXITCODE\n"
            case = work / f"case_{name}.ps1"
            case.write_text(stub(pulls, issues, log, fail_writes, name in FAIL_CLOSE_ONLY) + call, encoding="utf-8")
            proc = subprocess.run(
                ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(case)],
                capture_output=True,
                text=True,
                env={**os.environ, "GH_API_BACKOFF_SECONDS": "0"},
            )
            out = proc.stdout + proc.stderr
            calls = [c for c in log.read_text(encoding="utf-8-sig").splitlines() if c.strip()]
            closed = sorted(
                int(c.split("/issues/")[1].split()[0]) for c in calls if "-X PATCH" in c and "state=closed" in c
            )
            commented = sorted(int(c.split("/issues/")[1].split("/")[0]) for c in calls if "-X POST" in c)
            # The delivery note must land before the close, so a failed close never leaves a silent one.
            ordered = all(
                next(i for i, c in enumerate(calls) if "-X POST" in c and f"/issues/{n}/" in c)
                < next(i for i, c in enumerate(calls) if "-X PATCH" in c and f"/issues/{n} " in c)
                for n in closed
            )
            ok = (
                proc.returncode == want_exit
                and closed == sorted(want_closed)
                and (fail_writes or commented == sorted(want_closed))
                and ordered
                and (want_text in out)
            )
            failures += 0 if ok else 1
            print(f"[{'PASS' if ok else 'FAIL'}] {name}: exit={proc.returncode} closed={closed} commented={commented}")
            if not ok:
                print(f"        want exit={want_exit} closed={sorted(want_closed)} text={want_text!r}")
                for line in out.splitlines():
                    if line.strip():
                        print(f"        | {line.rstrip()}")

    print()
    print(f"=== {len(CASES) - failures}/{len(CASES)} passed ===")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
