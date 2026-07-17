"""Workflow prompt text for the AF deploy MCP server.

Kept dependency-free (no ``mcp`` import) so the guidance text is unit-testable
without the server framework. ``server.py`` thin-wraps each builder with
``@mcp.prompt()`` so they surface as ``/mcp.af.*`` slash commands in the
client. The text instructs the driving agent which tools to call, in what order,
and where a human confirmation is required — the tools themselves stay guarded.
"""

from __future__ import annotations


def deploy_prompt(workspace_root: str) -> str:
    """Guidance for a lifecycle-aware AF framework deploy into ``workspace_root``.

    Branches on first-time setup vs. redeploy. A first-time setup chains the
    project-customisation steps a user typically forgets (onboarding + initial
    skill curation). A redeploy resolves conflicts first, then reapplies curated
    skills on the FINAL base, then re-baselines once. Reapply runs *after*
    conflict resolution so taking the framework base for a curated-agent conflict
    does not discard the restored curation.
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
        "## Step 3 — First-time project customisation (FIRST-TIME SETUP only)\n"
        "On a first-time setup there are no conflicts yet, so adapt the project first "
        "(the dependency matters: curation reads `af-env.conf`, which onboarding writes):\n"
        "5a. Run the target's `/af-onboard-project` prompt. It analyses the codebase and "
        "fills `.github/af-env.conf`, `copilot-instructions.md`, and the architecture "
        "map. Without it, the framework is deployed but not adapted to the project.\n"
        "5b. Then run the target's `/af-curate-skills` prompt (no flag) to match skills "
        "to the tech stack. This creates `.github/skills/curated-assignments.json` — the "
        "record that later `--reapply` runs depend on. A first-time setup is done after "
        "Step 7.\n\n"
        "## Step 4 — Resolve conflicts (REDEPLOY)\n"
        "6. If `apply` (or the dry-run) reported any CONFLICT files, resolve each one: "
        "use `conflict_diff` to inspect and `write_resolved` to write the merged result "
        "(the merge half of the `resolve_conflicts` workflow). For a **curated-agent "
        "conflict** — an agent file carrying project-specific skill lines — take the "
        "**framework base**; the reapply in Step 5 restores the curation on top. Never "
        "leave a CONFLICT unresolved. **Defer the re-baseline to Step 6** — do not run "
        "`update_hashes` yet.\n\n"
        "## Step 5 — Reapply curated skills (REDEPLOY)\n"
        "7. **Reapply MUST run AFTER conflict resolution, never before.** A deploy "
        "resets AF-owned agent files, and taking the framework base for a curated-agent "
        "conflict discards curation — so reapply has to land curation on the FINAL, "
        "post-resolution base. If `.github/skills/curated-assignments.json` exists, run "
        "the target's `/af-curate-skills --reapply` prompt. If it is MISSING (the "
        "project was never curated), fall back to a full `/af-curate-skills` run (no "
        "flag) instead of silently skipping.\n\n"
        "## Step 6 — Re-baseline (final write)\n"
        "8. Call `update_hashes` with `confirm=true` ONCE, as the final write. This "
        "seals the resolved + reapplied state as the new baseline, so future dry-runs "
        "show PRESERVE (project-owned) instead of CONFLICT.\n\n"
        "## Step 7 — Report\n"
        "9. Report what was applied, the backup directory, the lifecycle path taken "
        "(first-time vs. redeploy), whether onboarding/curation/reapply ran, any "
        "remaining conflicts (should be none), and remind the user that `[customizable]` "
        "files (e.g. `af-env.conf`) are PRESERVED, so a redeploy never clobbers project-"
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
