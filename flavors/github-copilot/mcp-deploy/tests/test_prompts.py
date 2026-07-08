"""Tests for the deploy MCP workflow prompt text."""

# copilot:generated | test-writer | 2026-07-08

from __future__ import annotations

from aaig_deploy_mcp import prompts


def test_deploy_prompt_orders_the_tool_workflow() -> None:
    text = prompts.deploy_prompt("/proj")
    assert "/proj" in text
    # The deploy prompt must reference the read-then-guarded-write sequence.
    for tool in ("af_status", "af_dry_run", "af_apply"):
        assert tool in text
    assert "confirm=true" in text
    # Conflicts must be routed to the resolution prompt, never overwritten.
    assert "af_resolve_conflicts" in text
    assert "CONFLICT" in text


def test_deploy_prompt_warns_about_customizable_preservation() -> None:
    text = prompts.deploy_prompt("/proj")
    assert "[customizable]" in text
    assert "af-env.conf" in text


def test_resolve_conflicts_prompt_orders_the_merge_workflow() -> None:
    text = prompts.resolve_conflicts_prompt("/proj")
    assert "/proj" in text
    for tool in ("af_dry_run", "af_conflict_diff", "af_write_resolved", "af_update_hashes"):
        assert tool in text
    assert "confirm=true" in text
    # Must mention VS Code path handling so conflicts there are resolvable too.
    assert ".vscode/" in text
