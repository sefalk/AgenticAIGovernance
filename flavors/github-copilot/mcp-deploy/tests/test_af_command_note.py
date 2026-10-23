"""The deploy says when a project has no `af-command` server registered (#445).

Since #60 removed `createAndRunTask`, argument-bearing script runs have one
route: `af-command/run_script`. The agent files reference the server by the key
`af-command`, so that key -- not the executable path -- decides whether the
tools resolve. Measured on MP (2026-10-22): the registration lives in the
`.code-workspace` file one level above the repo, not in `.vscode/mcp.json`.
"""

# copilot:generated | test-writer | 2026-10-22

from __future__ import annotations

import shutil
import subprocess

import pytest

NOTE = "af-command is not registered"
SERVER = '{"servers": {"af-command": {"type": "stdio", "command": "af-command-mcp.exe"}}}'
WORKSPACE = '{"folders": [{"path": "proj"}], "settings": {"mcp": {"servers": {"af-command": {"command": "x"}}}}}'


def _note(target):
    from af_deploy_mcp import deploy_core

    return deploy_core.af_command_note(target)


def test_a_project_without_any_registration_gets_the_note(tmp_path):
    target = tmp_path / "proj"
    target.mkdir()
    assert any(NOTE in line for line in _note(target))


def test_a_registration_in_vscode_mcp_json_silences_it(tmp_path):
    target = tmp_path / "proj"
    (target / ".vscode").mkdir(parents=True)
    (target / ".vscode" / "mcp.json").write_text(SERVER, encoding="utf-8")
    assert _note(target) == []


def test_a_registration_in_a_workspace_file_beside_the_repo_silences_it(tmp_path):
    target = tmp_path / "proj"
    target.mkdir()
    (tmp_path / "proj.code-workspace").write_text(WORKSPACE, encoding="utf-8")
    assert _note(target) == []


def test_a_registration_in_a_workspace_file_inside_the_repo_silences_it(tmp_path):
    target = tmp_path / "proj"
    target.mkdir()
    (target / "team.code-workspace").write_text(WORKSPACE, encoding="utf-8")
    assert _note(target) == []


def test_only_the_af_command_key_counts_not_a_sibling_server(tmp_path):
    target = tmp_path / "proj"
    (target / ".vscode").mkdir(parents=True)
    (target / ".vscode" / "mcp.json").write_text(
        '{"servers": {"af": {"command": "af-deploy-mcp.exe"}}}', encoding="utf-8"
    )
    assert any(NOTE in line for line in _note(target))


def test_mcp_apply_reports_the_note(tmp_path, minimal_source):
    from af_deploy_mcp import deploy_core

    target = tmp_path / "proj"
    target.mkdir()
    assert any(NOTE in line for line in deploy_core.apply(minimal_source, target)["af_command"])


def test_mcp_apply_states_the_local_harness_scope(tmp_path, minimal_source):
    # The guards were built and measured in the Local harness only (#443, decision A).
    from af_deploy_mcp import deploy_core

    target = tmp_path / "proj"
    target.mkdir()
    assert any("Local harness only" in line for line in deploy_core.apply(minimal_source, target)["harness"])


def _pwsh() -> str | None:
    return next((exe for exe in ("pwsh", "powershell") if shutil.which(exe)), None)


@pytest.mark.skipif(_pwsh() is None, reason="PowerShell not available")
def test_ps1_deploy_notes_a_missing_registration(tmp_path, minimal_source):
    target = tmp_path / "proj"
    target.mkdir()
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
    assert NOTE in res.stdout
    assert "Local harness only" in res.stdout


@pytest.mark.skipif(_pwsh() is None, reason="PowerShell not available")
def test_ps1_deploy_is_silent_once_registered(tmp_path, minimal_source):
    target = tmp_path / "proj"
    (target / ".vscode").mkdir(parents=True)
    (target / ".vscode" / "mcp.json").write_text(SERVER, encoding="utf-8")
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
    assert NOTE not in res.stdout
