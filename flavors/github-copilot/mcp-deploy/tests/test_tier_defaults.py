"""The curated tier model defaults agree across all three deploy paths (#418).

`deploy.ps1`, `deploy.sh` and `deploy_core.py` each carry a copy of the
defaults that fill an agent's `__AF_TIER_*__` placeholder. A model line-up
change touches all three, and nothing compared them.
"""

# copilot:generated | coordinator | 2026-10-20

from __future__ import annotations

import re
from pathlib import Path

from af_deploy_mcp import deploy_core

FLAVOR = Path(__file__).resolve().parents[2]
TIERS = ("PREMIUM", "BALANCED", "EFFICIENT")

# Withdrawn from the Copilot model picker; a default list naming one only
# costs a fallback, but one naming nothing else leaves the agent without a model.
WITHDRAWN = ("Claude Opus 4.8", "Claude Opus 4.7", "Claude Haiku 4.5", "Claude Sonnet 5 ")


def _ps1() -> dict[str, str]:
    text = (FLAVOR / "deploy.ps1").read_text(encoding="utf-8")
    return dict(re.findall(r"^\s*(PREMIUM|BALANCED|EFFICIENT)\s*=\s*'([^']*)'", text, re.M))


def _sh() -> dict[str, str]:
    text = (FLAVOR / "deploy.sh").read_text(encoding="utf-8")
    return dict(re.findall(r"^\s*\[(PREMIUM|BALANCED|EFFICIENT)\]='([^']*)'", text, re.M))


def test_three_copies_are_identical():
    core = {t: deploy_core.TIER_DEFAULTS[t] for t in TIERS}
    assert _ps1() == core
    assert _sh() == core


def test_no_default_names_a_withdrawn_model():
    for tier, models in deploy_core.TIER_DEFAULTS.items():
        for gone in WITHDRAWN:
            assert gone not in models + " ", f"{tier} still names {gone.strip()}"


def test_current_line_up_leads_each_tier():
    first = {t: deploy_core.TIER_DEFAULTS[t].split(",")[0].strip() for t in TIERS}
    assert first == {
        "PREMIUM": "Claude Opus 5.5 (copilot)",
        "BALANCED": "Claude Sonnet 5.5 (copilot)",
        "EFFICIENT": "Claude Haiku 5.5 (copilot)",
    }
