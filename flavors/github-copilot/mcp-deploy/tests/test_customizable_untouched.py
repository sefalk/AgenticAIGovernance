"""A customizable file the project never changed takes the framework update (#106).

``PROTECT`` used to fire whenever AF changed a ``[customizable]`` file, without
asking whether the project had changed it. In a measured upgrade both PROTECT
files were byte-identical to their baseline: review work with nothing to review,
and a fix withheld from every project that never touched the file.

A customizable file whose hash still equals its baseline is now ``UPDATE``. The
cases with no evidence that the project left it alone stay ``PROTECT``.
"""

from __future__ import annotations

import hashlib
import shutil
import subprocess
from pathlib import Path

import pytest

from af_deploy_mcp import deploy_core

AF_ROOT = Path(__file__).resolve().parents[2]  # flavors/github-copilot
REL = "instructions/architecture.instructions.md"
OLD = "# architecture, as deployed\n"
NEW = "# architecture, framework fix\n"


def _write(p: Path, text: str) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8", newline="")


def _hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest().upper()


def _source(root: Path, manifest: str, content: str = NEW) -> Path:
    _write(root / "VERSION", "1.0.0\n")
    _write(root / ".github" / ".af-manifest", manifest)
    _write(root / ".github" / REL, content)
    return root


def _target(root: Path, content: str, baseline: dict[str, str]) -> Path:
    _write(root / ".github" / REL, content)
    lines = ["# AF deployment baseline hashes", *(f"{k}={v}" for k, v in baseline.items())]
    _write(root / ".github" / ".af-hashes", "\n".join(lines) + "\n")
    return root


CORE_MANIFEST = f"# manifest\ninstructions/\n{REL}   [customizable]\n"


def _classes(src: Path, target: Path) -> dict[str, str]:
    return {f["path"]: f["classification"] for f in deploy_core.dry_run(src, target)["files"]}


# ── deploy_core ─────────────────────────────────────────────────────────────


def test_an_untouched_customizable_file_is_updated(tmp_path: Path) -> None:
    src = _source(tmp_path / "src", CORE_MANIFEST)
    target = _target(tmp_path / "proj", OLD, {REL: _hash(OLD)})
    assert _classes(src, target)[f".github/{REL}"] == "UPDATE"


def test_apply_writes_the_update_and_backs_up(tmp_path: Path) -> None:
    src = _source(tmp_path / "src", CORE_MANIFEST)
    target = _target(tmp_path / "proj", OLD, {REL: _hash(OLD)})

    report = deploy_core.apply(src, target)

    assert f".github/{REL}" in report["applied"]
    assert (target / ".github" / REL).read_text(encoding="utf-8") == NEW
    assert (Path(report["backup_dir"]) / ".github" / REL).read_text(encoding="utf-8") == OLD


def test_a_customizable_file_new_to_the_baseline_stays_protected(tmp_path: Path) -> None:
    # No baseline entry: nothing shows the project left the file alone.
    src = _source(tmp_path / "src", CORE_MANIFEST)
    target = _target(tmp_path / "proj", OLD, {"other.md": _hash("x")})
    assert _classes(src, target)[f".github/{REL}"] == "PROTECT"


def test_a_customized_file_is_still_preserved(tmp_path: Path) -> None:
    src = _source(tmp_path / "src", CORE_MANIFEST, content=OLD)
    target = _target(tmp_path / "proj", "# architecture, ours\n", {REL: _hash(OLD)})
    assert _classes(src, target)[f".github/{REL}"] == "PRESERVE"


# ── deploy.ps1 ──────────────────────────────────────────────────────────────


def _powershell() -> str | None:
    return shutil.which("pwsh") or shutil.which("powershell")


@pytest.mark.skipif(_powershell() is None, reason="PowerShell not available")
@pytest.mark.parametrize(
    ("project_content", "verdict", "written"),
    [
        (OLD, "UPDATE", NEW),
        ("# architecture, ours\n", "CONFLICT", "# architecture, ours\n"),
    ],
    ids=["untouched-is-updated", "customized-stays-conflict"],
)
def test_deploy_ps1_agrees(tmp_path: Path, project_content: str, verdict: str, written: str) -> None:
    # A minimal source keeps the run short; the manifest is the real one.
    src = tmp_path / "src"
    _source(src, (AF_ROOT / ".github" / ".af-manifest").read_text(encoding="utf-8"))
    shutil.copy2(AF_ROOT / "deploy.ps1", src / "deploy.ps1")
    target = _target(tmp_path / "proj", project_content, {REL: _hash(OLD)})
    subprocess.run(["git", "init", "-q", str(target)], check=True)

    res = subprocess.run(
        [
            _powershell(),
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(src / "deploy.ps1"),
            "-TargetDir",
            str(target),
        ],
        capture_output=True,
        text=True,
        timeout=300,
        stdin=subprocess.DEVNULL,
    )

    assert any(line.strip().startswith(verdict) and REL in line for line in res.stdout.splitlines()), (
        res.stdout + res.stderr
    )
    assert (target / ".github" / REL).read_text(encoding="utf-8") == written
