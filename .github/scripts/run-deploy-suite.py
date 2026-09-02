"""Run the deploy engine's pytest suite as a CI gate.

The suite existed and was never executed (#270), so a regression in the code
that decides what overwrites a consumer project would have reached a project
before it reached a build. The first run found a test that had been failing
unnoticed. Three things make this more than a `pytest` line in the workflow,
and all three belong here rather than in YAML where they cannot be tested:

* A skip is a pass that proves nothing. Eleven of the thirteen skips are
  environmental, so a runner that loses an interpreter would report success
  while asserting nothing about `deploy.sh`. Every tolerated reason is listed
  in ALLOWED_SKIPS with why it is tolerated; an unlisted one fails the gate.
* Reason-matching alone still passes if the suite quietly shrinks to a handful
  of tests, so MIN_PASSED puts a floor under what actually ran.
* The runtime is reported, because whether this suite stays in the Regression
  job is a decision that should be made against a number.

The environment is deliberately left alone. Git for Windows ships `bash` and
`awk` on every Windows runner but keeps them off PATH, which is why the parity
tests skip there. Putting them on PATH was tried and measured on 2026-09-02:
`bash deploy.sh --force` needs longer than the 300s the test itself allows, so
all eleven turn from skips into five-minute failures. On Windows the skip is
the correct outcome, not a gap to close by installing something.
"""

from __future__ import annotations

import re
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SUITE = REPO / "flavors" / "github-copilot" / "mcp-deploy"

# Tolerated skip reasons, each with the reason it is not a defect.
ALLOWED_SKIPS: dict[str, str] = {
    "no curated-skills region": (
        "coordinator and compliance-checker carry no '## Skills' section by design; "
        "test_agent_curated_regions asserts that set separately"
    ),
    "bash or deploy.sh not available": (
        "deploy.sh under Git-Bash on Windows exceeds the test's own 300s subprocess limit "
        "(measured 2026-09-02), so this must skip rather than run on a Windows runner"
    ),
    "awk or deploy.sh not available": (
        "same measurement: the sh parity tests drive deploy.sh, which is not viable there"
    ),
    "bash/git or deploy.sh not available": (
        "same measurement, plus a git repository the bash path builds through MSYS"
    ),
}

# A floor under tests actually executed. Raise it when the suite grows.
MIN_PASSED = 108

SKIP_LINE = re.compile(r"^SKIPPED \[\d+\] (.+)$", re.MULTILINE)
PASS_COUNT = re.compile(r"(\d+) passed")
TIMEOUT = 900


def main() -> int:
    if not SUITE.is_dir():
        print(f"FAIL suite directory missing: {SUITE}")
        return 1

    started = time.monotonic()
    try:
        proc = subprocess.run(
            [sys.executable, "-m", "pytest", "-q", "-rs", "--no-header"],
            cwd=SUITE,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=TIMEOUT,
            stdin=subprocess.DEVNULL,
        )
    except subprocess.TimeoutExpired:
        print(f"FAIL the suite did not finish within {TIMEOUT}s")
        return 1
    elapsed = time.monotonic() - started
    output = proc.stdout + proc.stderr
    print(output)
    print(f"[deploy-suite] runtime {elapsed:.1f}s")

    if proc.returncode != 0:
        if proc.returncode == 2:
            print("FAIL pytest exited 2 -- collection error, so no test ran at all")
        else:
            print(f"FAIL pytest exited {proc.returncode}")
        return 1

    unexpected = [r.strip() for r in SKIP_LINE.findall(output) if not any(a in r for a in ALLOWED_SKIPS)]
    if unexpected:
        print(f"FAIL {len(unexpected)} unexpected skip(s) -- a skipped test asserts nothing:")
        for reason in unexpected:
            print(f"  {reason}")
        print("Install the missing prerequisite, or add the reason to ALLOWED_SKIPS with a justification.")
        return 1

    passed = PASS_COUNT.search(output)
    if not passed:
        print("FAIL no pass count in the summary -- cannot tell whether anything ran")
        return 1
    if int(passed.group(1)) < MIN_PASSED:
        print(f"FAIL only {passed.group(1)} tests passed, expected at least {MIN_PASSED}")
        print("The suite shrank. Restore the tests, or lower MIN_PASSED deliberately.")
        return 1

    print(f"OK  deploy engine suite: {passed.group(1)} passed in {elapsed:.1f}s, no unexpected skips")
    return 0


if __name__ == "__main__":
    sys.exit(main())
