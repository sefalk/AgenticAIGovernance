"""The CI sweep is scoped on pull requests into dev and full everywhere else (#427).

CI ran every payload suite on every pull request -- about 21 minutes each, with
`run-all-tests.ps1 -Changed` already able to pick the suites a diff needs. The
sweep step now passes `-Changed` on a pull request into `dev` only. The push to
`dev` after the merge and the `dev -> main` promotion keep the full sweep, so a
gap in suite-scope.json is caught after the merge at the latest.

The step's real `run` block is executed against a stub runner that records its
arguments. Asserting on the YAML text would prove only that a string is there.

Usage:
    python .github/scripts/test-ci-scoped-sweep.py
"""

# copilot:generated | coordinator | 2026-10-21

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[2]
WORKFLOW = REPO / ".github/workflows/regression.yml"
STEP = "Run all regression suites"
RUNNER = Path("flavors/github-copilot/.github/scripts/run-all-tests.ps1")

STUB = """param([Parameter(ValueFromRemainingArguments = $true)]$Rest)
(@($args) + @($Rest) | ForEach-Object { $_ }) -join ' ' | Out-File -FilePath $env:STUB_LOG -Append -Encoding utf8
"""


def sweep_step() -> dict:
    jobs = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))["jobs"]
    for job in jobs.values():
        for step in job.get("steps", []):
            if step.get("name") == STEP:
                return step
    raise SystemExit(f"FAIL: no step named {STEP!r} in {WORKFLOW}")


def run(step: dict, event: str, base: str, head: str) -> tuple[int, list[str], str]:
    """Run the step's script as GitHub would, with the expression env resolved by hand."""
    env_decl = step.get("env", {})
    scoped = event == "pull_request" and base == "dev"
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        stub = work / RUNNER
        stub.parent.mkdir(parents=True)
        stub.write_text(STUB, encoding="utf-8")
        log = work / "stub.log"
        summary = work / "summary.md"
        script = work / "step.ps1"
        script.write_text(step["run"], encoding="utf-8")
        env = {**os.environ, "STUB_LOG": str(log), "GITHUB_STEP_SUMMARY": str(summary)}
        for key, value in env_decl.items():
            # Every env value of this step is one of these expressions.
            if "github.event_name == 'pull_request' && github.base_ref == 'dev'" in str(value):
                env[key] = "true" if scoped else "false"
            elif "github.base_ref" in str(value):
                env[key] = base
            else:
                env[key] = str(value)
        proc = subprocess.run(
            ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script)],
            cwd=work,
            env=env,
            capture_output=True,
            text=True,
        )
        calls = log.read_text(encoding="utf-8-sig").splitlines() if log.is_file() else []
        text = summary.read_text(encoding="utf-8-sig") if summary.is_file() else ""
        return proc.returncode, calls, text + proc.stdout + proc.stderr


def main() -> int:
    if shutil.which("powershell") is None:
        print("FAIL: no powershell -- the step cannot be executed, so nothing here is proven.")
        return 2
    step = sweep_step()
    failures = 0

    def check(name: str, ok: bool, detail: str) -> None:
        nonlocal failures
        failures += 0 if ok else 1
        print(f"[{'PASS' if ok else 'FAIL'}] {name}")
        if not ok:
            for line in detail.splitlines():
                print(f"        | {line}")

    code, calls, out = run(step, "pull_request", "dev", "agent/x")
    last = calls[-1] if calls else ""
    check(
        "a_pr_into_dev_runs_the_scoped_sweep",
        code == 0 and "-Changed" in last and "origin/dev" in last,
        "\n".join(calls) + out,
    )
    check(
        "a_pr_into_dev_shows_the_selection_first",
        len(calls) == 2 and "-ListSelection" in calls[0] and "origin/dev" in calls[0],
        "\n".join(calls),
    )
    check(
        "the_scoped_run_keeps_FailOnSkip_and_the_exclusions",
        "-FailOnSkip" in last and "test-deploy-engine.ps1" in last,
        last,
    )

    for name, event, base, head in [
        ("a_push_to_dev_runs_the_full_sweep", "push", "", ""),
        ("the_promotion_runs_the_full_sweep", "pull_request", "main", "dev"),
    ]:
        code, calls, out = run(step, event, base, head)
        ok = code == 0 and len(calls) == 1 and "-Changed" not in calls[0] and "-FailOnSkip" in calls[0]
        check(name, ok, "\n".join(calls) + out)

    checkout = next(
        (
            s
            for job in yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))["jobs"].values()
            for s in job.get("steps", [])
            if str(s.get("uses", "")).startswith("actions/checkout")
        ),
        {},
    )
    check(
        "the_checkout_has_the_history_a_three_dot_diff_needs",
        str(checkout.get("with", {}).get("fetch-depth")) == "0",
        str(checkout),
    )

    print()
    total = 6
    print(f"=== {total - failures}/{total} passed ===")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
