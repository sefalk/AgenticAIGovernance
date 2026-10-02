"""Cross-tool EOL/BOM parity: deploy.ps1 and the MCP deploy must agree.

Runs the real ``deploy.ps1`` against a throwaway target and asserts the MCP
``dry_run`` sees no pending writes (and vice versa). This is the end-to-end guard
for the invariant that both deploy paths emit byte-identical files regardless of
the working tree's line endings. Skipped when PowerShell or deploy.ps1 is absent
(e.g. Linux CI), where the unit-level parity tests still hold.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest
from _probe import usable

from af_deploy_mcp import deploy_core

AF_ROOT = Path(__file__).resolve().parents[2]  # flavors/github-copilot
DEPLOY_PS1 = AF_ROOT / "deploy.ps1"
DEPLOY_SH = AF_ROOT / "deploy.sh"


def _pwsh() -> str | None:
    for exe in ("pwsh", "powershell"):
        if shutil.which(exe):
            return exe
    return None


pytestmark = pytest.mark.skipif(
    _pwsh() is None or not DEPLOY_PS1.is_file(),
    reason="PowerShell or deploy.ps1 not available",
)


def _run_ps1(target: Path, *extra: str) -> subprocess.CompletedProcess:
    exe = _pwsh()
    assert exe is not None
    return subprocess.run(
        [exe, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(DEPLOY_PS1), "-TargetDir", str(target), *extra],
        capture_output=True,
        text=True,
        timeout=300,
    )


def test_ps1_deploy_then_mcp_dryrun_is_clean(tmp_path: Path) -> None:
    target = tmp_path / "proj"
    target.mkdir()
    res = _run_ps1(target, "-Force")
    assert res.returncode == 0, res.stdout + res.stderr

    report = deploy_core.dry_run(AF_ROOT, target)
    counts = report["counts"]
    # Parity: after a ps1 deploy, the MCP must see zero pending writes.
    assert counts.get("UPDATE", 0) == 0, report["files"]
    assert counts.get("CONFLICT", 0) == 0, report["files"]
    assert counts.get("CREATE", 0) == 0, report["files"]


def test_mcp_apply_then_ps1_dryrun_is_clean(tmp_path: Path) -> None:
    target = tmp_path / "proj"
    target.mkdir()
    deploy_core.apply(AF_ROOT, target)
    deploy_core.update_hashes(AF_ROOT, target)

    res = _run_ps1(target, "-DryRun")
    assert res.returncode == 0, res.stdout + res.stderr
    # Parity: after an MCP apply, deploy.ps1 must plan no UPDATE/CONFLICT writes.
    assert "UPDATE  " not in res.stdout, res.stdout
    assert "CONFLICT " not in res.stdout, res.stdout


@pytest.mark.skipif(
    not usable("bash") or not DEPLOY_SH.is_file(),
    reason="bash or deploy.sh not available",
)
def test_sh_deploy_then_mcp_dryrun_is_clean(tmp_path: Path) -> None:
    # Guards the hash-casing fix: deploy.sh writes uppercase .af-hashes so the
    # case-sensitive MCP 3-way classifier reads a bash baseline without spurious
    # CONFLICTs. Skipped on Windows -- not because bash is missing (Git ships it,
    # just off PATH) but because deploy.sh under MSYS exceeds the 300s below
    # (measured 2026-09-02). Putting bash on PATH turns this into a slow failure.
    # On a hosted runner the name resolves to the WSL launcher instead, which is
    # why availability is probed rather than looked up; see _probe.usable.
    target = tmp_path / "proj"
    target.mkdir()
    res = subprocess.run(
        ["bash", str(DEPLOY_SH), "--target", str(target), "--force"],
        capture_output=True,
        text=True,
        timeout=300,
    )
    assert res.returncode == 0, res.stdout + res.stderr
    report = deploy_core.dry_run(AF_ROOT, target)
    counts = report["counts"]
    assert counts.get("UPDATE", 0) == 0, report["files"]
    assert counts.get("CONFLICT", 0) == 0, report["files"]
    assert counts.get("CREATE", 0) == 0, report["files"]
