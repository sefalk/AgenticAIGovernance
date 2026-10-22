"""Tests for the command server's core runner (#60, slice 1).

Real subprocesses on tiny Python fixtures, so the walltime and tree-kill
contract is proven against the operating system rather than a mock.
"""

# copilot:generated | coordinator | 2026-10-19

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

import pytest

from af_deploy_mcp import command_core as cc

AGENT_DIR = ".github/scripts/agent"


def _workspace(tmp_path: Path, conf: str | None = None) -> Path:
    root = tmp_path / "ws"
    (root / AGENT_DIR).mkdir(parents=True)
    if conf is not None:
        (root / ".github" / "af-env.conf").write_text(conf, encoding="utf-8")
    return root


def _script(root: Path, rel: str, body: str) -> Path:
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(body, encoding="utf-8")
    return p


def _alive(pid: int) -> bool:
    if sys.platform == "win32":
        import ctypes

        handle = ctypes.windll.kernel32.OpenProcess(0x1000, False, pid)
        if not handle:
            return False
        code = ctypes.c_ulong()
        ctypes.windll.kernel32.GetExitCodeProcess(handle, ctypes.byref(code))
        ctypes.windll.kernel32.CloseHandle(handle)
        return code.value == 259  # STILL_ACTIVE
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


# ── configuration ──────────────────────────────────────────────────────────


def test_script_dirs_parse_with_an_optional_mode() -> None:
    dirs = cc.parse_script_dirs(" .github/scripts/agent , scripts/ops:ask-always ")
    assert dirs == [cc.ScriptDir(".github/scripts/agent", None), cc.ScriptDir("scripts/ops", "ask-always")]


def test_an_unknown_mode_is_rejected() -> None:
    with pytest.raises(ValueError, match="sometimes"):
        cc.parse_script_dirs("scripts/x:sometimes")


def test_defaults_apply_without_af_env(tmp_path: Path) -> None:
    cfg = cc.load_config(_workspace(tmp_path))
    assert cfg.dirs == [cc.ScriptDir(AGENT_DIR, None)]
    assert cfg.approval == "ask"
    assert (cfg.walltime_default, cfg.walltime_max) == (600, 3600)
    assert cfg.task_dirs == [".github/scripts"]


def test_af_env_overrides_the_defaults(tmp_path: Path) -> None:
    conf = (
        "AF_SCRIPT_DIRS=tools,tools/fast:autonomous\nAF_SCRIPT_APPROVAL=ask-always\n"
        "AF_SCRIPT_WALLTIME_DEFAULT=60\nAF_SCRIPT_WALLTIME_MAX=120\nAF_TASK_SCRIPT_DIRS=ci\n"
    )
    cfg = cc.load_config(_workspace(tmp_path, conf))
    assert cfg.dirs == [cc.ScriptDir("tools", None), cc.ScriptDir("tools/fast", "autonomous")]
    assert cfg.approval == "ask-always"
    assert (cfg.walltime_default, cfg.walltime_max, cfg.task_dirs) == (60, 120, ["ci"])


# ── path resolution ────────────────────────────────────────────────────────


def test_the_deepest_configured_folder_wins(tmp_path: Path) -> None:
    root = _workspace(tmp_path)
    _script(root, f"{AGENT_DIR}/a.py", "")
    _script(root, ".github/scripts/b.py", "")
    cfg = cc.load_config(root)
    agent = cc.resolve_script(root, cfg, f"{AGENT_DIR}/a.py")
    reviewed = cc.resolve_script(root, cfg, ".github/scripts/b.py")
    assert (agent.folder, agent.folder_mode) == (AGENT_DIR, None)
    assert (reviewed.folder, reviewed.folder_mode) == (".github/scripts", "reviewed")


@pytest.mark.parametrize(
    ("rel", "reason"),
    [
        (f"{AGENT_DIR}/../../../evil.py", "outside"),
        ("elsewhere/x.py", "outside"),
        (f"{AGENT_DIR}/run.bat", "extension"),
        (f"{AGENT_DIR}/missing.py", "not found"),
    ],
    ids=["dotdot-escape", "unconfigured-folder", "unknown-extension", "missing-file"],
)
def test_unsafe_or_unknown_paths_are_refused(tmp_path: Path, rel: str, reason: str) -> None:
    root = _workspace(tmp_path)
    _script(root, "evil.py", "")
    _script(root, "elsewhere/x.py", "")
    _script(root, f"{AGENT_DIR}/run.bat", "")
    with pytest.raises(cc.Refused, match=reason):
        cc.resolve_script(root, cc.load_config(root), rel)


def test_a_symlink_out_of_the_folder_is_refused(tmp_path: Path) -> None:
    root = _workspace(tmp_path)
    outside = _script(tmp_path, "outside.py", "")
    link = root / AGENT_DIR / "link.py"
    try:
        link.symlink_to(outside)
    except OSError:
        pytest.skip("symlinks need a privilege this account lacks")
    with pytest.raises(cc.Refused, match="outside"):
        cc.resolve_script(root, cc.load_config(root), f"{AGENT_DIR}/link.py")


def test_python_runs_with_the_project_venv_when_present(tmp_path: Path) -> None:
    root = _workspace(tmp_path)
    script = _script(root, f"{AGENT_DIR}/a.py", "")
    assert cc.interpreter_for(script, root) == [sys.executable, str(script)]
    venv = root / (".venv/Scripts/python.exe" if sys.platform == "win32" else ".venv/bin/python")
    venv.parent.mkdir(parents=True)
    venv.write_text("", encoding="utf-8")
    assert cc.interpreter_for(script, root) == [str(venv), str(script)]


@pytest.mark.skipif(sys.platform != "win32", reason="Windows PowerShell")
def test_powershell_runs_with_file_and_no_profile(tmp_path: Path) -> None:
    root = _workspace(tmp_path)
    script = _script(root, f"{AGENT_DIR}/a.ps1", "")
    assert cc.interpreter_for(script, root) == [
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(script),
    ]


# ── walltime ───────────────────────────────────────────────────────────────


CFG = cc.Config(dirs=[], approval="ask", walltime_default=600, walltime_max=3600, task_dirs=[])


@pytest.mark.parametrize(
    ("explicit", "history", "budget", "expected"),
    [
        (20, [999.0], 5, (20, "explicit")),
        (9000, [], None, (3600, "explicit-capped")),
        (None, [10.0, 20.0], 500, (40, "history")),
        (None, [2.0], None, (30, "history")),
        (None, [3000.0], None, (3600, "history")),
        (None, [], 170, (170, "suite-budget")),
        (None, [], None, (600, "default")),
    ],
    ids=["explicit", "explicit-capped", "history-x2", "history-floor", "history-capped", "budget", "default"],
)
def test_walltime_resolution_order(
    explicit: int | None, history: list[float], budget: int | None, expected: tuple[int, str]
) -> None:
    assert cc.resolve_walltime(explicit, history, budget, CFG) == expected


def test_history_uses_only_the_last_five_passing_runs(tmp_path: Path) -> None:
    root = _workspace(tmp_path)
    log = root / ".github" / "logs" / "command-runs.jsonl"
    log.parent.mkdir(parents=True)
    rows = [{"path": "p.py", "verdict": "PASS", "duration_s": d} for d in (500, 1, 2, 3, 4, 5)]
    rows += [
        {"path": "p.py", "verdict": "FAIL", "duration_s": 900},
        {"path": "q.py", "verdict": "PASS", "duration_s": 7},
    ]
    log.write_text("\n".join(json.dumps(r) for r in rows) + "\n", encoding="utf-8")
    assert cc.read_history(root, "p.py") == [1, 2, 3, 4, 5]


def test_a_suite_budget_is_found_by_basename(tmp_path: Path) -> None:
    root = _workspace(tmp_path)
    budgets = root / ".github" / "scripts" / "suite-budgets.json"
    budgets.write_text(json.dumps({"default": 120, "suites": {"test-x.ps1": 170}}), encoding="utf-8")
    assert cc.suite_budget(root, ".github/scripts/test-x.ps1") == 170
    assert cc.suite_budget(root, f"{AGENT_DIR}/other.py") is None


# ── running ────────────────────────────────────────────────────────────────


def _run(root: Path, rel: str, args: list[str] | None = None, walltime: int | None = None) -> dict:
    return cc.run_script(root, rel, args or [], walltime)


def test_a_fast_script_returns_at_once_not_after_the_walltime(tmp_path: Path) -> None:
    root = _workspace(tmp_path)
    _script(root, f"{AGENT_DIR}/ok.py", "print('hello')\n")
    t0 = time.monotonic()
    result = _run(root, f"{AGENT_DIR}/ok.py")
    assert result["verdict"] == "PASS"
    assert result["walltime_s"] == 600
    assert time.monotonic() - t0 < 5
    assert "hello" in result["tail"]


def test_a_failing_script_reports_its_exit_code_and_log(tmp_path: Path) -> None:
    root = _workspace(tmp_path)
    _script(root, f"{AGENT_DIR}/bad.py", "import sys\nprint('broken', sys.argv[1])\nsys.exit(3)\n")
    result = _run(root, f"{AGENT_DIR}/bad.py", ["arg one"])
    assert (result["verdict"], result["exit_code"]) == ("FAIL", 3)
    assert "broken arg one" in result["tail"]
    assert "broken arg one" in Path(result["log_path"]).read_text(encoding="utf-8")


def test_a_hanging_script_times_out_and_its_tree_is_killed(tmp_path: Path) -> None:
    root = _workspace(tmp_path)
    body = (
        "import pathlib, subprocess, sys, time\n"
        "child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])\n"
        "pathlib.Path(sys.argv[1]).write_text(str(child.pid))\n"
        "print('started', flush=True)\n"
        "time.sleep(60)\n"
    )
    _script(root, f"{AGENT_DIR}/hang.py", body)
    pid_file = tmp_path / "grandchild.pid"
    t0 = time.monotonic()
    result = _run(root, f"{AGENT_DIR}/hang.py", [str(pid_file)], walltime=3)
    assert result["verdict"] == "TIMEOUT"
    assert time.monotonic() - t0 < 15
    assert "started" in result["tail"]
    grandchild = int(pid_file.read_text())
    deadline = time.monotonic() + 5
    while _alive(grandchild) and time.monotonic() < deadline:
        time.sleep(0.2)
    assert not _alive(grandchild)


def test_the_tail_is_capped(tmp_path: Path) -> None:
    root = _workspace(tmp_path)
    _script(root, f"{AGENT_DIR}/loud.py", "for i in range(500):\n    print(f'line {i} ' + 'x' * 200)\n")
    tail = _run(root, f"{AGENT_DIR}/loud.py")["tail"]
    assert len(tail) <= 6000
    assert len(tail.splitlines()) <= 60
    assert "line 499" in tail


def test_each_run_is_logged_and_feeds_the_next_walltime(tmp_path: Path) -> None:
    root = _workspace(tmp_path)
    script = _script(root, f"{AGENT_DIR}/ok.py", "print('hi')\n")
    _run(root, f"{AGENT_DIR}/ok.py", ["a"])
    rows = [
        json.loads(line)
        for line in (root / ".github" / "logs" / "command-runs.jsonl").read_text(encoding="utf-8").splitlines()
    ]
    assert len(rows) == 1
    assert rows[0]["path"] == f"{AGENT_DIR}/ok.py"
    assert rows[0]["args"] == ["a"]
    assert rows[0]["verdict"] == "PASS"
    assert rows[0]["sha256"] == cc.content_hash(script)
    assert _run(root, f"{AGENT_DIR}/ok.py")["walltime_source"] == "history"


def test_a_refused_path_runs_nothing_and_says_why(tmp_path: Path) -> None:
    root = _workspace(tmp_path)
    result = _run(root, "../outside.py")
    assert result["verdict"] == "REFUSED"
    assert "outside" in result["reason"]


# ── header-declared arguments (#60, 2026-10-21) ──────────────────────────────

HEADED = "# af-command: Echo one file.\n# af-arg: PATH  The file\nimport sys\nprint('ran', *sys.argv[1:])\n"


def test_argv_matching_the_header_runs(tmp_path: Path) -> None:
    root = _workspace(tmp_path)
    _script(root, f"{AGENT_DIR}/echo.py", HEADED)
    result = _run(root, f"{AGENT_DIR}/echo.py", ["a.txt"])
    assert result["verdict"] == "PASS"
    assert "ran a.txt" in result["tail"]


def test_argv_violating_the_header_is_refused_before_approval(tmp_path: Path) -> None:
    root = _workspace(tmp_path)
    _script(root, f"{AGENT_DIR}/echo.py", HEADED)
    asked: list[str] = []
    result = cc.run_script(root, f"{AGENT_DIR}/echo.py", ["a", "b"], None, lambda r, d, c: asked.append(r.rel))
    assert result["verdict"] == "REFUSED"
    assert "usage: PATH" in result["reason"]
    assert asked == []  # nobody is asked to approve a call that cannot be right


def test_a_malformed_header_refuses_every_call(tmp_path: Path) -> None:
    root = _workspace(tmp_path)
    _script(root, f"{AGENT_DIR}/bad.py", "# af-arg: PATH\nprint('never')\n")
    result = _run(root, f"{AGENT_DIR}/bad.py", ["x"])
    assert result["verdict"] == "REFUSED"
    assert "header" in result["reason"]


def test_a_script_without_a_header_passes_argv_through(tmp_path: Path) -> None:
    root = _workspace(tmp_path)
    _script(root, f"{AGENT_DIR}/free.py", "import sys\nprint('got', *sys.argv[1:])\n")
    assert "got --anything 1 2" in _run(root, f"{AGENT_DIR}/free.py", ["--anything", "1", "2"])["tail"]
