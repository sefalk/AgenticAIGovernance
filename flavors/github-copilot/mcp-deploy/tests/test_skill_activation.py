"""An activated optional skill stays where the project moved it (#110).

``skills/INDEX.md`` documents activation as a *move* from
``skills/_available/{name}/`` to ``skills/{name}/``. The deploy re-created the
``_available/`` copy on every run, so an activated skill existed twice: in one
consumer four skills, unchanged for thirteen months. The active copy, meanwhile,
never received a framework fix.

Now, when the target has ``skills/{name}/``, the library source is redirected
onto the active copy and classified like any file. The moved file keeps the
baseline of its ``_available/`` key, so a project's edit is never mistaken for
an untouched file. This mirrors #384, which keeps a *deactivated* default
skill's ``_available/`` copy current.
"""

from __future__ import annotations

import hashlib
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

from af_deploy_mcp import deploy_core

AF_ROOT = Path(__file__).resolve().parents[2]  # flavors/github-copilot
NAME = "demo-skill"
AVAIL = f"skills/_available/{NAME}/SKILL.md"
ACTIVE = f"skills/{NAME}/SKILL.md"
OLD = "demo skill, as activated\n"
NEW = "demo skill, framework fix\n"
OURS = "demo skill, project edit\n"


def _write(p: Path, text: str) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8", newline="")


def _hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest().upper()


def _source(root: Path, content: str = NEW) -> Path:
    _write(root / "VERSION", "1.0.0\n")
    shutil.copy2(AF_ROOT / ".github" / ".af-manifest", _mk(root / ".github" / ".af-manifest"))
    _write(root / ".github" / AVAIL, content)
    return root


def _mk(p: Path) -> Path:
    p.parent.mkdir(parents=True, exist_ok=True)
    return p


def _activated(root: Path, content: str, *, duplicate: bool = False) -> Path:
    """A project that moved demo-skill out of _available/ after deploying OLD."""
    _write(root / ".github" / ACTIVE, content)
    if duplicate:
        _write(root / ".github" / AVAIL, OLD)
    _write(root / ".github" / ".af-hashes", f"# AF deployment baseline hashes\n{AVAIL}={_hash(OLD)}\n")
    return root


def _classes(src: Path, target: Path) -> dict[str, str]:
    return {f["path"]: f["classification"] for f in deploy_core.dry_run(src, target)["files"]}


# ── deploy_core ─────────────────────────────────────────────────────────────


def test_the_library_copy_is_not_recreated_beside_an_active_skill(tmp_path: Path) -> None:
    src = _source(tmp_path / "src")
    target = _activated(tmp_path / "proj", OLD)
    classes = _classes(src, target)
    assert classes[f".github/{AVAIL}"] == "ACTIVATED"
    assert classes[f".github/{ACTIVE}"] == "UPDATE"


def test_apply_updates_the_active_copy_and_leaves_available_empty(tmp_path: Path) -> None:
    src = _source(tmp_path / "src")
    target = _activated(tmp_path / "proj", OLD)
    report = deploy_core.apply(src, target)
    assert (target / ".github" / ACTIVE).read_text(encoding="utf-8") == NEW
    assert not (target / ".github" / AVAIL).exists()
    assert f".github/{ACTIVE}" in report["applied"]
    assert ACTIVE in deploy_core.read_baseline_hashes(target / ".github")


def test_an_edited_active_copy_is_a_conflict_not_an_overwrite(tmp_path: Path) -> None:
    # Without the moved baseline an edited copy would read as untouched and be overwritten.
    src = _source(tmp_path / "src")
    target = _activated(tmp_path / "proj", OURS)
    report = deploy_core.apply(src, target)
    assert (target / ".github" / ACTIVE).read_text(encoding="utf-8") == OURS
    assert {"path": f".github/{ACTIVE}", "classification": "CONFLICT"} in report["skipped"]


def test_an_unresolved_conflict_is_still_a_conflict_on_the_next_deploy(tmp_path: Path) -> None:
    # Dropping the moved-from key without carrying its baseline over would turn the
    # second run into "new in AF" -> UPDATE, overwriting the project's edit.
    src = _source(tmp_path / "src")
    target = _activated(tmp_path / "proj", OURS)
    deploy_core.apply(src, target)
    report = deploy_core.apply(src, target)
    assert (target / ".github" / ACTIVE).read_text(encoding="utf-8") == OURS
    assert {"path": f".github/{ACTIVE}", "classification": "CONFLICT"} in report["skipped"]


def test_an_edited_active_copy_without_a_framework_change_is_preserved(tmp_path: Path) -> None:
    src = _source(tmp_path / "src", content=OLD)
    target = _activated(tmp_path / "proj", OURS)
    assert _classes(src, target)[f".github/{ACTIVE}"] == "PRESERVE"


def test_a_leftover_duplicate_is_an_orphan(tmp_path: Path) -> None:
    src = _source(tmp_path / "src")
    target = _activated(tmp_path / "proj", OLD, duplicate=True)
    assert {"path": f".github/{AVAIL}", "key": AVAIL} in deploy_core.list_orphans(src, target)


def test_a_skill_that_was_never_activated_is_still_deployed_to_available(tmp_path: Path) -> None:
    src = _source(tmp_path / "src")
    target = tmp_path / "proj"
    (target / ".github").mkdir(parents=True)
    classes = _classes(src, target)
    assert classes[f".github/{AVAIL}"] == "CREATE"
    assert f".github/{ACTIVE}" not in classes


# ── validate-skills.py ──────────────────────────────────────────────────────


def test_validate_skills_names_an_overlap(tmp_path: Path) -> None:
    github = tmp_path / ".github"
    for rel in (ACTIVE, AVAIL):
        _write(github / rel, f"---\nname: {NAME}\ndescription: 'x'\n---\n\n# Demo\n")
    _write(github / "skills" / "INDEX.md", "# Skills\n")
    res = subprocess.run(
        [sys.executable, str(AF_ROOT / ".github" / "scripts" / "validate-skills.py"), "--root", str(github)],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert f"'{NAME}' is active and also in _available/" in res.stdout, res.stdout


# ── deploy.ps1 ──────────────────────────────────────────────────────────────


def _powershell() -> str | None:
    return shutil.which("pwsh") or shutil.which("powershell")


@pytest.mark.skipif(_powershell() is None, reason="PowerShell not available")
@pytest.mark.parametrize(
    ("project_content", "verdict", "written"),
    [(OLD, "UPDATE", NEW), (OURS, "CONFLICT", OURS)],
    ids=["untouched-active-copy-is-updated", "edited-active-copy-stays-conflict"],
)
def test_deploy_ps1_agrees(tmp_path: Path, project_content: str, verdict: str, written: str) -> None:
    src = _source(tmp_path / "src")
    shutil.copy2(AF_ROOT / "deploy.ps1", src / "deploy.ps1")
    target = _activated(tmp_path / "proj", project_content)
    subprocess.run(["git", "init", "-q", str(target)], check=True)

    res = _run_ps1(src, target)

    lines = res.stdout.splitlines()
    assert any(line.strip().startswith(verdict) and ACTIVE in line for line in lines), res.stdout + res.stderr
    assert (target / ".github" / ACTIVE).read_text(encoding="utf-8") == written
    assert not (target / ".github" / AVAIL).exists()


@pytest.mark.skipif(_powershell() is None, reason="PowerShell not available")
def test_deploy_ps1_keeps_an_unresolved_conflict_on_the_next_run(tmp_path: Path) -> None:
    src = _source(tmp_path / "src")
    shutil.copy2(AF_ROOT / "deploy.ps1", src / "deploy.ps1")
    target = _activated(tmp_path / "proj", OURS)
    subprocess.run(["git", "init", "-q", str(target)], check=True)

    _run_ps1(src, target)
    res = _run_ps1(src, target)

    lines = res.stdout.splitlines()
    assert any(line.strip().startswith("CONFLICT") and ACTIVE in line for line in lines), res.stdout + res.stderr
    assert (target / ".github" / ACTIVE).read_text(encoding="utf-8") == OURS


def _run_ps1(src: Path, target: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [_powershell(), "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(src / "deploy.ps1")]
        + ["-TargetDir", str(target)],
        capture_output=True,
        text=True,
        timeout=300,
        stdin=subprocess.DEVNULL,
    )
