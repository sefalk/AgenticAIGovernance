"""Files git ignores in the source checkout are not payload (#454).

The foreign-work guard writes `.github/logs/.worktree-baseline-*` next to the
payload. They are ignored there, yet every deploy path and the wheel build
enumerated them like payload files: a dry run against a consumer listed
`CREATE .github/logs/.worktree-baseline-s1` and `UPDATE ...-shared`, so an apply
would have overwritten the consumer's own guard state with this repository's.

Ignored means ignored by git in the source checkout. A tracked file stays
payload even where a pattern matches it (`logs/README.md`), and so does an
untracked file nobody ignored: a hotfix deploys from an uncommitted tree. A
source that is no checkout (the bundled wheel payload) behaves as before.
"""

from __future__ import annotations

import importlib.util
import shutil
import subprocess
import sys
import types
from pathlib import Path

import pytest

from af_deploy_mcp import deploy_core

AF_ROOT = Path(__file__).resolve().parents[2]  # flavors/github-copilot
MCP_ROOT = AF_ROOT / "mcp-deploy"

IGNORED = "logs/.worktree-baseline-shared"
UNTRACKED = "instructions/zz-untracked.instructions.md"
TRACKED = ("logs/.gitignore", "logs/README.md", "instructions/tracked.instructions.md")

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


def _layout(root: Path) -> None:
    gh = root / ".github"
    (gh / "logs").mkdir(parents=True, exist_ok=True)
    shutil.copy2(AF_ROOT / ".github" / "logs" / ".gitignore", gh / "logs" / ".gitignore")
    _write(gh / "logs" / "README.md", "logs readme\n")
    _write(gh / "instructions" / "tracked.instructions.md", "tracked\n")


def _dirty(root: Path) -> None:
    gh = root / ".github"
    _write(gh / IGNORED, "# created 2026-10-23T09:39:41Z\n# head deadbeef\n M foreign/path\n")
    _write(gh / UNTRACKED, "untracked, not ignored\n")


@pytest.fixture
def git_source(minimal_source: Path) -> Path:
    """A committed payload checkout with one ignored and one untracked file."""
    _layout(minimal_source)
    _git(minimal_source, "init", "-q", "-b", "main")
    _git(minimal_source, "add", "--all")
    _git(minimal_source, "commit", "-q", "--no-verify", "-m", "seed")
    _dirty(minimal_source)
    assert _git(minimal_source, "check-ignore", f".github/{IGNORED}") == f".github/{IGNORED}"
    return minimal_source


@pytest.fixture
def plain_source(minimal_source: Path) -> Path:
    """The same tree with no repository around it, as in the bundled wheel."""
    _layout(minimal_source)
    _dirty(minimal_source)
    return minimal_source


def _collect(root: Path) -> list[str]:
    gh = root / ".github"
    return deploy_core.collect_source_files(gh, deploy_core.parse_manifest(gh / ".af-manifest"))


# ── deploy_core (MCP af_apply / af_dry_run) ─────────────────────────────────


def test_collect_source_files_omits_a_git_ignored_file(git_source: Path) -> None:
    assert IGNORED not in _collect(git_source)


def test_collect_source_files_keeps_tracked_and_untracked_files(git_source: Path) -> None:
    files = _collect(git_source)
    for rel in (*TRACKED, UNTRACKED):
        assert rel in files, rel


def test_collect_source_files_outside_a_checkout_is_unchanged(plain_source: Path) -> None:
    files = _collect(plain_source)
    assert IGNORED in files
    assert UNTRACKED in files


# ── deploy.ps1 ──────────────────────────────────────────────────────────────


def _pwsh() -> str | None:
    for exe in ("pwsh", "powershell"):
        if shutil.which(exe):
            return exe
    return None


@pytest.mark.skipif(_pwsh() is None, reason="PowerShell not available")
def test_ps1_dry_run_omits_a_git_ignored_file(tmp_path: Path, git_source: Path) -> None:
    target = tmp_path / "proj"
    target.mkdir()
    res = subprocess.run(
        [
            _pwsh() or "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(git_source / "deploy.ps1"),
            "-TargetDir",
            str(target),
            "-DryRun",
        ],
        capture_output=True,
        text=True,
        timeout=300,
    )
    assert res.returncode == 0, res.stdout + res.stderr
    assert f".github/{IGNORED}" not in res.stdout, res.stdout
    for rel in (*TRACKED, UNTRACKED):
        assert f"CREATE  .github/{rel}" in res.stdout, rel


# ── wheel build (hatch_build.py) ────────────────────────────────────────────


@pytest.fixture
def hatch_build(monkeypatch: pytest.MonkeyPatch):
    # hatchling lives only in the isolated build env; the seam under test needs none of it.
    iface = types.ModuleType("hatchling.builders.hooks.plugin.interface")
    iface.BuildHookInterface = type("BuildHookInterface", (), {})
    for name in ("hatchling", "hatchling.builders", "hatchling.builders.hooks", "hatchling.builders.hooks.plugin"):
        monkeypatch.setitem(sys.modules, name, types.ModuleType(name))
    monkeypatch.setitem(sys.modules, iface.__name__, iface)
    spec = importlib.util.spec_from_file_location("_af_hatch_build_test", MCP_ROOT / "hatch_build.py")
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_wheel_payload_omits_a_git_ignored_file(git_source: Path, hatch_build) -> None:
    dests = set(hatch_build._payload_force_include(git_source).values())
    assert f"af_deploy_mcp/payload/.github/{IGNORED}" not in dests


def test_wheel_payload_keeps_tracked_and_untracked_files(git_source: Path, hatch_build) -> None:
    mapping = hatch_build._payload_force_include(git_source)
    dests = set(mapping.values())
    for rel in (*TRACKED, UNTRACKED, ".af-manifest"):
        assert f"af_deploy_mcp/payload/.github/{rel}" in dests, rel
    for src, dest in mapping.items():
        assert Path(src).is_file(), src
        assert dest.startswith("af_deploy_mcp/payload/"), dest
