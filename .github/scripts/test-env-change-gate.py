"""Decision table for the env-change declaration gate in regression.yml.

The gate is a PowerShell block embedded in a workflow step, so no regression
suite covers it: run-all-tests.ps1 sweeps the payload under flavors/, and this
is CI's own machinery. Without this file the gate would be a shipped script
that nothing ever executed -- the defect class recorded in #61.

The step's script is extracted from the workflow and executed as-is against a
stubbed `gh`. Retyping the logic here would prove only that the copy works.

Usage:
    python .github/scripts/test-env-change-gate.py
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[2]
STEP_NAME = "Require declaration for environment changes"
PAYLOAD_HOOK = "flavors/github-copilot/.github/hooks/pre-commit.ps1"

# name, changed files, pull request body, expected exit, expected text
CASES: list[tuple[str, list[str], str, int, str]] = [
    (
        "no_env_files_passes",
        ["flavors/github-copilot/.github/scripts/run-lint.ps1", "README.md"],
        "## What changed\n\nSomething unrelated.\n",
        0,
        "declaration not required",
    ),
    (
        "payload_hook_is_not_an_env_file",
        [PAYLOAD_HOOK],
        "## What changed\n\nA payload hook.\n",
        0,
        "declaration not required",
    ),
    (
        "env_file_without_marker_fails",
        [".vscode/settings.json"],
        "## What changed\n\nSomething unrelated.\n",
        1,
        "Add a line to the pull request body",
    ),
    (
        "marker_with_empty_reason_fails",
        [".githooks/pre-commit"],
        "## What changed\n\nenv-change:\n",
        1,
        "states no reason",
    ),
    (
        "marker_with_short_reason_fails",
        [".github/workflows/regression.yml"],
        "## What changed\n\nenv-change: typo\n",
        1,
        "states no reason",
    ),
    (
        "marker_with_reason_passes",
        [".github/workflows/regression.yml"],
        "## What changed\n\nenv-change: adds the declaration gate itself\n",
        0,
        "Environment change declared",
    ),
    (
        "commented_out_template_marker_fails",
        [".vscode/settings.json"],
        "## What changed\n\n<!-- env-change: -->\n\nUntouched template.\n",
        1,
        "Add a line to the pull request body",
    ),
    (
        "marker_anywhere_in_body_counts",
        [".vscode/settings.json", "README.md"],
        "## Why\n\nblah\n\nenv-change: pins the interpreter for the venv shim\n\n## Closes\n",
        0,
        "Environment change declared",
    ),
    (
        "empty_marker_does_not_mask_a_filled_one",
        [".vscode/settings.json"],
        "env-change:\n\nenv-change: pins the interpreter for the venv shim\n",
        0,
        "Environment change declared",
    ),
]


def ps_array(items: list[str]) -> str:
    return "@(" + ", ".join("'" + i.replace("'", "''") + "'" for i in items) + ")"


def main() -> int:
    workflow = yaml.safe_load(
        (REPO / ".github/workflows/regression.yml").read_text(encoding="utf-8")
    )
    steps = workflow["jobs"]["suites"]["steps"]
    run_text = next((s["run"] for s in steps if s.get("name") == STEP_NAME), None)
    if run_text is None:
        print(f"FAIL: no step named '{STEP_NAME}' in regression.yml.")
        print(
            "The gate was renamed or removed; this suite tests nothing until it is pointed at the new name."
        )
        return 2

    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        for name, files, body, want_exit, want_text in CASES:
            prelude = (
                "$ErrorActionPreference = 'Stop'\n"
                "$env:REPO = 'sefalk/AgenticAIGovernance'\n"
                "$env:PR_NUMBER = '999'\n"
                f"$FILES = {ps_array(files)}\n"
                "$BODY = @'\n"
                f"{body}\n"
                "'@\n"
                "function gh {\n"
                "    $joined = $args -join ' '\n"
                "    $global:LASTEXITCODE = 0\n"
                "    if ($joined -like '*/files*') { return $FILES }\n"
                "    return $BODY\n"
                "}\n\n"
            )
            case_file = work / f"case_{name}.ps1"
            case_file.write_text(prelude + run_text, encoding="utf-8")

            proc = subprocess.run(
                [
                    "powershell",
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(case_file),
                ],
                capture_output=True,
                text=True,
            )
            out = proc.stdout + proc.stderr
            passed = proc.returncode == want_exit and want_text in out
            failures += 0 if passed else 1
            print(
                f"[{'PASS' if passed else 'FAIL'}] {name}: exit={proc.returncode} (want {want_exit})"
            )
            if not passed:
                for line in out.splitlines():
                    if line.strip():
                        print(f"        | {line.rstrip()}")

    print()
    print(f"=== {len(CASES) - failures}/{len(CASES)} passed ===")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
