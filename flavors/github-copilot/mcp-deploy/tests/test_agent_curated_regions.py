"""Curated-skills managed region in shipped agents (measure #2c-i).

Guards the payload shape that makes curated-skill lines CONFLICT-free: every
framework agent with a ``## Skills`` section ships exactly one *empty*
``AF:MANAGED:curated-skills`` region, and filling that region is classification-
invariant (``deploy_core`` strips it back to the empty-region source). Agents
without a ``## Skills`` section (coordinator, compliance-checker) carry no region.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from af_deploy_mcp import deploy_core

AF_ROOT = Path(__file__).resolve().parents[2]  # flavors/github-copilot
AGENTS_DIR = AF_ROOT / ".github" / "agents"

REGION = "curated-skills"
START = f"<!-- AF:MANAGED:{REGION}:START -->"
END = f"<!-- AF:MANAGED:{REGION}:END -->"

# Agents without a ## Skills section must NOT carry the region.
NO_SKILLS_AGENTS = {"coordinator", "compliance-checker"}


def _agent_files() -> list[Path]:
    return sorted(AGENTS_DIR.glob("*.agent.md"))


def test_agents_dir_present() -> None:
    assert AGENTS_DIR.is_dir(), AGENTS_DIR
    assert _agent_files(), "no agent files found"


def test_expected_agents_carry_exactly_one_empty_region() -> None:
    agents = _agent_files()
    with_region = 0
    for path in agents:
        text = path.read_text(encoding="utf-8")
        has_skills = "\n## Skills" in text or text.startswith("## Skills")
        stem = path.stem.replace(".agent", "")
        if stem in NO_SKILLS_AGENTS:
            assert START not in text, f"{path.name} should not carry the region"
            continue
        assert has_skills, f"{path.name}: no '## Skills' section and not listed in NO_SKILLS_AGENTS"
        assert text.count(START) == 1, f"{path.name}: expected exactly one START"
        assert text.count(END) == 1, f"{path.name}: expected exactly one END"
        # Empty body: END immediately follows the START line.
        assert f"{START}\n{END}" in text, f"{path.name}: region body is not empty"
        with_region += 1
    # Counted against the agent set, not a literal: a new agent must carry the
    # region or be declared exempt, and neither can pass by the count drifting.
    assert with_region == len(agents) - len(NO_SKILLS_AGENTS), f"{with_region} of {len(agents)} agents"


def test_shipped_regions_are_well_formed_for_the_engine() -> None:
    # The deploy_core engine must see exactly one region per shipped agent, empty.
    for path in _agent_files():
        text = path.read_text(encoding="utf-8")
        if START not in text:
            continue
        bodies = deploy_core._managed_region_bodies(text)  # noqa: SLF001 - parity check
        assert bodies == {REGION: ""}, f"{path.name}: {bodies!r}"


def _fill_region(text: str) -> str:
    curated = (
        "- **cur-alpha** (`skills/cur-alpha/SKILL.md`) \u2014 curated\n"
        "- **cur-beta** (`skills/cur-beta/SKILL.md`) \u2014 curated\n"
    )
    return text.replace(f"{START}\n{END}", f"{START}\n{curated}{END}")


@pytest.mark.parametrize("path", _agent_files(), ids=lambda p: p.stem)
def test_filling_region_is_classification_invariant(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if START not in text:
        pytest.skip("no curated-skills region")
    filled = _fill_region(text)
    assert filled != text, "fixture did not inject curated lines"
    # Stripping the filled agent yields the shipped (empty-region) content, so the
    # deploy classifies a curated agent as UNCHANGED against the framework source.
    assert deploy_core.strip_managed_regions(filled) == text
    # And transplanting the filled target onto the empty framework base restores it.
    assert deploy_core.merge_managed_regions(text, filled) == filled
