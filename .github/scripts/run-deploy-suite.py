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

Failures are also emitted as a workflow annotation. A step that exits non-zero
publishes nothing but "Process completed with exit code 1" to anyone who cannot
open the run log, which is what made the first two failures of this gate
undiagnosable from outside the repository. An annotation is rendered on the run
page itself, so the reason travels with the failure.
"""

from __future__ import annotations

import os
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


def fail(summary: str, detail: str = "") -> int:
    """Print a failure and, under Actions, raise it as an annotation."""
    print(f"FAIL {summary}")
    if detail:
        print(detail)
    if os.environ.get("GITHUB_ACTIONS") == "true":
        body = summary if not detail else f"{summary}\n{detail}"
        escaped = body.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        print(f"::error title=deploy engine suite::{escaped[:3000]}")
    return 1


def salient(output: str) -> str:
    """The lines of a pytest run that say why it failed, without the noise."""
    lines = [line.rstrip() for line in output.splitlines() if line.strip()]
    marked = [
        line for line in lines if line.startswith("E ") or any(m in line for m in ("FAILED", "ERROR", "Interrupted"))
    ]
    picked = list(dict.fromkeys(marked[-15:] + lines[-10:]))
    return "\n".join(picked)


def main() -> int:
    if not SUITE.is_dir():
        return fail(f"suite directory missing: {SUITE}")

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
        return fail(f"the suite did not finish within {TIMEOUT}s")
    elapsed = time.monotonic() - started
    output = proc.stdout + proc.stderr
    print(output)
    print(f"[deploy-suite] runtime {elapsed:.1f}s")

    if proc.returncode != 0:
        if proc.returncode == 2:
            reason = "pytest exited 2 -- collection error, so no test ran at all"
        else:
            reason = f"pytest exited {proc.returncode}"
        return fail(reason, salient(output))

    unexpected = [r.strip() for r in SKIP_LINE.findall(output) if not any(a in r for a in ALLOWED_SKIPS)]
    if unexpected:
        return fail(
            f"{len(unexpected)} unexpected skip(s) -- a skipped test asserts nothing",
            "\n".join(unexpected)
            + "\nInstall the missing prerequisite, or add the reason to ALLOWED_SKIPS with a justification.",
        )

    passed = PASS_COUNT.search(output)
    if not passed:
        return fail("no pass count in the summary -- cannot tell whether anything ran", salient(output))
    if int(passed.group(1)) < MIN_PASSED:
        return fail(
            f"only {passed.group(1)} tests passed, expected at least {MIN_PASSED}",
            "The suite shrank. Restore the tests, or lower MIN_PASSED deliberately.",
        )

    print(f"OK  deploy engine suite: {passed.group(1)} passed in {elapsed:.1f}s, no unexpected skips")
    return 0


if __name__ == "__main__":
    sys.exit(main())
