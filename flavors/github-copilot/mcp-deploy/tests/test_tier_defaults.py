"""Tier model defaults have exactly one home: the framework's af-env.conf (#418).

The line-up used to live in three hardcoded copies (`deploy.ps1`, `deploy.sh`,
`deploy_core.py`), so every model change touched three scripts and two tests.
Now the framework's own `af-env.conf` carries `AF_MODEL_DEFAULT_*`, every deploy
path reads it from the SOURCE payload, and a project overrides a tier with
`AF_MODEL_TIER_*` in its own copy (blank = framework default).
"""

# copilot:generated | coordinator | 2026-10-20

from __future__ import annotations

import re
from pathlib import Path

import pytest

from af_deploy_mcp import deploy_core

FLAVOR = Path(__file__).resolve().parents[2]
SOURCE_ENV = FLAVOR / ".github" / "af-env.conf"
TIERS = ("PREMIUM", "BALANCED", "EFFICIENT")
PLANNER = "---\nname: planner\nmodel: __AF_TIER_BALANCED__\n---\n"

# The Claude 4.x line and older is no longer offered in Copilot (owner, 2026-10-20).
WITHDRAWN = re.compile(r"Claude (Opus|Sonnet|Haiku) [1-4](\.\d+)? ")


def _defaults() -> dict[str, list[str]]:
    out = {}
    for tier in TIERS:
        raw = deploy_core.get_af_env_value(SOURCE_ENV, f"AF_MODEL_DEFAULT_{tier}")
        out[tier] = [m.strip() for m in raw.split(",") if m.strip()]
    return out


def test_framework_config_carries_a_default_for_every_tier():
    assert all(_defaults()[t] for t in TIERS), _defaults()


def test_no_default_names_a_withdrawn_model():
    for tier, models in _defaults().items():
        stale = [m for m in models if WITHDRAWN.search(m + " ")]
        assert not stale, f"{tier}: {stale}"


@pytest.mark.parametrize("script", ["deploy.ps1", "deploy.sh", "mcp-deploy/af_deploy_mcp/deploy_core.py"])
def test_no_deploy_path_hardcodes_a_model(script):
    text = (FLAVOR / script).read_text(encoding="utf-8")
    assert "(copilot)" not in text
    assert "AF_MODEL_DEFAULT_" in text


def test_blank_project_tier_takes_the_framework_default(tmp_path):
    target = tmp_path / "af-env.conf"
    target.write_text("AF_MODEL_TIER_BALANCED=\n", encoding="utf-8")
    resolved = deploy_core.resolve_tier_tokens(PLANNER, target, SOURCE_ENV)
    assert resolved == "---\nname: planner\nmodel:\n" + "".join(f"  - {m}\n" for m in _defaults()["BALANCED"]) + "---\n"


def test_project_tier_overrides_the_default(tmp_path):
    target = tmp_path / "af-env.conf"
    target.write_text("AF_MODEL_TIER_BALANCED=Only One (copilot)\n", encoding="utf-8")
    assert "model: Only One (copilot)\n" in deploy_core.resolve_tier_tokens(PLANNER, target, SOURCE_ENV)


def test_no_list_anywhere_fails_loudly(tmp_path):
    with pytest.raises(ValueError, match="AF_MODEL_DEFAULT_BALANCED"):
        deploy_core.resolve_tier_tokens(PLANNER, tmp_path / "none.conf", tmp_path / "none.conf")
