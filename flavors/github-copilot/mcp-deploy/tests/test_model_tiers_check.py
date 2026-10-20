"""Tier model names are checked against Copilot's model catalogue (#421).

VS Code greys out an unknown `model:` entry ("Unknown model ... will be
ignored") but reports it as neither error nor warning, so no agent sees it, and
a tier whose every entry is unknown silently falls back to the picker model.
Copilot Chat writes its full `/models` catalogue to `models.json` in each
debug-log session directory; `check-model-tiers.py` compares the effective
tier lists against the newest copy, and every deploy path reports the result.
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

from af_deploy_mcp import deploy_core

AF_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = AF_ROOT / ".github" / "scripts" / "check-model-tiers.py"
DEFAULTS = (
    "AF_MODEL_DEFAULT_PREMIUM=Known Big (copilot)\n"
    "AF_MODEL_DEFAULT_BALANCED=Known Mid (copilot), Gone Model (copilot)\n"
    "AF_MODEL_DEFAULT_EFFICIENT=Known Small (copilot)\n"
)


def _catalogue(path: Path, *names: str) -> Path:
    entries = [{"name": n, "capabilities": {"type": "chat"}, "model_picker_enabled": True} for n in names]
    entries.append({"name": "Embedder", "capabilities": {"type": "embeddings"}})
    path.write_text(json.dumps(entries), encoding="utf-8")
    return path


def _run(*args: str, env: dict | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args], capture_output=True, text=True, env=env or os.environ.copy()
    )


@pytest.fixture
def envs(tmp_path: Path) -> tuple[Path, Path, Path]:
    source = tmp_path / "source.conf"
    source.write_text(DEFAULTS, encoding="utf-8")
    target = tmp_path / "target.conf"
    target.write_text("AF_MODEL_TIER_PREMIUM=\n", encoding="utf-8")
    catalogue = _catalogue(tmp_path / "models.json", "Known Big", "Known Mid", "Known Small")
    return source, target, catalogue


def test_unknown_model_is_flagged_with_its_tier(envs):
    source, target, catalogue = envs
    res = _run("--source-env", str(source), "--target-env", str(target), "--models-json", str(catalogue))
    assert res.returncode == 1, res.stdout + res.stderr
    assert "Gone Model (copilot)" in res.stdout
    assert "BALANCED" in res.stdout
    assert "Known Mid" not in res.stdout.split("WARN", 1)[-1]


def test_all_known_passes_and_names_the_catalogue(envs, tmp_path):
    source, target, _ = envs
    catalogue = _catalogue(tmp_path / "all.json", "Known Big", "Known Mid", "Known Small", "Gone Model")
    res = _run("--source-env", str(source), "--target-env", str(target), "--models-json", str(catalogue))
    assert res.returncode == 0, res.stdout + res.stderr
    assert str(catalogue) in res.stdout


def test_project_override_is_checked_instead_of_the_default(envs):
    source, target, catalogue = envs
    target.write_text("AF_MODEL_TIER_BALANCED=Known Mid (copilot)\n", encoding="utf-8")
    res = _run("--source-env", str(source), "--target-env", str(target), "--models-json", str(catalogue))
    assert res.returncode == 0, res.stdout + res.stderr


def test_no_catalogue_is_not_measurable_never_a_pass(envs, tmp_path):
    source, target, _ = envs
    res = _run("--source-env", str(source), "--target-env", str(target), "--models-json", str(tmp_path / "nope.json"))
    assert res.returncode == 2, res.stdout + res.stderr
    assert "not checked" in res.stdout


def test_catalogue_path_comes_from_the_environment(envs):
    source, target, catalogue = envs
    env = os.environ.copy()
    env["AF_MODELS_JSON"] = str(catalogue)
    res = _run("--source-env", str(source), "--target-env", str(target), env=env)
    assert res.returncode == 1, res.stdout + res.stderr


def test_newest_catalogue_is_discovered_in_vscode_storage(envs, tmp_path):
    # The real path: no override, found under the VS Code user storage root.
    source, target, _ = envs
    home = tmp_path / "home"
    if sys.platform == "win32":
        user = tmp_path / "Code" / "User"
    elif sys.platform == "darwin":
        user = home / "Library" / "Application Support" / "Code" / "User"
    else:
        user = home / ".config" / "Code" / "User"
    session = user / "workspaceStorage" / "ws" / "GitHub.copilot-chat" / "debug-logs" / "s1"
    session.mkdir(parents=True)
    found = _catalogue(session / "models.json", "Known Big", "Known Mid", "Known Small", "Gone Model")
    env = {k: v for k, v in os.environ.items() if k != "AF_MODELS_JSON"}
    env.update(APPDATA=str(tmp_path), HOME=str(home), USERPROFILE=str(home))
    res = _run("--source-env", str(source), "--target-env", str(target), env=env)
    assert res.returncode == 0, res.stdout + res.stderr
    assert str(found) in res.stdout


def test_mcp_apply_reports_the_check(tmp_path, monkeypatch):
    catalogue = _catalogue(tmp_path / "models.json", "Nothing Real")
    monkeypatch.setenv("AF_MODELS_JSON", str(catalogue))
    target = tmp_path / "proj"
    target.mkdir()
    result = deploy_core.apply(AF_ROOT, target)
    check = result["model_check"]
    assert check["exit"] == 1
    assert any("WARN" in line for line in check["lines"])


def _pwsh() -> str | None:
    return next((exe for exe in ("pwsh", "powershell") if shutil.which(exe)), None)


@pytest.mark.skipif(_pwsh() is None, reason="PowerShell not available")
def test_ps1_deploy_prints_the_warning(tmp_path):
    catalogue = _catalogue(tmp_path / "models.json", "Nothing Real")
    target = tmp_path / "proj"
    target.mkdir()
    env = os.environ.copy()
    env["AF_MODELS_JSON"] = str(catalogue)
    res = subprocess.run(
        [
            _pwsh(),
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(AF_ROOT / "deploy.ps1"),
            "-TargetDir",
            str(target),
            "-Force",
        ],
        capture_output=True,
        text=True,
        timeout=300,
        env=env,
    )
    assert res.returncode == 0, res.stdout + res.stderr
    assert "unknown model" in res.stdout
