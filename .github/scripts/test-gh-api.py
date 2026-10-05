"""Every `gh api` call in this repository's workflows goes through one helper (#323).

A transient API hiccup used to fail a whole regression build with a sentence
two gates shared word for word, indistinguishable from a lost permission. The
helper, `.github/scripts/gh-api.ps1`, asks again on transient answers (5xx, 429,
a secondary rate limit, no HTTP status at all) and fails at once on the ones
that are answers (401, 403, 404, ...). Writes are never retried: the caller
states read or write, the helper does not infer it.

Two halves:

1. Decision table. The helper runs as-is against a stubbed `gh` that replays
   a scripted sequence of responses, inside a PowerShell session whose
   ErrorActionPreference is Stop -- what the Actions `powershell` shell sets.
2. Watchdog. No workflow `run:` block may call `gh api` directly, so a gate
   added later inherits the retry instead of re-introducing the gap.

Usage:
    python .github/scripts/test-gh-api.py
"""

from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[2]
HELPER = REPO / ".github" / "scripts" / "gh-api.ps1"
WORKFLOWS = REPO / ".github" / "workflows"
ENDPOINT = "repos/o/r/pulls/1/files"

DIRECT_CALL = re.compile(r"(?<![\w.\-/\\])gh\s+api\b")

E500 = "err:gh: Server Error (HTTP 500)"
E502 = "err:gh: Bad Gateway (HTTP 502)"
E429 = "err:gh: API rate limit exceeded (HTTP 429)"
E403_SECONDARY = "err:gh: You have exceeded a secondary rate limit (HTTP 403)"
E403 = "err:gh: Resource not accessible by integration (HTTP 403)"
E404 = "err:gh: Not Found (HTTP 404)"
E401 = "err:gh: Bad credentials (HTTP 401)"
ENET = "err:error connecting to api.github.com"

# name, mode, scripted gh responses, expected exit, expected gh calls, expected text in output
CASES: list[tuple[str, str, list[str], int, int, str]] = [
    ("success_returns_every_line", "Read", ["ok:a|b"], 0, 1, "OUT=a|b"),
    ("recovers_after_a_transient_500", "Read", [E500, "ok:a|b"], 0, 2, "OUT=a|b"),
    ("retries_429", "Read", [E429, "ok:x"], 0, 2, "OUT=x"),
    ("retries_a_secondary_rate_limit_403", "Read", [E403_SECONDARY, "ok:x"], 0, 2, "OUT=x"),
    ("retries_a_network_error_without_status", "Read", [ENET, "ok:x"], 0, 2, "OUT=x"),
    ("fails_fast_on_403", "Read", [E403, "ok:x"], 1, 1, "HTTP 403"),
    ("fails_fast_on_404", "Read", [E404, "ok:x"], 1, 1, "HTTP 404"),
    ("fails_fast_on_401", "Read", [E401, "ok:x"], 1, 1, "HTTP 401"),
    ("gives_up_after_the_bound", "Read", [E502], 1, 3, "after 3 attempts"),
    ("never_retries_a_write", "Write", [E500, "ok:x"], 1, 1, "not retried"),
    ("failure_names_step_and_endpoint", "Read", [E404], 1, 1, f"::error::demo gate: list files -- gh api {ENDPOINT}"),
    ("passes_arguments_through_unchanged", "Read", ["ok:x"], 0, 1, f"ARGS=api {ENDPOINT} --paginate --jq .[].filename"),
]


def ps_single(text: str) -> str:
    return "'" + text.replace("'", "''") + "'"


def run_case(work: Path, name: str, mode: str, responses: list[str], call: str | None = None) -> str:
    responses_ps = "@(" + ", ".join(ps_single(r) for r in responses) + ")"
    invocation = call or (
        f"& {ps_single(str(HELPER))} -Step 'demo gate: list files' -Mode {mode} "
        f"-Arguments @('{ENDPOINT}', '--paginate', '--jq', '.[].filename')"
    )
    script = (
        "$ErrorActionPreference = 'Stop'\n"
        "$env:GH_API_BACKOFF_SECONDS = '0'\n"
        f"$global:STUB_RESPONSES = {responses_ps}\n"
        "$global:STUB_CALLS = 0\n"
        "$global:STUB_ARGS = ''\n"
        "function gh {\n"
        "    $global:STUB_CALLS++\n"
        "    $global:STUB_ARGS = $args -join ' '\n"
        "    $i = [Math]::Min($global:STUB_CALLS, $global:STUB_RESPONSES.Count) - 1\n"
        "    $r = $global:STUB_RESPONSES[$i]\n"
        "    if ($r -like 'ok:*') { $global:LASTEXITCODE = 0; return ($r.Substring(3) -split '\\|') }\n"
        "    $global:LASTEXITCODE = 1\n"
        "    Write-Error $r.Substring(4)\n"
        "}\n"
        "try {\n"
        f"    $out = {invocation}\n"
        "    $code = $LASTEXITCODE\n"
        "} catch {\n"
        "    $out = @(); $code = 'THREW'\n"
        '    Write-Output "THREW=$($_.Exception.Message)"\n'
        "}\n"
        'Write-Output "EXIT=$code"\n'
        'Write-Output "CALLS=$global:STUB_CALLS"\n'
        'Write-Output "ARGS=$global:STUB_ARGS"\n'
        "Write-Output \"OUT=$(@($out) -join '|')\"\n"
    )
    case_file = work / f"case_{name}.ps1"
    case_file.write_text(script, encoding="utf-8")
    proc = subprocess.run(
        ["powershell", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(case_file)],
        capture_output=True,
        text=True,
        check=False,
    )
    return proc.stdout + proc.stderr


def field(out: str, key: str) -> str:
    match = re.search(rf"^{key}=(.*)$", out, re.MULTILINE)
    return match.group(1).strip() if match else ""


def report(name: str, ok: bool, detail: str) -> int:
    print(f"[{'PASS' if ok else 'FAIL'}] {name}: {detail}")
    return 0 if ok else 1


def direct_calls() -> list[str]:
    found = []
    for wf in sorted(WORKFLOWS.glob("*.y*ml")):
        data = yaml.safe_load(wf.read_text(encoding="utf-8")) or {}
        for job_name, job in (data.get("jobs") or {}).items():
            for step in job.get("steps") or []:
                for line in str(step.get("run") or "").splitlines():
                    code = line.split("#", 1)[0]
                    if DIRECT_CALL.search(code):
                        found.append(f"{wf.name}:{job_name}:{step.get('name')}: {line.strip()}")
    return found


def main() -> int:
    failures = 0
    total = 0

    total += 1
    failures += report("helper_exists", HELPER.is_file(), str(HELPER.relative_to(REPO)))

    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        if HELPER.is_file():
            for name, mode, responses, want_exit, want_calls, want_text in CASES:
                total += 1
                out = run_case(work, name, mode, responses)
                got_exit, got_calls = field(out, "EXIT"), field(out, "CALLS")
                ok = got_exit == str(want_exit) and got_calls == str(want_calls) and want_text in out
                failures += report(name, ok, f"exit={got_exit} calls={got_calls} want={want_exit}/{want_calls}")
                if not ok:
                    print("      " + out.strip().replace("\n", "\n      "))

            total += 1
            out = run_case(
                work,
                "mode_is_required",
                "",
                ["ok:x"],
                call=f"& {ps_single(str(HELPER))} -Step 'demo' -Arguments @('{ENDPOINT}')",
            )
            ok = field(out, "CALLS") == "0" and field(out, "EXIT") != "0"
            failures += report("mode_is_required", ok, f"exit={field(out, 'EXIT')} calls={field(out, 'CALLS')}")
        else:
            total += len(CASES) + 1
            failures += len(CASES) + 1
            print(f"[FAIL] {len(CASES) + 1} decision-table cases: helper missing")

    total += 1
    hits = direct_calls()
    failures += report("no_workflow_calls_gh_api_directly", not hits, f"{len(hits)} direct call(s)")
    for hit in hits:
        print(f"      {hit}")

    total += 1
    control = [
        DIRECT_CALL.search('$files = gh api "repos/x/pulls/1/files"') is not None,
        DIRECT_CALL.search("gh api -X DELETE repos/x/git/refs/heads/b") is not None,
        DIRECT_CALL.search("& $ghApi -Step 's' -Mode Read") is None,
        DIRECT_CALL.search("$h = '.github/scripts/gh-api.ps1'") is None,
    ]
    failures += report("control_the_watchdog_sees_a_direct_call_and_not_the_helper", all(control), str(control))

    print(f"=== {total - failures}/{total} passed ===")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
