"""No workflow step may read the checkout before the checkout runs.

#327 was not "someone put a step in the wrong place". The two declaration
gates were deliberately placed ahead of `actions/checkout` back when their
matching was inline PowerShell, which needs nothing from the repository. That
placement was load-bearing and nowhere written down, so extracting the matcher
into `.github/scripts/match-local-check.ps1` turned every hook pull request
into a `CommandNotFoundException` naming a file that is tracked and present.

The failure was invisible in the worst way. A pull request touching hooks
reached the matcher and always failed; a pull request touching anything else
exited early and always passed. The gate reported a verdict it had never
computed, and `test-local-check-marker.py` stayed green throughout, because
the matcher was correct -- only unreachable.

Asserting the one step order would fix one instance. This asserts the
property: within a job, any step that depends on repository content must come
after the checkout that provides it.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[2]
WORKFLOWS = REPO / ".github" / "workflows"

# Markers that a step needs the working tree. Substring matches on purpose:
# these appear in shell text, not in a parsable structure.
WORKSPACE_MARKERS = (
    "GITHUB_WORKSPACE",
    ".github/scripts/",
    ".github\\scripts\\",
    "flavors/",
    "mcp-deploy",
    "git ls-files",
    "git log",
    "git diff",
)

failures: list[str] = []
checks = 0


def annotate(body: str) -> None:
    """Raise a failure as a workflow annotation.

    A step that exits non-zero publishes nothing but its exit code to anyone
    who cannot open the run log, so the reason is attached to the run itself.
    """
    if os.environ.get("GITHUB_ACTIONS") != "true":
        return
    escaped = body.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    print(f"::error title=Workflow checkout order::{escaped[:3000]}")


def check(label: str, condition: bool, detail: str = "") -> None:
    global checks
    checks += 1
    if not condition:
        failures.append(f"{label}{': ' + detail if detail else ''}")


def step_label(step: dict, index: int) -> str:
    return str(step.get("name") or step.get("uses") or f"step {index}")


def is_checkout(step: dict) -> bool:
    return str(step.get("uses", "")).startswith("actions/checkout")


def workspace_markers_in(step: dict) -> list[str]:
    """Markers found in a step's own text.

    `uses: ./...` is a local action, which is repository content by
    definition and carries no marker of its own.
    """
    text = str(step.get("run", ""))
    uses = str(step.get("uses", ""))
    found = [m for m in WORKSPACE_MARKERS if m in text]
    if uses.startswith("./"):
        found.append(uses)
    return found


def main() -> int:
    workflows = sorted(WORKFLOWS.glob("*.yml")) + sorted(WORKFLOWS.glob("*.yaml"))

    # An empty list would sail through every loop below and report success, so
    # the glob is asserted rather than assumed.
    check("workflows were found to inspect", bool(workflows), str(WORKFLOWS))
    if not workflows:
        report = "\n".join(f"FAIL {f}" for f in failures)
        print(report)
        annotate(report)
        return 1

    jobs_seen = 0
    for wf in workflows:
        rel = wf.relative_to(REPO).as_posix()
        doc = yaml.safe_load(wf.read_text(encoding="utf-8")) or {}
        for job_name, job in (doc.get("jobs") or {}).items():
            steps = (job or {}).get("steps") or []
            if not steps:
                continue
            jobs_seen += 1

            checkout_at = next((i for i, s in enumerate(steps) if is_checkout(s)), None)
            for index, step in enumerate(steps):
                markers = workspace_markers_in(step)
                if not markers:
                    continue
                label = f"{rel}::{job_name}::{step_label(step, index)}"
                if checkout_at is None:
                    check(
                        f"{label} has a checkout to depend on",
                        False,
                        f"reads {markers[0]} but the job never checks out",
                    )
                else:
                    check(
                        f"{label} runs after the checkout",
                        index > checkout_at,
                        f"reads {markers[0]} at step {index}, checkout is step {checkout_at}",
                    )

    check("jobs with steps were found", jobs_seen > 0, f"{len(workflows)} workflow file(s)")

    if failures:
        report = "\n".join(f"FAIL {f}" for f in failures)
        print(report)
        print(f"\n{len(failures)} of {checks} checks failed")
        annotate(report)
        return 1
    print(f"OK  workflow checkout order: {jobs_seen} job(s) across {len(workflows)} workflow(s) ({checks} checks)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
