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
    """Guidance for a lifecycle-aware AF framework deploy into ``workspace_root``.

    Branches on first-time setup vs. redeploy. A first-time setup chains the
    project-customisation steps a user typically forgets (onboarding + initial
    skill curation); a redeploy restores curated skills (``--reapply``) and
    resolves conflicts. Both paths always end in conflict resolution.
    """
    return (
        f"Deploy the AF framework into `{workspace_root}` using ONLY the af "
        "MCP tools. Do not clone the AF repository and do not edit deployed files by "
        "hand — the server owns the payload and the write guards.\n\n"
        "## Step 1 — Assess\n"
        "1. Call `status` and report the bundled vs. deployed framework version.\n"
        "2. Call `dry_run`. Summarise the counts (CREATE / UPDATE / CONFLICT / PROTECT "
        "/ PRESERVE / UNCHANGED) and list the files that would change. Call out any "
        "CONFLICT and PROTECT files explicitly.\n"
        "3. **Determine the lifecycle stage** and tell the user which path you will take:\n"
        "   - **FIRST-TIME SETUP** if the target has no `.github/.af-manifest` yet (this "
        "deploy creates it), i.e. `status` reports no deployed version.\n"
        "   - **REDEPLOY** if `.github/.af-manifest` already exists.\n\n"
        "## Step 2 — Apply\n"
        "4. Present the pending CREATE/UPDATE changes and ask the user to confirm. Only "
        "after explicit approval, call `apply` with `confirm=true`. `apply` never "
        "overwrites CONFLICT / PROTECT / PRESERVE / `[customizable]` files and backs up "
        "everything it replaces, so it is safe to run even with conflicts pending.\n\n"
        "## Step 3 — Project customisation (branch on the lifecycle stage)\n"
        "These steps are part of the deploy, not optional afterthoughts. A user setting "
        "AF up for the first time will otherwise forget them and end up with framework "
        "files but no project-specific configuration.\n\n"
        "**On FIRST-TIME SETUP — run the target's project prompts in this order (the "
        "dependency matters: curation reads `af-env.conf`, which onboarding writes):**\n"
        "5a. Run the target's `/af-onboard-project` prompt. It analyses the codebase and "
        "fills `.github/af-env.conf`, `copilot-instructions.md`, and the architecture "
        "map. Without it, the framework is deployed but not adapted to the project.\n"
        "5b. Then run the target's `/af-curate-skills` prompt (no flag) to match skills "
        "to the tech stack. This creates `.github/skills/curated-assignments.json` — the "
        "record that later `--reapply` runs depend on.\n\n"
        "**On REDEPLOY:**\n"
        "5c. **Restore curated skills.** If `.github/skills/curated-assignments.json` "
        "exists, run the target's `/af-curate-skills --reapply` prompt. A deploy "
        "overwrites AF-owned files (agent definitions) and thereby RESETS curated skill "
        "assignments; reapply restores them from the recorded state. Skipping this "
        "silently loses the project's skill curation.\n"
        "5d. If `curated-assignments.json` is MISSING on a redeploy (the project was "
        "never curated), fall back to a full `/af-curate-skills` run (no flag) instead of "
        "silently skipping.\n\n"
        "## Step 4 — Resolve & report\n"
        "6. **Resolve conflicts.** If `apply` (or the dry-run) reported any CONFLICT "
        "files, run the `resolve_conflicts` prompt to merge them and re-baseline. "
        "Never leave a CONFLICT unresolved.\n"
        "7. Report what was applied, the backup directory, the lifecycle path taken "
        "(first-time vs. redeploy), whether onboarding/curation/reapply ran, and any "
        "remaining conflicts. Remind the user that `[customizable]` files (e.g. "
        "`af-env.conf`) are PRESERVED, so a redeploy never clobbers project-specific "
        "edits."
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
