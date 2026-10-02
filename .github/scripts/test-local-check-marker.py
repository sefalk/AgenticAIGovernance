"""Decision table for the local-check attestation marker.

#313: a body that attested correctly was rejected because it formatted the
filename in backticks, and the error message told the author to add a line that
was already there. The matcher that replaced the two literals is the fix; this
is what keeps it honest.

Two layers, because they fail for different reasons:

1. The matcher is exercised directly. Fast, and it is where the shape of an
   accepted marker is pinned down.
2. The attestation gate is extracted from regression.yml and executed against a
   stubbed `gh`, as the sibling gate suites do. This is the layer that would
   catch the matcher being correct and the step not calling it.

The #234 property -- a template nobody edited must not satisfy a check about
work somebody did -- is asserted against the real pull request template rather
than a copy of it, so that editing the template cannot quietly pass.

Usage:
    python .github/scripts/test-local-check-marker.py
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[2]
MATCHER = REPO / ".github/scripts/match-local-check.ps1"
TEMPLATE = REPO / ".github/pull_request_template.md"
STEP_NAME = "Require local-check attestation for hook changes"
HOOK_FILE = "flavors/github-copilot/.github/hooks/scripts/documenter-stop.ps1"

MATCH, ABSENT, MALFORMED = 0, 1, 2

# name, body, expected exit
MATCHER_CASES: list[tuple[str, str, int]] = [
    (
        "plain_marker_matches",
        "## What changed\n\nlocal-check: test-hooks-integration.ps1\n",
        MATCH,
    ),
    (
        # The body of PR #312, verbatim. This is the case that started #313.
        "backticked_filename_matches",
        "local-check: `test-hooks-integration.ps1` PASS (1.6s), run locally as part of the full sweep below.\n",
        MATCH,
    ),
    (
        "whole_marker_backticked_matches",
        "I ran `local-check: test-hooks-integration.ps1` before pushing.\n",
        MATCH,
    ),
    (
        "marker_with_trailing_prose_matches",
        "local-check: test-hooks-integration.ps1 -- 42 assertions, 0 failed.\n",
        MATCH,
    ),
    (
        "extra_spaces_after_the_colon_match",
        "local-check:   test-hooks-integration.ps1\n",
        MATCH,
    ),
    (
        # #234. The template ships the marker commented out.
        "commented_out_marker_is_absent",
        "## Summary\n\n<!-- local-check: test-hooks-integration.ps1 -->\n\nUntouched template.\n",
        ABSENT,
    ),
    (
        # A commented-out marker must not mask a real one, and a real one must
        # not be reachable by commenting out the text around it.
        "comment_does_not_mask_a_real_marker",
        "<!-- local-check: test-hooks-integration.ps1 -->\n\nlocal-check: test-hooks-integration.ps1\n",
        MATCH,
    ),
    (
        "multiline_comment_containing_the_marker_is_absent",
        "<!--\nlocal-check: test-hooks-integration.ps1\n-->\n",
        ABSENT,
    ),
    (
        # Rejecting this is defensible; rejecting it without saying why is not.
        "bold_marker_is_reported_as_malformed",
        "**local-check:** test-hooks-integration.ps1\n",
        MALFORMED,
    ),
    (
        "marker_naming_the_wrong_suite_is_malformed",
        "local-check: test-hooks.ps1\n",
        MALFORMED,
    ),
    (
        "no_mention_at_all_is_absent",
        "## What changed\n\nSomething unrelated.\n",
        ABSENT,
    ),
    (
        "empty_body_is_absent",
        "",
        ABSENT,
    ),
]


def ps_single(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def run_matcher(body: str, work: Path, name: str) -> tuple[int, str]:
    """Invoke the matcher the way the workflow does, through a file.

    Passing the body as a here-string rather than on the command line keeps
    newlines and backticks out of PowerShell's argument parsing, which is what
    the gate does too -- it holds the body in a variable.
    """
    script = (
        "$ErrorActionPreference = 'Stop'\n"
        "$body = @'\n"
        f"{body}\n"
        "'@\n"
        f"& {ps_single(str(MATCHER))} -Body $body\n"
        "exit $LASTEXITCODE\n"
    )
    case_file = work / f"matcher_{name}.ps1"
    case_file.write_text(script, encoding="utf-8")
    proc = subprocess.run(
        ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(case_file)],
        capture_output=True,
        text=True,
        cwd=str(REPO),
    )
    return proc.returncode, proc.stdout + proc.stderr


def check_matcher(work: Path) -> int:
    failures = 0
    for name, body, want in MATCHER_CASES:
        code, out = run_matcher(body, work, name)
        passed = code == want
        failures += 0 if passed else 1
        print(f"[{'PASS' if passed else 'FAIL'}] {name}: exit={code} (want {want})")
        if not passed:
            for line in out.splitlines():
                if line.strip():
                    print(f"        | {line.rstrip()}")
    return failures


def check_real_template(work: Path) -> int:
    """The shipped template must not attest on an author's behalf.

    Bound to the file rather than to a copy of its text: a template edited to
    uncomment the marker would pass a copy-based test forever.
    """
    if not TEMPLATE.is_file():
        print(f"[FAIL] real template: {TEMPLATE} does not exist, so nothing was checked")
        return 1

    text = TEMPLATE.read_text(encoding="utf-8")
    failures = 0

    mentions = "local-check: test-hooks-integration.ps1" in text
    failures += 0 if mentions else 1
    print(f"[{'PASS' if mentions else 'FAIL'}] real template still carries the marker line to be uncommented")

    code, _ = run_matcher(text, work, "real_template")
    passed = code == ABSENT
    failures += 0 if passed else 1
    print(f"[{'PASS' if passed else 'FAIL'}] real template does not satisfy the gate: exit={code} (want {ABSENT})")
    return failures


def check_gate(work: Path) -> int:
    """The gate itself: does the step reach the matcher, and act on its verdict?"""
    workflow = yaml.safe_load((REPO / ".github/workflows/regression.yml").read_text(encoding="utf-8"))
    steps = workflow["jobs"]["suites"]["steps"]
    run_text = next((s["run"] for s in steps if s.get("name") == STEP_NAME), None)
    if run_text is None:
        print(f"FAIL: no step named '{STEP_NAME}' in regression.yml.")
        print("The gate was renamed or removed; this suite tests nothing until it is pointed at the new name.")
        return 1

    # name, changed files, body, expected exit, expected text
    cases: list[tuple[str, list[str], str, int, str]] = [
        (
            "no_hook_files_needs_no_attestation",
            ["README.md"],
            "Nothing to declare.\n",
            0,
            "attestation not required",
        ),
        (
            "plain_marker_clears_the_gate",
            [HOOK_FILE],
            "local-check: test-hooks-integration.ps1\n",
            0,
            "Attestation present",
        ),
        (
            "backticked_marker_clears_the_gate",
            [HOOK_FILE],
            "local-check: `test-hooks-integration.ps1` PASS (1.6s).\n",
            0,
            "Attestation present",
        ),
        (
            "commented_out_marker_still_fails",
            [HOOK_FILE],
            "<!-- local-check: test-hooks-integration.ps1 -->\n",
            1,
            "Run it locally",
        ),
        (
            "unreadable_marker_says_so",
            [HOOK_FILE],
            "**local-check:** test-hooks-integration.ps1\n",
            1,
            "not one this gate can read",
        ),
        (
            "missing_marker_keeps_the_original_message",
            [HOOK_FILE],
            "Nothing to declare.\n",
            1,
            "Run it locally",
        ),
    ]

    failures = 0
    for name, files, body, want_exit, want_text in cases:
        # The stub returns the body as an array of lines because that is what
        # PowerShell does with a native command's multi-line output; a stub
        # returning one string made a sibling suite pass while CI failed.
        prelude = (
            "$ErrorActionPreference = 'Stop'\n"
            "$env:REPO = 'sefalk/AgenticAIGovernance'\n"
            "$env:PR_NUMBER = '999'\n"
            f"$env:GITHUB_WORKSPACE = {ps_single(str(REPO))}\n"
            "$STUB_FILES = @(" + ", ".join(ps_single(f) for f in files) + ")\n"
            "$STUB_BODY = @'\n"
            f"{body}\n"
            "'@\n"
            "function gh {\n"
            "    $joined = $args -join ' '\n"
            "    $global:LASTEXITCODE = 0\n"
            "    if ($joined -like '*/files*') { return $STUB_FILES }\n"
            "    return $STUB_BODY -split [char]10\n"
            "}\n\n"
        )
        case_file = work / f"gate_{name}.ps1"
        case_file.write_text(prelude + run_text, encoding="utf-8")

        proc = subprocess.run(
            ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(case_file)],
            capture_output=True,
            text=True,
            cwd=str(REPO),
        )
        out = proc.stdout + proc.stderr
        passed = proc.returncode == want_exit and want_text in out
        failures += 0 if passed else 1
        print(f"[{'PASS' if passed else 'FAIL'}] {name}: exit={proc.returncode} (want {want_exit})")
        if not passed:
            for line in out.splitlines():
                if line.strip():
                    print(f"        | {line.rstrip()}")
    return failures


def main() -> int:
    if not MATCHER.is_file():
        print(f"FAIL: {MATCHER} does not exist. Both gates in regression.yml depend on it.")
        return 2

    total = len(MATCHER_CASES) + 2 + 6
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        failures = check_matcher(work)
        print()
        failures += check_real_template(work)
        print()
        failures += check_gate(work)

    print()
    print(f"=== {total - failures}/{total} passed ===")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
