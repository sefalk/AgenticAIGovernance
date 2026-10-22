"""A deploy records the source commit, because VERSION no longer moves per commit (#426).

The pre-commit hook used to bump the patch number on every framework commit, so
`version:` in `.github/.af-version` identified the exact source a project was
deployed from. That bump made every pair of parallel pull requests conflict on
the same line, and it is gone: VERSION now changes only at a release cut. The
identity moves to a `commit:` line, and `status` compares commits when both
sides have one, so "stale" still means "the source moved since this deploy".

A payload that is not a tracked part of a git checkout -- the copy bundled into
the wheel, or a scratch directory -- has no commit, and status falls back to the
version comparison it always made.
"""

# copilot:generated | coordinator | 2026-10-21

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

from af_deploy_mcp import deploy_core

AF_ROOT = Path(__file__).resolve().parents[2]  # flavors/github-copilot

pytestmark = pytest.mark.skipif(shutil.which("git") is None, reason="git not available")


def _git(cwd: Path, *args: str) -> str:
    res = subprocess.run(
        ["git", "-c", "user.name=af-test", "-c", "user.email=af-test@example.invalid", *args],
        cwd=cwd,
        check=True,
        capture_output=True,
        text=True,
    )
    return res.stdout.strip()


def _write(p: Path, text: str) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8", newline="\n")


def _payload(root: Path) -> Path:
    _write(root / "VERSION", "1.0.0\n")
    _write(root / ".github" / ".af-manifest", (AF_ROOT / ".github" / ".af-manifest").read_text(encoding="utf-8"))
    _write(root / ".github" / "MANIFEST.md", "manifest v1\n")
    return root


def _committed(root: Path) -> tuple[Path, str]:
    _payload(root)
    _git(root, "init", "-q", "-b", "main")
    _git(root, "add", "--", "VERSION", ".github")
    _git(root, "commit", "-q", "--no-verify", "-m", "seed")
    return root, _git(root, "rev-parse", "--short=12", "HEAD")


def _target(tmp_path: Path) -> Path:
    target = tmp_path / "proj"
    target.mkdir()
    return target


# ── source_commit ───────────────────────────────────────────────────────────


def test_a_committed_payload_reports_its_head(tmp_path: Path) -> None:
    src, head = _committed(tmp_path / "src")
    assert deploy_core.source_commit(src) == head


def test_an_edited_tracked_file_marks_the_commit_dirty(tmp_path: Path) -> None:
    src, head = _committed(tmp_path / "src")
    _write(src / ".github" / "MANIFEST.md", "manifest, edited\n")
    assert deploy_core.source_commit(src) == f"{head}-dirty"


def test_an_untracked_file_does_not_mark_it_dirty(tmp_path: Path) -> None:
    src, head = _committed(tmp_path / "src")
    _write(src / "scratch.txt", "not part of the payload\n")
    assert deploy_core.source_commit(src) == head


def test_a_payload_outside_git_has_no_commit(tmp_path: Path) -> None:
    assert deploy_core.source_commit(_payload(tmp_path / "src")) == ""


def test_an_untracked_payload_inside_a_repo_has_no_commit(tmp_path: Path) -> None:
    # The wheel's payload under mcp-deploy/.venv sits inside the framework
    # checkout. Reporting that checkout's HEAD would name a commit the copy was
    # not taken from.
    repo, _ = _committed(tmp_path / "repo")
    copy = _payload(repo / ".venv" / "payload")
    assert deploy_core.source_commit(copy) == ""


# ── the wheel's payload carries its build commit (#429) ──────────────────────────────────


def test_a_bundled_payload_reports_the_commit_stamped_at_build(tmp_path: Path) -> None:
    src = _payload(tmp_path / "payload")
    _write(src / "SOURCE_COMMIT", "0123456789ab\n")
    assert deploy_core.source_commit(src) == "0123456789ab"


def test_a_stamp_that_is_not_a_commit_is_ignored(tmp_path: Path) -> None:
    src = _payload(tmp_path / "payload")
    _write(src / "SOURCE_COMMIT", "see the release notes\n")
    assert deploy_core.source_commit(src) == ""


def test_a_tracked_checkout_wins_over_a_stale_stamp(tmp_path: Path) -> None:
    src, head = _committed(tmp_path / "src")
    _write(src / "SOURCE_COMMIT", "0123456789ab\n")
    assert deploy_core.source_commit(src) == head


def test_the_build_hook_stamps_the_payload(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    import importlib.util
    import sys
    import types

    # Hatchling is not in the dev venv; the hook only needs the base class.
    iface = types.ModuleType("hatchling.builders.hooks.plugin.interface")

    class BuildHookInterface:
        def __init__(self, root: str) -> None:
            self.root = root

    iface.BuildHookInterface = BuildHookInterface
    for name in ("hatchling", "hatchling.builders", "hatchling.builders.hooks", "hatchling.builders.hooks.plugin"):
        monkeypatch.setitem(sys.modules, name, types.ModuleType(name))
    monkeypatch.setitem(sys.modules, iface.__name__, iface)

    spec = importlib.util.spec_from_file_location("af_hatch_build", AF_ROOT / "mcp-deploy" / "hatch_build.py")
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    src, head = _committed(tmp_path / "src")
    (src / "mcp-deploy").mkdir()
    hook = module.SourceCommitHook(str(src / "mcp-deploy"))
    build_data: dict = {"force_include": {}}
    hook.initialize("standard", build_data)
    [(stamp, dest)] = build_data["force_include"].items()
    assert dest == "af_deploy_mcp/payload/SOURCE_COMMIT"
    assert Path(stamp).read_text(encoding="utf-8").strip() == head


def test_pyproject_registers_the_build_hook() -> None:
    text = (AF_ROOT / "mcp-deploy" / "pyproject.toml").read_text(encoding="utf-8")
    assert "[tool.hatch.build.targets.wheel.hooks.custom]" in text


# ── .af-version ─────────────────────────────────────────────────────────────


def test_apply_records_the_commit(tmp_path: Path) -> None:
    src, head = _committed(tmp_path / "src")
    target = _target(tmp_path)
    deploy_core.apply(src, target)
    assert deploy_core.read_deployed_commit(target) == head
    assert f"commit: {head}\n" in (target / ".github" / ".af-version").read_text(encoding="utf-8")


def test_apply_without_a_commit_writes_no_commit_line(tmp_path: Path) -> None:
    target = _target(tmp_path)
    deploy_core.apply(_payload(tmp_path / "src"), target)
    assert "commit:" not in (target / ".github" / ".af-version").read_text(encoding="utf-8")
    assert deploy_core.read_deployed_commit(target) == ""


# ── status ──────────────────────────────────────────────────────────────────


def test_status_is_up_to_date_at_the_deployed_commit(tmp_path: Path) -> None:
    src, head = _committed(tmp_path / "src")
    target = _target(tmp_path)
    deploy_core.apply(src, target)
    result = deploy_core.status(src, target)
    assert result["state"] == "up-to-date"
    assert result["source_commit"] == head
    assert result["deployed_commit"] == head


def test_status_is_stale_after_a_commit_at_the_same_version(tmp_path: Path) -> None:
    # The case the per-commit bump used to catch: VERSION unchanged, source moved.
    src, _ = _committed(tmp_path / "src")
    target = _target(tmp_path)
    deploy_core.apply(src, target)
    _write(src / ".github" / "MANIFEST.md", "manifest v2\n")
    _git(src, "commit", "-q", "--no-verify", "-am", "change")
    result = deploy_core.status(src, target)
    assert result["source_version"] == result["deployed_version"]
    assert result["state"] == "stale"


def test_status_falls_back_to_the_version_without_a_deployed_commit(tmp_path: Path) -> None:
    # A project last deployed before #426 has no commit line.
    src, _ = _committed(tmp_path / "src")
    target = _target(tmp_path)
    _write(target / ".github" / ".af-version", "version: 1.0.0\ndeployed: 2026-10-01T00:00:00\nsource: x\n")
    result = deploy_core.status(src, target)
    assert result["deployed_commit"] == ""
    assert result["state"] == "up-to-date"


def test_status_falls_back_to_the_version_without_a_source_commit(tmp_path: Path) -> None:
    src = _payload(tmp_path / "src")
    target = _target(tmp_path)
    _write(target / ".github" / ".af-version", "version: 0.9.0\ncommit: 0123456789ab\n")
    result = deploy_core.status(src, target)
    assert result["source_commit"] == ""
    assert result["state"] == "stale"


# ── deploy.ps1 records the same line (the bash leg: test-deploy-available-sync.sh) ──


def _powershell() -> str | None:
    return shutil.which("pwsh") or shutil.which("powershell")


def _ps1_deploy(src: Path, target: Path) -> None:
    shutil.copy2(AF_ROOT / "deploy.ps1", src / "deploy.ps1")
    subprocess.run(
        [_powershell(), "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(src / "deploy.ps1")]
        + ["-TargetDir", str(target)],
        capture_output=True,
        text=True,
        timeout=300,
        stdin=subprocess.DEVNULL,
        check=False,
    )


@pytest.mark.skipif(_powershell() is None, reason="PowerShell not available")
def test_deploy_ps1_records_the_commit_deploy_core_records(tmp_path: Path) -> None:
    src, head = _committed(tmp_path / "src")
    target = _target(tmp_path)
    subprocess.run(["git", "init", "-q", str(target)], check=True)
    _ps1_deploy(src, target)
    # deploy.ps1 itself is untracked in src, so the payload is not dirty.
    assert deploy_core.read_deployed_commit(target) == head


@pytest.mark.skipif(_powershell() is None, reason="PowerShell not available")
def test_deploy_ps1_writes_no_commit_line_outside_git(tmp_path: Path) -> None:
    src = _payload(tmp_path / "src")
    target = _target(tmp_path)
    subprocess.run(["git", "init", "-q", str(target)], check=True)
    _ps1_deploy(src, target)
    text = (target / ".github" / ".af-version").read_text(encoding="utf-8")
    assert text.startswith("version: 1.0.0\n")
    assert "commit:" not in text
