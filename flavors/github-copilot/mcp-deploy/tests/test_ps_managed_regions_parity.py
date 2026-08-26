"""Cross-tool parity for managed regions (measure #2b): deploy.ps1 == deploy_core.

Loads the *real* PowerShell region helpers from ``deploy.ps1`` via the PS AST
(no duplication of the logic under test) and asserts they produce byte-identical
strip/merge output to ``deploy_core.strip_managed_regions`` /
``merge_managed_regions``. Skipped when PowerShell or deploy.ps1 is absent
(e.g. Linux CI), where the Python-level region tests still hold.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

from af_deploy_mcp import deploy_core

AF_ROOT = Path(__file__).resolve().parents[2]  # flavors/github-copilot
DEPLOY_PS1 = AF_ROOT / "deploy.ps1"

REGION = "curated-skills"


def _pwsh() -> str | None:
    for exe in ("pwsh", "powershell"):
        if shutil.which(exe):
            return exe
    return None


pytestmark = pytest.mark.skipif(
    _pwsh() is None or not DEPLOY_PS1.is_file(),
    reason="PowerShell or deploy.ps1 not available",
)

# Harness: load ONLY the region helpers + the $script:ManagedRegionRegex
# assignment from deploy.ps1 (via AST), then run strip or merge and write the
# result as UTF-8 (no BOM). This exercises the real shipped PS code.
_HARNESS = r"""
param(
    [Parameter(Mandatory)][string]$Mode,
    [Parameter(Mandatory)][string]$DeployPs1,
    [Parameter(Mandatory)][string]$BaseFile,
    [string]$OverlayFile,
    [Parameter(Mandatory)][string]$OutFile
)
$ast = [System.Management.Automation.Language.Parser]::ParseFile($DeployPs1, [ref]$null, [ref]$null)
$names = 'Strip-ManagedRegions', 'Get-ManagedRegionBodies', 'Merge-ManagedRegions'
foreach ($f in $ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $names -contains $n.Name
        }, $true)) { Invoke-Expression $f.Extent.Text }
$assign = $ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $n.Left.Extent.Text -eq '$script:ManagedRegionRegex'
    }, $true)
Invoke-Expression $assign[0].Extent.Text

$utf8 = New-Object System.Text.UTF8Encoding($false)
$base = [System.IO.File]::ReadAllText($BaseFile, $utf8)
if ($Mode -eq 'strip') {
    $result = Strip-ManagedRegions $base
} else {
    $overlay = [System.IO.File]::ReadAllText($OverlayFile, $utf8)
    $result = Merge-ManagedRegions $base $overlay
}
[System.IO.File]::WriteAllBytes($OutFile, $utf8.GetBytes($result))
"""


def _agent(region_body: str, base: str = "base-a") -> str:
    return (
        "## Skills\n"
        f"- **{base}** (`skills/{base}/SKILL.md`) \u2014 base\n"
        f"<!-- AF:MANAGED:{REGION}:START -->\n"
        f"{region_body}"
        f"<!-- AF:MANAGED:{REGION}:END -->\n\n"
        "## Next\n"
    )


def _run_ps_region(tmp_path: Path, mode: str, base: str, overlay: str | None = None) -> bytes:
    exe = _pwsh()
    assert exe is not None
    harness = tmp_path / "harness.ps1"
    harness.write_text(_HARNESS, encoding="utf-8")
    base_file = tmp_path / "base.txt"
    base_file.write_bytes(base.encode("utf-8"))
    out_file = tmp_path / "out.bin"
    args = [
        exe,
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(harness),
        "-Mode",
        mode,
        "-DeployPs1",
        str(DEPLOY_PS1),
        "-BaseFile",
        str(base_file),
        "-OutFile",
        str(out_file),
    ]
    if overlay is not None:
        overlay_file = tmp_path / "overlay.txt"
        overlay_file.write_bytes(overlay.encode("utf-8"))
        args += ["-OverlayFile", str(overlay_file)]
    res = subprocess.run(args, capture_output=True, text=True, timeout=120)
    assert res.returncode == 0, res.stdout + res.stderr
    return out_file.read_bytes()


def test_ps_strip_matches_core(tmp_path: Path) -> None:
    text = _agent("- **cur-x** (`skills/cur-x/SKILL.md`) \u2014 x\n")
    ps_bytes = _run_ps_region(tmp_path, "strip", text)
    assert ps_bytes == deploy_core.strip_managed_regions(text).encode("utf-8")


def test_ps_strip_noop_matches_core(tmp_path: Path) -> None:
    text = "## Skills\n- **base-a** (`skills/base-a/SKILL.md`) \u2014 base\n"
    ps_bytes = _run_ps_region(tmp_path, "strip", text)
    assert ps_bytes == deploy_core.strip_managed_regions(text).encode("utf-8")


def test_ps_merge_matches_core(tmp_path: Path) -> None:
    base = _agent("", base="base-NEW")  # framework: empty region, updated base
    overlay = _agent("- **cur-x** (`skills/cur-x/SKILL.md`) \u2014 x\n", base="base-OLD")
    ps_bytes = _run_ps_region(tmp_path, "merge", base, overlay)
    assert ps_bytes == deploy_core.merge_managed_regions(base, overlay).encode("utf-8")


def test_ps_strip_crlf_matches_core(tmp_path: Path) -> None:
    # CRLF host: the \n-anchored region regex must behave identically on both
    # sides (the \r rides inside the marker lines).
    text = _agent("- **cur-x** (`skills/cur-x/SKILL.md`) \u2014 x\n").replace("\n", "\r\n")
    ps_bytes = _run_ps_region(tmp_path, "strip", text)
    assert ps_bytes == deploy_core.strip_managed_regions(text).encode("utf-8")
