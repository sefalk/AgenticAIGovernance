"""Managed-region mechanism (measure #2a).

A deployed file may carry an ``AF:MANAGED:{name}`` region whose inner content is
project-owned. The deploy ignores that content for classification (hash over the
region-stripped file) and preserves it on write (transplant the target's region
into the framework base). Most files have no region and are unaffected.
"""

from __future__ import annotations

from pathlib import Path

from af_deploy_mcp import deploy_core

REGION = "curated-skills"


def _agent(region_body: str, base: str = "base-a") -> str:
    return (
        "## Skills\n"
        f"- **{base}** (`skills/{base}/SKILL.md`) \u2014 base\n"
        f"<!-- AF:MANAGED:{REGION}:START -->\n"
        f"{region_body}"
        f"<!-- AF:MANAGED:{REGION}:END -->\n\n"
        "## Next\n"
    )


def _write(p: Path, text: str) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8", newline="")


# ── Pure functions ──────────────────────────────────────────────────────────


def test_strip_empties_region_keeps_markers_and_base() -> None:
    stripped = deploy_core.strip_managed_regions(_agent("- **cur-x** (`skills/cur-x/SKILL.md`) \u2014 x\n"))
    assert "cur-x" not in stripped
    assert f"AF:MANAGED:{REGION}:START" in stripped
    assert f"AF:MANAGED:{REGION}:END" in stripped
    assert "base-a" in stripped


def test_strip_is_noop_without_regions() -> None:
    text = "## Skills\n- **base-a** (`skills/base-a/SKILL.md`) \u2014 base\n"
    assert deploy_core.strip_managed_regions(text) == text


def test_strip_of_empty_and_filled_region_are_equal() -> None:
    empty = _agent("")
    filled = _agent("- **cur-x** (`skills/cur-x/SKILL.md`) \u2014 x\n")
    assert deploy_core.strip_managed_regions(empty) == deploy_core.strip_managed_regions(filled)


def test_merge_transplants_overlay_region_into_base() -> None:
    base = _agent("", base="base-NEW")  # framework: empty region, updated base
    overlay = _agent("- **cur-x** (`skills/cur-x/SKILL.md`) \u2014 x\n", base="base-OLD")  # project
    merged = deploy_core.merge_managed_regions(base, overlay)
    assert "cur-x" in merged  # project region content preserved
    assert "base-NEW" in merged and "base-OLD" not in merged  # base from framework


def test_merge_noop_when_no_region() -> None:
    base = "## Skills\n- **base-NEW** x\n"
    overlay = "## Skills\n- **base-OLD** x\n"
    assert deploy_core.merge_managed_regions(base, overlay) == base


# ── Classification + write integration ──────────────────────────────────────


def _make_region_source(root: Path) -> Path:
    _write(root / "VERSION", "1.0.0\n")
    gh = root / ".github"
    _write(gh / ".af-manifest", "# manifest\nagents/\n")
    _write(gh / "agents" / "x.agent.md", _agent(""))  # framework ships empty region
    return root


def test_region_content_change_classifies_unchanged(tmp_path: Path) -> None:
    src = _make_region_source(tmp_path / "src")
    target = tmp_path / "proj"
    deploy_core.apply(src, target)
    # Project fills the curated region (base untouched).
    agent = target / ".github" / "agents" / "x.agent.md"
    _write(agent, _agent("- **cur-x** (`skills/cur-x/SKILL.md`) \u2014 x\n"))
    files = {f["path"]: f["classification"] for f in deploy_core.dry_run(src, target)["files"]}
    assert files[".github/agents/x.agent.md"] == "UNCHANGED"


def test_base_change_updates_and_preserves_region(tmp_path: Path) -> None:
    src = _make_region_source(tmp_path / "src")
    target = tmp_path / "proj"
    deploy_core.apply(src, target)
    agent = target / ".github" / "agents" / "x.agent.md"
    _write(agent, _agent("- **cur-x** (`skills/cur-x/SKILL.md`) \u2014 x\n"))
    # Framework changes the BASE (outside the region).
    _write(src / ".github" / "agents" / "x.agent.md", _agent("", base="base-b"))
    files = {f["path"]: f["classification"] for f in deploy_core.dry_run(src, target)["files"]}
    assert files[".github/agents/x.agent.md"] == "UPDATE"
    deploy_core.apply(src, target)
    written = agent.read_text(encoding="utf-8")
    assert "base-b" in written  # framework base update landed
    assert "cur-x" in written  # project region preserved
