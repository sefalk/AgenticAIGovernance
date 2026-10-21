"""Shared fixtures for the deploy-engine suite."""

# copilot:generated | coordinator | 2026-10-21

from __future__ import annotations

import shutil
from pathlib import Path

import pytest

AF_ROOT = Path(__file__).resolve().parents[1].parent  # flavors/github-copilot

# Everything a deploy reads before its advisory checks run. A deploy of the real
# payload copies ~300 files and took ~30 s per case under PowerShell, which put
# the suite over its budget (#60 follow-up, 2026-10-21).
_MINIMAL = (
    "VERSION",
    "deploy.ps1",
    ".github/.af-manifest",
    ".github/af-env.conf",
    ".github/scripts/check-model-tiers.py",
    ".github/scripts/analyze-copilot-usage.py",
)


@pytest.fixture
def minimal_source(tmp_path: Path) -> Path:
    """A payload root holding only what the deploy's post-write checks read."""
    root = tmp_path / "src"
    for rel in _MINIMAL:
        dest = root / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(AF_ROOT / rel, dest)
    return root
