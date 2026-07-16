"""Tests for the deploy MCP workflow prompt text."""

from __future__ import annotations

from af_deploy_mcp import prompts


def test_deploy_prompt_orders_the_tool_workflow() -> None:
    text = prompts.deploy_prompt("/proj")
    assert "/proj" in text
    # The deploy prompt must reference the read-then-guarded-write sequence.
    for tool in ("status", "dry_run", "apply"):
        assert tool in text
    assert "confirm=true" in text
    # Conflicts must be routed to the resolution prompt, never overwritten.
    assert "resolve_conflicts" in text
    assert "CONFLICT" in text


def test_deploy_prompt_warns_about_customizable_preservation() -> None:
    text = prompts.deploy_prompt("/proj")
    assert "[customizable]" in text
    assert "af-env.conf" in text


def test_deploy_prompt_chains_post_deploy_steps() -> None:
    text = prompts.deploy_prompt("/proj")
    # Curated-skill reapply must be a wired post-deploy step (not lost on deploy reset).
    assert "curated-assignments.json" in text
    assert "--reapply" in text
    # Conflict resolution must route to the resolve prompt as a post-deploy step.
    assert "resolve_conflicts" in text


def test_deploy_prompt_is_lifecycle_aware() -> None:
    text = prompts.deploy_prompt("/proj")
    # Must distinguish first-time setup from redeploy and detect via the manifest.
    assert "FIRST-TIME SETUP" in text
    assert "REDEPLOY" in text
    assert ".af-manifest" in text


def test_deploy_prompt_first_time_chains_onboard_then_curate() -> None:
    text = prompts.deploy_prompt("/proj")
    # First-time setup must trigger onboarding and INITIAL curation (not just reapply).
    assert "/af-onboard-project" in text
    assert "/af-curate-skills" in text
    # Onboarding must come before curation (curate reads af-env.conf that onboard writes).
    assert text.index("/af-onboard-project") < text.index("/af-curate-skills")


def test_deploy_prompt_redeploy_falls_back_to_full_curate_when_uncurated() -> None:
    text = prompts.deploy_prompt("/proj")
    # A redeploy of a never-curated project must not silently skip curation.
    assert "MISSING" in text
    assert "fall back" in text.lower()


def test_resolve_conflicts_prompt_orders_the_merge_workflow() -> None:
    text = prompts.resolve_conflicts_prompt("/proj")
    assert "/proj" in text
    for tool in ("dry_run", "conflict_diff", "write_resolved", "update_hashes"):
        assert tool in text
    assert "confirm=true" in text
    # Must mention VS Code path handling so conflicts there are resolvable too.
    assert ".vscode/" in text
