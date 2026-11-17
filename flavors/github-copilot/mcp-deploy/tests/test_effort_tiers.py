"""Reasoning effort per model tier (#557).

Under the Copilot harness a subagent without ``reasoning-effort:`` inherits the
parent's effort (measured in #447). The deploy therefore emits
``reasoning-effort:`` next to every resolved tier ``model:``: the project's
``AF_EFFORT_TIER_*`` override, else the framework's ``AF_EFFORT_DEFAULT_*``.
Blank everywhere means no line (inherit); an agent's own key always wins.
"""

# copilot:generated | coordinator | 2026-11-11

from __future__ import annotations

from pathlib import Path

import pytest

from af_deploy_mcp import deploy_core

FLAVOR = Path(__file__).resolve().parents[2]
SOURCE_ENV = FLAVOR / ".github" / "af-env.conf"
PLANNER = "---\nname: planner\nmodel: __AF_TIER_BALANCED__\n---\n\n# Planner\n"


def _source(tmp_path: Path, effort_line: str = "") -> Path:
    src = tmp_path / "source.conf"
    src.write_text("AF_MODEL_DEFAULT_BALANCED=Only One (copilot)\n" + effort_line, encoding="utf-8")
    return src


def _target(tmp_path: Path, text: str = "") -> Path:
    tgt = tmp_path / "target.conf"
    tgt.write_text(text, encoding="utf-8")
    return tgt


@pytest.mark.parametrize(("tier", "effort"), [("PREMIUM", "high"), ("BALANCED", "medium"), ("EFFICIENT", "low")])
def test_framework_ships_the_owner_defaults(tier: str, effort: str) -> None:
    assert deploy_core.get_af_env_value(SOURCE_ENV, f"AF_EFFORT_DEFAULT_{tier}") == effort


def test_default_effort_follows_the_model_line(tmp_path: Path) -> None:
    src = _source(tmp_path, "AF_EFFORT_DEFAULT_BALANCED=medium\n")
    out = deploy_core.resolve_tier_tokens(PLANNER, _target(tmp_path), src)
    assert out == "---\nname: planner\nmodel: Only One (copilot)\nreasoning-effort: medium\n---\n\n# Planner\n"


def test_effort_follows_a_multi_model_array(tmp_path: Path) -> None:
    src = tmp_path / "source.conf"
    src.write_text(
        "AF_MODEL_DEFAULT_BALANCED=A (copilot), B (copilot)\nAF_EFFORT_DEFAULT_BALANCED=medium\n", encoding="utf-8"
    )
    out = deploy_core.resolve_tier_tokens(PLANNER, _target(tmp_path), src)
    assert "model:\n  - A (copilot)\n  - B (copilot)\nreasoning-effort: medium\n---\n" in out


def test_project_override_wins_over_the_default(tmp_path: Path) -> None:
    src = _source(tmp_path, "AF_EFFORT_DEFAULT_BALANCED=medium\n")
    out = deploy_core.resolve_tier_tokens(PLANNER, _target(tmp_path, "AF_EFFORT_TIER_BALANCED=xhigh\n"), src)
    assert "reasoning-effort: xhigh\n" in out
    assert "reasoning-effort: medium" not in out


def test_blank_everywhere_emits_no_line_so_the_agent_inherits(tmp_path: Path) -> None:
    src = _source(tmp_path, "AF_EFFORT_DEFAULT_BALANCED=\n")
    out = deploy_core.resolve_tier_tokens(PLANNER, _target(tmp_path, "AF_EFFORT_TIER_BALANCED=\n"), src)
    assert "reasoning-effort" not in out


def test_project_inherit_suppresses_the_default(tmp_path: Path) -> None:
    src = _source(tmp_path, "AF_EFFORT_DEFAULT_BALANCED=medium\n")
    out = deploy_core.resolve_tier_tokens(PLANNER, _target(tmp_path, "AF_EFFORT_TIER_BALANCED=inherit\n"), src)
    assert "reasoning-effort" not in out


def test_an_agents_own_effort_is_kept(tmp_path: Path) -> None:
    src = _source(tmp_path, "AF_EFFORT_DEFAULT_BALANCED=medium\n")
    agent = "---\nname: planner\nmodel: __AF_TIER_BALANCED__\nreasoning-effort: low\n---\n"
    out = deploy_core.resolve_tier_tokens(agent, _target(tmp_path), src)
    assert out.count("reasoning-effort:") == 1
    assert "reasoning-effort: low\n" in out


def test_crlf_files_keep_their_line_ending(tmp_path: Path) -> None:
    src = _source(tmp_path, "AF_EFFORT_DEFAULT_BALANCED=medium\n")
    out = deploy_core.resolve_tier_tokens(PLANNER.replace("\n", "\r\n"), _target(tmp_path), src)
    assert "model: Only One (copilot)\r\nreasoning-effort: medium\r\n" in out


def test_an_unknown_effort_fails_the_deploy(tmp_path: Path) -> None:
    src = _source(tmp_path, "AF_EFFORT_DEFAULT_BALANCED=turbo\n")
    with pytest.raises(ValueError, match="AF_EFFORT_DEFAULT_BALANCED"):
        deploy_core.resolve_tier_tokens(PLANNER, _target(tmp_path), src)
