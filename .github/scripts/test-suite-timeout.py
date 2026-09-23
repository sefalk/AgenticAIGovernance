"""The per-suite timeout must have exactly one value.

#333: run-all-tests.ps1 defaulted to 600 seconds and regression.yml invoked it
with 1200. Nothing declared that the two were different, so a suite that takes
691 seconds passed in CI and reported FAILED on a developer's machine -- the
same tree, the same suite, two verdicts. The person reading the local run has
no reason to suspect the budget is the variable.

The fix is not a bigger number, it is a single number: the script's default is
the budget, and the workflow stops passing one. This suite is what keeps it
that way, because the drift is re-introduced by adding one flag.

Three invariants, and they fail for different reasons:

1. The runner declares an integer default. Without it there is nothing to be
   the single source.
2. The workflow does not override it -- or, if some future need forces an
   override, it is the same number. An override that agrees is harmless; an
   override that differs is #333 again.
3. The per-suite cap is strictly below the job's own timeout. A per-suite kill
   that never fires because the job dies first reports nothing about which
   suite hung, which is the only thing the cap exists to tell us.

The parsers are exercised against synthetic text as well as the real files, so
a case cannot pass because the regex matched nothing.

Usage:
    python .github/scripts/test-suite-timeout.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
RUNNER = REPO / "flavors" / "github-copilot" / ".github" / "scripts" / "run-all-tests.ps1"
WORKFLOW = REPO / ".github" / "workflows" / "regression.yml"

# The value CI has actually been running with. The default may rise above it;
# dropping below it would re-introduce #333 from the other direction, by making
# the single source smaller than the budget the suites were measured against.
CI_PROVEN_SECONDS = 1200

_DEFAULT = re.compile(r"\[int\]\s*\$TimeoutSeconds\s*=\s*(\d+)")
_OVERRIDE = re.compile(r"-TimeoutSeconds\s+(\d+)")
_JOB_CAP = re.compile(r"(?m)^\s*timeout-minutes:\s*(\d+)\s*$")


def runner_default(text: str) -> int | None:
    """Return the declared default per-suite timeout, or None if absent."""
    match = _DEFAULT.search(text)
    return int(match.group(1)) if match else None


def workflow_overrides(text: str) -> list[int]:
    """Return every -TimeoutSeconds value the workflow passes to the runner."""
    return [int(m.group(1)) for m in _OVERRIDE.finditer(text)]


def job_cap_seconds(text: str) -> int | None:
    """Return the tightest job timeout in seconds, or None if none is declared."""
    caps = [int(m.group(1)) for m in _JOB_CAP.finditer(text)]
    return min(caps) * 60 if caps else None


def report(name: str, passed: bool, detail: str) -> int:
    print(f"[{'PASS' if passed else 'FAIL'}] {name}: {detail}")
    return 0 if passed else 1


def main() -> int:
    for path in (RUNNER, WORKFLOW):
        if not path.exists():
            print(f"FAIL: {path} does not exist.")
            return 1

    runner_text = RUNNER.read_text(encoding="utf-8")
    workflow_text = WORKFLOW.read_text(encoding="utf-8")

    default = runner_default(runner_text)
    overrides = workflow_overrides(workflow_text)
    cap = job_cap_seconds(workflow_text)

    failures = 0
    total = 0

    total += 1
    failures += report(
        "runner_declares_an_integer_default",
        default is not None,
        f"default={default}",
    )

    total += 1
    disagreeing = [v for v in overrides if v != default]
    failures += report(
        "workflow_does_not_override_the_default",
        not disagreeing,
        f"overrides={overrides} default={default}",
    )

    total += 1
    failures += report(
        "default_is_not_below_the_value_ci_proved",
        default is not None and default >= CI_PROVEN_SECONDS,
        f"default={default} floor={CI_PROVEN_SECONDS}",
    )

    total += 1
    failures += report(
        "per_suite_cap_is_below_the_job_cap",
        default is not None and cap is not None and default < cap,
        f"default={default} job_cap={cap}",
    )

    # Negative controls. Without them every check above passes on a regex that
    # silently matched nothing.
    total += 1
    failures += report(
        "control_a_disagreeing_override_is_seen",
        workflow_overrides("run-all-tests.ps1 -FailOnSkip -TimeoutSeconds 999") == [999],
        "synthetic override parsed",
    )

    total += 1
    failures += report(
        "control_a_missing_default_is_seen",
        runner_default("param(\n    [switch]$FailOnSkip\n)") is None,
        "synthetic runner without a default parsed",
    )

    print(f"=== {total - failures}/{total} passed ===")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
