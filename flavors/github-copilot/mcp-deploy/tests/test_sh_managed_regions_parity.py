"""Cross-tool parity for managed regions (measure #2b): deploy.sh == deploy_core.

Extracts the *real* awk region engines (``_AWK_STRIP`` / ``_AWK_MERGE``) from
``deploy.sh`` and runs them via ``awk``, asserting byte-identical strip/merge
output to ``deploy_core.strip_managed_regions`` / ``merge_managed_regions``.

Skipped when ``awk`` is absent (e.g. the Windows dev box where deploy.sh cannot
run); it executes in Linux CI. This is the gate that must be green before any
payload file ships a real ``AF:MANAGED`` region (measure 2b, Option A).
"""

from __future__ import annotations

import re
import shutil
import subprocess
from pathlib import Path

import pytest

from af_deploy_mcp import deploy_core

AF_ROOT = Path(__file__).resolve().parents[2]  # flavors/github-copilot
DEPLOY_SH = AF_ROOT / "deploy.sh"

REGION = "curated-skills"

pytestmark = pytest.mark.skipif(
    shutil.which("awk") is None or not DEPLOY_SH.is_file(),
    reason="awk or deploy.sh not available",
)


def _extract_awk(name: str) -> str:
    """Pull a single-quoted ``NAME='...'`` awk program out of deploy.sh verbatim."""
    text = DEPLOY_SH.read_text(encoding="utf-8")
    m = re.search(rf"{name}='(.*?)'", text, re.DOTALL)
    assert m is not None, f"{name} not found in deploy.sh"
    return m.group(1)


def _endnl(text: str) -> str:
    # Mirrors deploy.sh _ends_with_nl: nonempty and last byte is LF.
    return "1" if text and text.endswith("\n") else "0"


def _run_strip(text: str) -> bytes:
    prog = _extract_awk("_AWK_STRIP")
    res = subprocess.run(
        ["awk", "-v", f"endnl={_endnl(text)}", prog],
        input=text.encode("utf-8"),
        capture_output=True,
        timeout=60,
    )
    assert res.returncode == 0, res.stderr.decode()
    return res.stdout


def _run_merge(base: str, overlay: str, tmp_path: Path) -> bytes:
    prog = _extract_awk("_AWK_MERGE")
    overlay_file = tmp_path / "overlay.txt"
    base_file = tmp_path / "base.txt"
    overlay_file.write_bytes(overlay.encode("utf-8"))
    base_file.write_bytes(base.encode("utf-8"))
    # Overlay is the FNR==NR pass (first arg); base is reconstructed (second).
    res = subprocess.run(
        ["awk", "-v", f"endnl={_endnl(base)}", prog, str(overlay_file), str(base_file)],
        capture_output=True,
        timeout=60,
    )
    assert res.returncode == 0, res.stderr.decode()
    return res.stdout


def _agent(region_body: str, base: str = "base-a") -> str:
    return (
        "## Skills\n"
        f"- **{base}** (`skills/{base}/SKILL.md`) \u2014 base\n"
        f"<!-- AF:MANAGED:{REGION}:START -->\n"
        f"{region_body}"
        f"<!-- AF:MANAGED:{REGION}:END -->\n\n"
        "## Next\n"
    )


def test_sh_strip_matches_core() -> None:
    text = _agent("- **cur-x** (`skills/cur-x/SKILL.md`) \u2014 x\n")
    assert _run_strip(text) == deploy_core.strip_managed_regions(text).encode("utf-8")


def test_sh_strip_noop_matches_core() -> None:
    text = "## Skills\n- **base-a** (`skills/base-a/SKILL.md`) \u2014 base\n"
    assert _run_strip(text) == deploy_core.strip_managed_regions(text).encode("utf-8")


def test_sh_strip_empty_region_matches_core() -> None:
    text = _agent("")  # START immediately followed by END
    assert _run_strip(text) == deploy_core.strip_managed_regions(text).encode("utf-8")


def test_sh_strip_no_trailing_newline_matches_core() -> None:
    text = _agent("- **cur-x** (`skills/cur-x/SKILL.md`) \u2014 x\n").rstrip("\n")
    assert _run_strip(text) == deploy_core.strip_managed_regions(text).encode("utf-8")


def test_sh_strip_multiline_body_matches_core() -> None:
    body = "- **a** (`skills/a/SKILL.md`) \u2014 a\n- **b** (`skills/b/SKILL.md`) \u2014 b\n\n"
    text = _agent(body)
    assert _run_strip(text) == deploy_core.strip_managed_regions(text).encode("utf-8")


def test_sh_strip_unterminated_region_kept_verbatim() -> None:
    # No matching END -> Python regex does not match -> body preserved.
    text = (
        "## Skills\n"
        f"<!-- AF:MANAGED:{REGION}:START -->\n"
        "- **cur-x** (`skills/cur-x/SKILL.md`) \u2014 x\n"
        "## Next (no END marker)\n"
    )
    assert _run_strip(text) == deploy_core.strip_managed_regions(text).encode("utf-8")


def test_sh_merge_transplants_matches_core(tmp_path: Path) -> None:
    base = _agent("", base="base-NEW")  # framework: emptied region, updated base
    overlay = _agent("- **cur-x** (`skills/cur-x/SKILL.md`) \u2014 x\n", base="base-OLD")
    assert _run_merge(base, overlay, tmp_path) == deploy_core.merge_managed_regions(base, overlay).encode("utf-8")


def test_sh_merge_noop_without_overlay_region(tmp_path: Path) -> None:
    base = _agent("- **framework** (`skills/framework/SKILL.md`) \u2014 fw\n")
    overlay = "## Skills\n- **base-a** (`skills/base-a/SKILL.md`) \u2014 base\n"  # no region
    assert _run_merge(base, overlay, tmp_path) == deploy_core.merge_managed_regions(base, overlay).encode("utf-8")


def test_sh_merge_no_trailing_newline_matches_core(tmp_path: Path) -> None:
    base = _agent("", base="base-NEW").rstrip("\n")
    overlay = _agent("- **cur-x** (`skills/cur-x/SKILL.md`) \u2014 x\n", base="base-OLD")
    assert _run_merge(base, overlay, tmp_path) == deploy_core.merge_managed_regions(base, overlay).encode("utf-8")


# NB: no CRLF parity test here (unlike the PowerShell suite). The bash region
# engine only ever runs on canonical LF bytes -- ``canonical_write`` strips CR and
# BOM before any strip/merge awk is invoked -- so a CRLF input is not a reachable
# deploy.sh state. (Git-for-Windows gawk additionally text-translates stdin, which
# would make such a direct test host-dependent rather than logic-revealing.)
