"""Workflow prompt text for the AF deploy MCP server.

Kept dependency-free (no ``mcp`` import) so the guidance text is unit-testable
without the server framework. ``server.py`` thin-wraps each builder with
``@mcp.prompt()`` so they surface as ``/mcp.af.*`` slash commands in the
client. The text instructs the driving agent which tools to call, in what order,
and where a human confirmation is required — the tools themselves stay guarded.
"""

# copilot:generated | implementer | 2026-07-08

from __future__ import annotations


def deploy_prompt(workspace_root: str) -> str:
    """Guidance for a full AF framework deploy into ``workspace_root``.

    Chains the two post-deploy steps a deploy must always run: curated-skill
    reapply (a deploy overwrites AF-owned agent files) and conflict resolution.
    """
    return (
        f"Deploy the AF framework into `{workspace_root}` using ONLY the af "
        "MCP tools. Do not clone the AF repository and do not edit deployed files by "
        "hand — the server owns the payload and the write guards.\n\n"
        "Follow these steps:\n"
        "1. Call `status` and report the bundled vs. deployed framework version.\n"
        "2. Call `dry_run`. Summarise the counts (CREATE / UPDATE / CONFLICT / PROTECT "
        "/ PRESERVE / UNCHANGED) and list the files that would change. Call out any "
        "CONFLICT and PROTECT files explicitly.\n"
        "3. Present the pending CREATE/UPDATE changes and ask the user to confirm. Only "
        "after explicit approval, call `apply` with `confirm=true`. `apply` never "
        "overwrites CONFLICT / PROTECT / PRESERVE / `[customizable]` files and backs up "
        "everything it replaces, so it is safe to run even with conflicts pending.\n\n"
        "Then ALWAYS run these post-deploy steps — they are part of the deploy, not "
        "optional afterthoughts:\n"
        "4. **Restore curated skills.** If `.github/skills/curated-assignments.json` "
        "exists in the target, run the target's `/af-curate-skills --reapply` prompt. A "
        "deploy overwrites AF-owned files (agent definitions) and thereby RESETS curated "
        "skill assignments; reapply restores them from the recorded state. Skipping this "
        "silently loses the project's skill curation.\n"
        "5. **Resolve conflicts.** If `apply` (or the dry-run) reported any CONFLICT "
        "files, run the `resolve_conflicts` prompt to merge them and re-baseline. "
        "Never leave a CONFLICT unresolved.\n"
        "6. Report what was applied, the backup directory, whether reapply ran, and any "
        "remaining conflicts. Remind the user that `[customizable]` files (e.g. "
        "`af-env.conf`) are PRESERVED, so a first-time deploy may still need project-"
        "specific edits."
    )


def resolve_conflicts_prompt(workspace_root: str) -> str:
    """Guidance for merging CONFLICT files and re-baselining in ``workspace_root``."""
    return (
        f"Resolve AF deploy conflicts in `{workspace_root}` using the af MCP "
        "tools. A CONFLICT means both the framework and the project changed a file since "
        "the last baseline — it needs a real merge, never a blind overwrite.\n\n"
        "Follow these steps:\n"
        "1. Call `dry_run` and collect every file classified CONFLICT.\n"
        "2. For each CONFLICT file, call `conflict_diff` with its path (`.github`-"
        "relative, or prefixed with `.vscode/` for a VS Code file) to see the project vs. "
        "framework changes.\n"
        "3. Produce a merged version that preserves the project's intent and folds in the "
        "framework's updates. Show each merge to the user for approval.\n"
        "4. On approval, write it with `write_resolved(path, content, confirm=true)`.\n"
        "5. When every conflict is resolved, call `update_hashes` with `confirm=true` "
        "to re-baseline `.af-hashes` so the resolved files classify as UNCHANGED next "
        "time.\n"
        "6. Call `dry_run` once more and confirm there are no remaining CONFLICT files."
    )
