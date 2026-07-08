"""Workflow prompt text for the AAIG deploy MCP server.

Kept dependency-free (no ``mcp`` import) so the guidance text is unit-testable
without the server framework. ``server.py`` thin-wraps each builder with
``@mcp.prompt()`` so they surface as ``/mcp.aaig-deploy.*`` slash commands in the
client. The text instructs the driving agent which tools to call, in what order,
and where a human confirmation is required — the tools themselves stay guarded.
"""

# copilot:generated | implementer | 2026-07-08

from __future__ import annotations


def deploy_prompt(workspace_root: str) -> str:
    """Guidance for a full AAIG framework deploy into ``workspace_root``."""
    return (
        f"Deploy the AAIG framework into `{workspace_root}` using ONLY the aaig-deploy "
        "MCP tools. Do not clone the AAIG repository and do not edit deployed files by "
        "hand — the server owns the payload and the write guards.\n\n"
        "Follow these steps:\n"
        "1. Call `af_status` and report the bundled vs. deployed framework version.\n"
        "2. Call `af_dry_run`. Summarise the counts (CREATE / UPDATE / CONFLICT / PROTECT "
        "/ PRESERVE / UNCHANGED) and list the files that would change. Call out any "
        "CONFLICT and PROTECT files explicitly.\n"
        "3. If any file is CONFLICT, STOP: tell the user to run the `af_resolve_conflicts` "
        "prompt first. Never overwrite a conflict.\n"
        "4. Otherwise, present the pending CREATE/UPDATE changes and ask the user to "
        "confirm. Only after explicit approval, call `af_apply` with `confirm=true`.\n"
        "5. Report what was applied and the backup directory. Remind the user that "
        "`[customizable]` files (e.g. `af-env.conf`) are PRESERVED, so a first-time "
        "deploy may still need project-specific edits to `af-env.conf`.\n"
        "6. If the project uses curated skill assignments, remind the user to run "
        "`/curate-skills --reapply` afterwards."
    )


def resolve_conflicts_prompt(workspace_root: str) -> str:
    """Guidance for merging CONFLICT files and re-baselining in ``workspace_root``."""
    return (
        f"Resolve AAIG deploy conflicts in `{workspace_root}` using the aaig-deploy MCP "
        "tools. A CONFLICT means both the framework and the project changed a file since "
        "the last baseline — it needs a real merge, never a blind overwrite.\n\n"
        "Follow these steps:\n"
        "1. Call `af_dry_run` and collect every file classified CONFLICT.\n"
        "2. For each CONFLICT file, call `af_conflict_diff` with its path (`.github`-"
        "relative, or prefixed with `.vscode/` for a VS Code file) to see the project vs. "
        "framework changes.\n"
        "3. Produce a merged version that preserves the project's intent and folds in the "
        "framework's updates. Show each merge to the user for approval.\n"
        "4. On approval, write it with `af_write_resolved(path, content, confirm=true)`.\n"
        "5. When every conflict is resolved, call `af_update_hashes` with `confirm=true` "
        "to re-baseline `.af-hashes` so the resolved files classify as UNCHANGED next "
        "time.\n"
        "6. Call `af_dry_run` once more and confirm there are no remaining CONFLICT files."
    )
