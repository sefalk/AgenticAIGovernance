"""Decision table for the promotion declaration gate in regression.yml.

The gate exempts a dev -> main promotion from the two per-feature declaration
gates and checks the contributing pull requests instead (#234). It is a
PowerShell block inside a workflow step, so no regression suite reaches it --
the defect class of #61, in the machinery that decides whether a release may
merge.

The step's script is extracted from the workflow and executed as-is against a
stubbed `git` and `gh`. Retyping the logic here would prove only that the copy
works.

The suite also asserts that the three gates agree on which paths are gated and
which markers satisfy them. They are three separate steps and cannot share a
variable, so nothing but this check stops one from drifting away from the
others -- and a promotion gate that looks for a marker the feature gate no
longer demands would pass every release while checking nothing.

Usage:
    python .github/scripts/test-promotion-gate.py
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[2]
STEP_NAME = "Verify contributing declarations on a promotion"
ATTESTATION_STEP = "Require local-check attestation for hook changes"
ENV_STEP = "Require declaration for environment changes"

US = "\x1f"
HOOK_FILE = "flavors/github-copilot/.github/hooks/block-dangerous.sh"
MARKER = "local-check: test-hooks-integration.ps1"
GOOD_ENV_BODY = "## Why\n\nenv-change: pins the interpreter for the venv shim\n"


class Case:
    def __init__(
        self,
        name: str,
        log: list[tuple[str, str, str]],
        files: dict[str, list[str]],
        bodies: dict[str, str],
        want_exit: int,
        want_text: str,
        catfile_fails: bool = False,
    ) -> None:
        self.name = name
        self.log = log
        self.files = files
        self.bodies = bodies
        self.want_exit = want_exit
        self.want_text = want_text
        self.catfile_fails = catfile_fails


CASES: list[Case] = [
    Case(
        "empty_range_passes",
        [],
        {},
        {},
        0,
        "Nothing on dev",
    ),
    Case(
        "declared_contributions_pass",
        [
            ("aaa1111", "p1 p2", "Merge pull request #101 from sefalk/agent/1-x"),
            ("bbb2222", "p1 p2", "Merge pull request #102 from sefalk/agent/2-y"),
        ],
        {"aaa1111": [HOOK_FILE], "bbb2222": [".vscode/settings.json"]},
        {"101": f"## Why\n\n{MARKER}\n", "102": GOOD_ENV_BODY},
        0,
        "2 contributing pull request(s) touched a gated path",
    ),
    Case(
        "hook_change_without_marker_names_the_pull_request",
        [("aaa1111", "p1 p2", "Merge pull request #101 from sefalk/agent/1-x")],
        {"aaa1111": [HOOK_FILE]},
        {"101": "## Why\n\nNothing declared.\n"},
        1,
        "#101 changed 1 file(s) under flavors/github-copilot/.github/hooks/",
    ),
    Case(
        "env_change_without_reason_names_the_pull_request",
        [("aaa1111", "p1 p2", "Merge pull request #101 from sefalk/agent/1-x")],
        {"aaa1111": [".githooks/pre-commit"]},
        {"101": "## Why\n\nenv-change: typo\n"},
        1,
        "#101 changed 1 environment file(s)",
    ),
    Case(
        "commented_out_marker_does_not_satisfy_the_gate",
        [("aaa1111", "p1 p2", "Merge pull request #101 from sefalk/agent/1-x")],
        {"aaa1111": [HOOK_FILE]},
        {"101": f"<!-- {MARKER} -->\n\nUntouched template.\n"},
        1,
        "without the line",
    ),
    Case(
        "ungated_contribution_needs_no_declaration",
        [("aaa1111", "p1 p2", "Merge pull request #101 from sefalk/agent/1-x")],
        {"aaa1111": ["README.md", "flavors/github-copilot/.github/agents/planner.agent.md"]},
        {},
        0,
        "0 contributing pull request(s)",
    ),
    Case(
        # The payload hooks live under flavors/ and have their own gate; the
        # env prefixes are matched with StartsWith for exactly this reason.
        "payload_hook_is_not_an_environment_file",
        [("aaa1111", "p1 p2", "Merge pull request #101 from sefalk/agent/1-x")],
        {"aaa1111": [HOOK_FILE]},
        {"101": f"## Why\n\n{MARKER}\n"},
        0,
        "each carried its declaration",
    ),
    Case(
        "direct_push_touching_a_gated_path_fails",
        [("ccc3333", "p1", "hotfix: bump the pinned ruff")],
        {"ccc3333": [".github/workflows/regression.yml"]},
        {},
        1,
        "arrived on dev without a pull request",
    ),
    Case(
        "direct_push_outside_gated_paths_is_reported_but_passes",
        [("ccc3333", "p1", "docs: fix a typo")],
        {"ccc3333": ["README.md"]},
        {},
        0,
        "Changes that reached dev outside a pull request",
    ),
    Case(
        # A merge that is not a pull request merge -- a hand-run `git merge` --
        # is attributable to nobody, so it is treated like a direct push.
        "hand_merge_without_a_pull_request_number_is_reported",
        [("ddd4444", "p1 p2", "Merge branch 'agent/9-z' into dev")],
        {"ddd4444": [HOOK_FILE]},
        {},
        1,
        "arrived on dev without a pull request",
    ),
    Case(
        "one_bad_contribution_among_good_ones_is_named",
        [
            ("aaa1111", "p1 p2", "Merge pull request #101 from sefalk/agent/1-x"),
            ("bbb2222", "p1 p2", "Merge pull request #102 from sefalk/agent/2-y"),
        ],
        {"aaa1111": [HOOK_FILE], "bbb2222": [HOOK_FILE]},
        {"101": f"## Why\n\n{MARKER}\n", "102": "## Why\n\nForgot.\n"},
        1,
        "#102 changed",
    ),
    Case(
        "unreachable_commit_fails_rather_than_passing",
        [],
        {},
        {},
        1,
        "not present in this checkout",
        catfile_fails=True,
    ),
]


def ps_single(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def ps_array(items: list[str]) -> str:
    if not items:
        return "@()"
    return "@(" + ", ".join(ps_single(i) for i in items) + ")"


def ps_hashtable(mapping: dict[str, list[str]]) -> str:
    if not mapping:
        return "@{}"
    body = "; ".join(f"{ps_single(k)} = {ps_array(v)}" for k, v in mapping.items())
    return "@{ " + body + " }"


def ps_body_table(mapping: dict[str, str]) -> str:
    if not mapping:
        return "@{}"
    parts = []
    for key, text in mapping.items():
        parts.append(f"{ps_single(key)} = {ps_single(text)}")
    return "@{ " + "; ".join(parts) + " }"


def build_prelude(case: Case) -> str:
    log_lines = [f"{sha}{US}{parents}{US}{subject}" for sha, parents, subject in case.log]
    # The STUB_ prefix is load-bearing. PowerShell variable names are
    # case-insensitive, so a stub called $FILES is the same variable as the
    # step's own $files -- the first loop iteration overwrites the table with
    # a file list, and the second fails on a String that has no ContainsKey.
    return (
        "$ErrorActionPreference = 'Stop'\n"
        "$env:REPO = 'sefalk/AgenticAIGovernance'\n"
        "$env:BASE_SHA = 'base000'\n"
        "$env:HEAD_SHA = 'head000'\n"
        f"$STUB_LOG = {ps_array(log_lines)}\n"
        f"$STUB_FILES = {ps_hashtable(case.files)}\n"
        f"$STUB_BODIES = {ps_body_table(case.bodies)}\n"
        f"$STUB_CATFILE_FAILS = ${str(case.catfile_fails).lower()}\n"
        # The stubs mirror what the real commands hand back: `gh` returns a
        # multi-line body as an array of lines, which is the shape that broke
        # the env-change gate in #165.
        "function git {\n"
        "    $joined = $args -join ' '\n"
        "    $global:LASTEXITCODE = 0\n"
        "    if ($joined -like 'cat-file*') {\n"
        "        if ($STUB_CATFILE_FAILS) { $global:LASTEXITCODE = 1 }\n"
        "        return\n"
        "    }\n"
        "    if ($joined -like 'log*') { return $STUB_LOG }\n"
        "    if ($joined -like 'diff*') {\n"
        "        $sha = $args[-1]\n"
        "        if ($STUB_FILES.ContainsKey($sha)) { return $STUB_FILES[$sha] }\n"
        "        return @()\n"
        "    }\n"
        "    return\n"
        "}\n"
        "function gh {\n"
        "    $joined = $args -join ' '\n"
        "    $global:LASTEXITCODE = 0\n"
        "    $m = [regex]::Match($joined, 'pulls/(\\d+)')\n"
        "    if ($m.Success -and $STUB_BODIES.ContainsKey($m.Groups[1].Value)) {\n"
        "        return $STUB_BODIES[$m.Groups[1].Value] -split [char]10\n"
        "    }\n"
        "    return @()\n"
        "}\n\n"
    )


def step_run(steps: list[dict], name: str) -> str | None:
    return next((s["run"] for s in steps if s.get("name") == name), None)


def check_gates_agree(steps: list[dict]) -> int:
    """The three gates must agree on gated paths and markers."""
    promotion = step_run(steps, STEP_NAME)
    attestation = step_run(steps, ATTESTATION_STEP)
    env_gate = step_run(steps, ENV_STEP)

    missing = [
        n for n, t in ((STEP_NAME, promotion), (ATTESTATION_STEP, attestation), (ENV_STEP, env_gate)) if t is None
    ]
    if missing:
        print(f"FAIL: no step named {missing} in regression.yml.")
        print("A gate was renamed or removed; this check tests nothing until it is pointed at the new name.")
        return 1

    failures = 0
    checks = [
        ("hook marker", MARKER, [attestation, promotion]),
        ("hook path prefix", "flavors/github-copilot/.github/hooks/", [attestation, promotion]),
        ("env prefix .vscode/", "'.vscode/'", [env_gate, promotion]),
        ("env prefix .githooks/", "'.githooks/'", [env_gate, promotion]),
        ("env prefix .github/", "'.github/'", [env_gate, promotion]),
        ("env marker", "env-change:", [env_gate, promotion]),
    ]
    for label, needle, texts in checks:
        present = all(needle in (t or "") for t in texts)
        failures += 0 if present else 1
        print(f"[{'PASS' if present else 'FAIL'}] gates agree on {label}")

    # A promotion that skipped the per-feature gates but was not itself
    # checked would be the worst of both. The exemption and the replacement
    # have to name the same condition.
    exemption = "!(github.base_ref == 'main' && github.head_ref == 'dev')"
    for name in (ATTESTATION_STEP, ENV_STEP):
        step = next(s for s in steps if s.get("name") == name)
        has = exemption in str(step.get("if", ""))
        failures += 0 if has else 1
        print(f"[{'PASS' if has else 'FAIL'}] '{name}' exempts promotions")

    promo_step = next(s for s in steps if s.get("name") == STEP_NAME)
    guarded = "github.base_ref == 'main' && github.head_ref == 'dev'" in str(promo_step.get("if", ""))
    failures += 0 if guarded else 1
    print(f"[{'PASS' if guarded else 'FAIL'}] '{STEP_NAME}' runs only on promotions")

    return failures


def main() -> int:
    workflow = yaml.safe_load((REPO / ".github/workflows/regression.yml").read_text(encoding="utf-8"))
    steps = workflow["jobs"]["suites"]["steps"]
    run_text = step_run(steps, STEP_NAME)
    if run_text is None:
        print(f"FAIL: no step named '{STEP_NAME}' in regression.yml.")
        print("The gate was renamed or removed; this suite tests nothing until it is pointed at the new name.")
        return 2

    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        for case in CASES:
            case_file = work / f"case_{case.name}.ps1"
            case_file.write_text(build_prelude(case) + run_text, encoding="utf-8")

            proc = subprocess.run(
                ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(case_file)],
                capture_output=True,
                text=True,
            )
            out = proc.stdout + proc.stderr
            passed = proc.returncode == case.want_exit and case.want_text in out
            failures += 0 if passed else 1
            print(f"[{'PASS' if passed else 'FAIL'}] {case.name}: exit={proc.returncode} (want {case.want_exit})")
            if not passed:
                for line in out.splitlines():
                    if line.strip():
                        print(f"        | {line.rstrip()}")

    print()
    consistency_failures = check_gates_agree(steps)

    total = len(CASES) + 10
    failures += consistency_failures
    print()
    print(f"=== {total - failures}/{total} passed ===")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
