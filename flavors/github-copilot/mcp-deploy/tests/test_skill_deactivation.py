"""Skill-deactivation churn suppression (measure #3, Option B).

When a project deactivates an active-by-default framework skill, `/af-curate-skills`
*moves* it to `skills/_available/{name}/` (instead of deleting it). The deploy must
then classify the framework's `skills/{name}/…` files as **DEACTIVATED** — not
CREATE — so a deactivated skill is not re-activated on every deploy.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

from af_deploy_mcp import deploy_core

AF_ROOT = Path(__file__).resolve().parents[2]  # flavors/github-copilot
DEPLOY_PS1 = AF_ROOT / "deploy.ps1"
DEPLOY_SH = AF_ROOT / "deploy.sh"


def _pwsh() -> str | None:
    for exe in ("pwsh", "powershell"):
        if shutil.which(exe):
            return exe
    return None


def _first_active_skill() -> str:
    skills = AF_ROOT / ".github" / "skills"
    for p in sorted(skills.iterdir()):
        if p.is_dir() and p.name != "_available" and (p / "SKILL.md").is_file():
            return p.name
    raise RuntimeError("no active framework skill found")


def _target_with_available(tmp_path: Path, name: str) -> Path:
    target = tmp_path / "proj"
    avail = target / ".github" / "skills" / "_available" / name
    avail.mkdir(parents=True)
    (avail / "SKILL.md").write_text("dummy\n", encoding="utf-8")
    return target


def test_is_deactivated_skill_unit(tmp_path: Path) -> None:
    tg = tmp_path / ".github"
    (tg / "skills" / "_available" / "git-worktrees").mkdir(parents=True)
    assert deploy_core._is_deactivated_skill_unit("skills/git-worktrees/SKILL.md", tg)
    # not moved to _available -> not deactivated
    assert not deploy_core._is_deactivated_skill_unit("skills/hexagonal-architecture/SKILL.md", tg)
    # the _available copy itself is not a deactivated active skill
    assert not deploy_core._is_deactivated_skill_unit("skills/_available/git-worktrees/SKILL.md", tg)
    # non-skill paths never match
    assert not deploy_core._is_deactivated_skill_unit("agents/implementer.agent.md", tg)
    assert not deploy_core._is_deactivated_skill_unit("skills/INDEX.md", tg)


def test_dry_run_suppresses_create_for_moved_skill(tmp_path: Path) -> None:
    name = _first_active_skill()
    target = _target_with_available(tmp_path, name)
    report = deploy_core.dry_run(AF_ROOT, target)
    by_path = {f["path"]: f["classification"] for f in report["files"]}
    assert by_path[f".github/skills/{name}/SKILL.md"] == "DEACTIVATED"
    assert report["counts"].get("DEACTIVATED", 0) >= 1
    # It must NOT be counted as a CREATE.
    assert f".github/skills/{name}/SKILL.md" not in {
        f["path"] for f in report["files"] if f["classification"] == "CREATE"
    }


def test_dry_run_creates_skill_without_available_marker(tmp_path: Path) -> None:
    name = _first_active_skill()
    target = tmp_path / "proj"
    (target / ".github").mkdir(parents=True)
    report = deploy_core.dry_run(AF_ROOT, target)
    by_path = {f["path"]: f["classification"] for f in report["files"]}
    assert by_path[f".github/skills/{name}/SKILL.md"] == "CREATE"
    assert report["counts"].get("DEACTIVATED", 0) == 0


def test_apply_does_not_write_deactivated_skill(tmp_path: Path) -> None:
    name = _first_active_skill()
    target = _target_with_available(tmp_path, name)
    result = deploy_core.apply(AF_ROOT, target)
    assert not (target / ".github" / "skills" / name / "SKILL.md").exists()
    skipped = {s["path"]: s["classification"] for s in result["skipped"]}
    assert skipped.get(f".github/skills/{name}/SKILL.md") == "DEACTIVATED"


def test_apply_does_not_baseline_deactivated_skill(tmp_path: Path) -> None:
    name = _first_active_skill()
    target = _target_with_available(tmp_path, name)
    deploy_core.apply(AF_ROOT, target)
    baseline = deploy_core.read_baseline_hashes(target / ".github")
    assert f"skills/{name}/SKILL.md" not in baseline


def _pwsh() -> str | None:
    for exe in ("pwsh", "powershell"):
        if shutil.which(exe):
            return exe
    return None


def test_ps1_dry_run_suppresses_deactivated_skill(tmp_path: Path) -> None:
    exe = _pwsh()
    if exe is None or not DEPLOY_PS1.is_file():
        pytest.skip("PowerShell or deploy.ps1 not available")
    name = _first_active_skill()
    target = _target_with_available(tmp_path, name)
    res = subprocess.run(
        [
            exe,
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(DEPLOY_PS1),
            "-TargetDir",
            str(target),
            "-DryRun",
        ],
        capture_output=True,
        text=True,
        timeout=300,
    )
    assert res.returncode == 0, res.stdout + res.stderr
    assert f"DEACTIVATED .github/skills/{name}/SKILL.md" in res.stdout, res.stdout
    assert f"CREATE  .github/skills/{name}/SKILL.md" not in res.stdout, res.stdout


def test_sh_dry_run_suppresses_deactivated_skill(tmp_path: Path) -> None:
    if shutil.which("bash") is None or shutil.which("git") is None or not DEPLOY_SH.is_file():
        pytest.skip("bash/git or deploy.sh not available")
    name = _first_active_skill()
    target = _target_with_available(tmp_path, name)
    # deploy.sh detects the target's git branch under set -euo pipefail, so the
    # target must be a git repo (see GH #1); git-init to isolate that concern.
    subprocess.run(["git", "init", "-q", str(target)], check=True, timeout=60)
    res = subprocess.run(
        ["bash", str(DEPLOY_SH), "--target", str(target), "--dry-run"],
        capture_output=True,
        text=True,
        timeout=300,
    )
    assert res.returncode == 0, res.stdout + res.stderr
    assert f"DEACTIVATED .github/skills/{name}/SKILL.md" in res.stdout, res.stdout
    assert f"CREATE  .github/skills/{name}/SKILL.md" not in res.stdout, res.stdout
