"""The test log is written by pytest itself, whoever starts it (#180).

`.github/test-log.json` is the cross-agent record of test runs and carries the
per-workflow budget, but only `run-tests.ps1/.sh` wrote it: a run through the
VS Code `runTests` tool, Test Explorer or a bare `pytest` left no entry, and a
missing entry reads exactly like "never run". The `af_test_log` plugin, loaded
from the project's `pyproject.toml`, writes the same entry shape for every
invocation. The wrappers keep writing their own entry and switch the plugin off
for their runs, so nothing is written twice.
"""

# copilot:generated | coordinator | 2026-10-20

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

AF_ROOT = Path(__file__).resolve().parents[2]
PLUGIN = AF_ROOT / ".github" / "scripts" / "af_test_log.py"
PYPROJECT = (
    "[tool.pytest.ini_options]\npythonpath = ['.github/scripts']\naddopts = '-p af_test_log'\ntestpaths = ['tests']\n"
)


@pytest.fixture
def project(tmp_path: Path) -> Path:
    (tmp_path / ".github" / "scripts").mkdir(parents=True)
    if PLUGIN.is_file():
        shutil.copy2(PLUGIN, tmp_path / ".github" / "scripts" / PLUGIN.name)
    (tmp_path / "pyproject.toml").write_text(PYPROJECT, encoding="utf-8")
    (tmp_path / "tests" / "domain").mkdir(parents=True)
    (tmp_path / "tests" / "adapters").mkdir(parents=True)
    (tmp_path / "tests" / "domain" / "test_d.py").write_text(
        "def test_a():\n    assert True\n\ndef test_b():\n    assert True\n", encoding="utf-8"
    )
    (tmp_path / "tests" / "adapters" / "test_a.py").write_text("def test_c():\n    assert 1 == 2\n", encoding="utf-8")
    return tmp_path


def _pytest(project: Path, *args: str, env: dict | None = None) -> subprocess.CompletedProcess:
    run_env = {k: v for k, v in os.environ.items() if k != "AF_TEST_LOG_BY_WRAPPER"}
    run_env.update(env or {})
    return subprocess.run(
        [sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider", *args],
        cwd=project,
        capture_output=True,
        text=True,
        env=run_env,
    )


def _log(project: Path) -> dict:
    return json.loads((project / ".github" / "test-log.json").read_text(encoding="utf-8-sig"))


def test_scope_run_writes_the_scope_entry(project):
    _pytest(project, "tests/domain")
    entry = _log(project)["domain"]
    assert entry["status"] == "ok"
    assert (entry["passed"], entry["failed"], entry["errors"], entry["total"]) == (2, 0, 0, 2)
    assert entry["partial"] is False
    assert entry["run_by"] == "pytest-plugin"
    assert entry["exit_code"] == 0


def test_whole_suite_is_all_and_counts_failures(project):
    _pytest(project, "tests")
    entry = _log(project)["all"]
    assert (entry["passed"], entry["failed"], entry["exit_code"]) == (2, 1, 1)
    assert entry["status"] == "ok"


def test_no_arguments_follow_testpaths(project):
    _pytest(project)
    assert "all" in _log(project)


def test_a_single_file_or_filter_is_partial_never_a_scope(project):
    _pytest(project, "tests/domain/test_d.py")
    log = _log(project)
    assert "domain" not in log
    assert log["partial"]["partial"] is True
    assert log["partial"]["target"] == "tests/domain/test_d.py"
    _pytest(project, "tests/domain", "-k", "test_a")
    log = _log(project)
    assert "domain" not in log
    assert log["partial"]["selector"] == "test_a"


def test_other_entries_survive(project):
    (project / ".github" / "test-log.json").write_text(
        json.dumps({"contracts": {"status": "ok", "passed": 7}}), encoding="utf-8-sig"
    )
    _pytest(project, "tests/domain")
    log = _log(project)
    assert log["contracts"] == {"status": "ok", "passed": 7}
    assert "domain" in log


def test_an_interrupted_run_stays_running(project):
    (project / "tests" / "domain" / "test_kill.py").write_text(
        "import os\n\ndef test_kill():\n    os._exit(3)\n", encoding="utf-8"
    )
    _pytest(project, "tests/domain")
    entry = _log(project)["domain"]
    assert entry["status"] == "running"
    assert entry["passed"] is None


def test_a_wrapper_run_is_left_to_the_wrapper(project):
    _pytest(project, "tests/domain", env={"AF_TEST_LOG_BY_WRAPPER": "1"})
    assert not (project / ".github" / "test-log.json").exists()


@pytest.mark.parametrize("wrapper", ["run-tests.ps1", "run-tests.sh"])
def test_wrappers_switch_the_plugin_off(wrapper):
    assert "AF_TEST_LOG_BY_WRAPPER" in (AF_ROOT / ".github" / "scripts" / wrapper).read_text(encoding="utf-8")


# ── The deploy says when a project has not loaded the plugin ────────────────

NOTE = "af_test_log"


def test_mcp_apply_notes_a_missing_registration(tmp_path, minimal_source):
    from af_deploy_mcp import deploy_core

    target = tmp_path / "proj"
    target.mkdir()
    (target / "pyproject.toml").write_text("[project]\nname = 'x'\n", encoding="utf-8")
    assert any(NOTE in line for line in deploy_core.apply(minimal_source, target)["test_log_plugin"])


def test_the_note_goes_once_registered_and_never_without_a_pyproject(tmp_path):
    from af_deploy_mcp import deploy_core

    assert deploy_core.test_log_plugin_note(tmp_path) == []
    (tmp_path / "pyproject.toml").write_text(PYPROJECT, encoding="utf-8")
    assert deploy_core.test_log_plugin_note(tmp_path) == []


def _pwsh() -> str | None:
    return next((exe for exe in ("pwsh", "powershell") if shutil.which(exe)), None)


@pytest.mark.skipif(_pwsh() is None, reason="PowerShell not available")
def test_ps1_deploy_notes_a_missing_registration(tmp_path, minimal_source):
    target = tmp_path / "proj"
    target.mkdir()
    (target / "pyproject.toml").write_text("[project]\nname = 'x'\n", encoding="utf-8")
    res = subprocess.run(
        [
            _pwsh(),
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(minimal_source / "deploy.ps1"),
            "-TargetDir",
            str(target),
            "-Force",
        ],
        capture_output=True,
        text=True,
        timeout=300,
    )
    assert res.returncode == 0, res.stdout + res.stderr
    assert "-p af_test_log" in res.stdout
