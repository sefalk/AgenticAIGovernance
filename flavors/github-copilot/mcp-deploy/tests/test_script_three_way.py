"""deploy.ps1 merges a both-sides change like deploy_core does (#393, follow-up to #105).

The MCP deploy reports ``MERGE`` for a non-customizable file both sides changed
without overlap; the scripts used to report ``CONFLICT`` and withhold it. They
also never wrote ``.github/.af-baseline/``, so a script deploy left the store
stale for the next MCP deploy and never pruned it.

Each case runs the same diverged target through ``deploy_core.apply`` and
``deploy.ps1`` and compares verdicts and written bytes. The bash leg lives in
``test-deploy-available-sync.sh`` (full deploy.sh runs exceed 5 minutes on
Windows, #260).
"""

# copilot:generated | coordinator | 2026-10-19

from __future__ import annotations

import hashlib
import shutil
import subprocess
from pathlib import Path

import pytest

from af_deploy_mcp import deploy_core

AF_ROOT = Path(__file__).resolve().parents[2]  # flavors/github-copilot
PLAIN = "MANIFEST.md"
CUSTOM = "copilot-instructions.md"
LINES = [f"line {i}" for i in range(1, 13)]


def _powershell() -> str | None:
    return shutil.which("pwsh") or shutil.which("powershell")


pytestmark = pytest.mark.skipif(_powershell() is None, reason="PowerShell not available")


def _text(lines: list[str]) -> str:
    return "\n".join(lines) + "\n"


def _edit(index: int, value: str, lines: list[str] = LINES) -> str:
    out = list(lines)
    out[index] = value
    return _text(out)


def _write(p: Path, text: str, newline: str = "") -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8", newline=newline)


def _source(root: Path) -> Path:
    _write(root / "VERSION", "1.0.0\n")
    _write(root / ".github" / ".af-manifest", (AF_ROOT / ".github" / ".af-manifest").read_text(encoding="utf-8"))
    _write(root / ".github" / PLAIN, _text(LINES))
    _write(root / ".github" / CUSTOM, _text([*LINES, "custom"]))
    shutil.copy2(AF_ROOT / "deploy.ps1", root / "deploy.ps1")
    return root


def _ps1(src: Path, target: Path) -> str:
    res = subprocess.run(
        [_powershell(), "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(src / "deploy.ps1")]
        + ["-TargetDir", str(target)],
        capture_output=True,
        text=True,
        timeout=300,
        stdin=subprocess.DEVNULL,
    )
    return res.stdout + res.stderr


def _deployed(tmp_path: Path) -> tuple[Path, Path]:
    """A target first deployed by deploy.ps1 itself."""
    src = _source(tmp_path / "src")
    target = tmp_path / "proj"
    target.mkdir()
    subprocess.run(["git", "init", "-q", str(target)], check=True)
    _ps1(src, target)
    return src, target


def _store(target: Path) -> Path:
    return target / ".github" / ".af-baseline"


def _verdict(output: str, rel: str) -> str | None:
    for line in output.splitlines():
        words = line.split()
        if len(words) >= 2 and words[1] == f".github/{rel}":
            return words[0]
    return None


def _core_bytes(target: Path, src: Path, tmp_path: Path, rel: str) -> bytes:
    twin = tmp_path / "core-twin"
    shutil.copytree(target, twin)
    deploy_core.apply(src, twin)
    return (twin / ".github" / rel).read_bytes()


# ── The store ───────────────────────────────────────────────────────────────


def test_a_ps1_deploy_stores_the_content_behind_every_recorded_hash(tmp_path: Path) -> None:
    _, target = _deployed(tmp_path)
    recorded = deploy_core.read_baseline_hashes(target / ".github")
    assert PLAIN in recorded
    for key in (PLAIN, CUSTOM):
        obj = _store(target) / recorded[key]
        assert obj.is_file(), f"no stored baseline for {key}"
        assert hashlib.sha256(obj.read_bytes()).hexdigest().upper() == recorded[key]
    assert (_store(target) / ".gitignore").read_text(encoding="utf-8").strip() == "*"


def test_a_ps1_deploy_prunes_objects_no_hash_references(tmp_path: Path) -> None:
    src, target = _deployed(tmp_path)
    old = deploy_core.read_baseline_hashes(target / ".github")[PLAIN]
    assert (_store(target) / old).is_file()
    _write(src / ".github" / PLAIN, _edit(0, "line AF"))
    _ps1(src, target)
    assert not (_store(target) / old).exists()


# ── The merge ───────────────────────────────────────────────────────────────


def test_a_non_overlapping_change_merges_to_the_same_bytes_as_deploy_core(tmp_path: Path) -> None:
    src, target = _deployed(tmp_path)
    _write(src / ".github" / PLAIN, _edit(1, "line AF"))
    _write(target / ".github" / PLAIN, _edit(9, "line PROJECT"))
    expected = _core_bytes(target, src, tmp_path, PLAIN)

    output = _ps1(src, target)

    assert _verdict(output, PLAIN) == "MERGE", output
    written = (target / ".github" / PLAIN).read_bytes()
    assert written == expected
    assert b"line AF" in written
    assert b"line PROJECT" in written


def test_a_crlf_project_file_still_merges(tmp_path: Path) -> None:
    src, target = _deployed(tmp_path)
    _write(src / ".github" / PLAIN, _edit(1, "line AF"))
    _write(target / ".github" / PLAIN, _edit(9, "line PROJECT"), newline="\r\n")
    expected = _core_bytes(target, src, tmp_path, PLAIN)

    output = _ps1(src, target)

    assert _verdict(output, PLAIN) == "MERGE", output
    assert (target / ".github" / PLAIN).read_bytes() == expected


def test_overlapping_changes_stay_conflict(tmp_path: Path) -> None:
    src, target = _deployed(tmp_path)
    _write(src / ".github" / PLAIN, _edit(1, "line AF"))
    project = _edit(1, "line PROJECT")
    _write(target / ".github" / PLAIN, project)

    output = _ps1(src, target)

    assert _verdict(output, PLAIN) == "CONFLICT", output
    assert (target / ".github" / PLAIN).read_text(encoding="utf-8") == project


def test_a_missing_store_object_stays_conflict(tmp_path: Path) -> None:
    src, target = _deployed(tmp_path)
    shutil.rmtree(_store(target))
    _write(src / ".github" / PLAIN, _edit(1, "line AF"))
    _write(target / ".github" / PLAIN, _edit(9, "line PROJECT"))
    assert _verdict(_ps1(src, target), PLAIN) == "CONFLICT"


def test_a_tampered_store_object_stays_conflict(tmp_path: Path) -> None:
    src, target = _deployed(tmp_path)
    digest = deploy_core.read_baseline_hashes(target / ".github")[PLAIN]
    (_store(target) / digest).write_text("tampered\n", encoding="utf-8")
    _write(src / ".github" / PLAIN, _edit(1, "line AF"))
    _write(target / ".github" / PLAIN, _edit(9, "line PROJECT"))
    assert _verdict(_ps1(src, target), PLAIN) == "CONFLICT"


def test_a_customizable_file_is_never_merged(tmp_path: Path) -> None:
    src, target = _deployed(tmp_path)
    custom_lines = [*LINES, "custom"]
    _write(src / ".github" / CUSTOM, _edit(1, "line AF", custom_lines))
    project = _edit(9, "line PROJECT", custom_lines)
    _write(target / ".github" / CUSTOM, project)

    output = _ps1(src, target)

    assert _verdict(output, CUSTOM) == "CONFLICT", output
    assert (target / ".github" / CUSTOM).read_text(encoding="utf-8") == project
