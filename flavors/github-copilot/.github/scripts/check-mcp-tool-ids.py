#!/usr/bin/env python3
"""Detect legacy Azure DevOps MCP tool identifiers in framework markdown.

The azure-devops-mcp server consolidated its per-operation tools into grouped
tools driven by an ``action`` parameter (upstream v2.9.0). Agent files that still
name the old identifiers fail prompt validation and the tool is silently dropped,
which disables the agent without any error at run time.

This checker is a denylist, not an allowlist, on purpose: it never needs a
complete picture of the current toolset, it cannot go stale in a way that
produces false passes, and every hit carries a concrete migration target.

Checks:
    1. Frontmatter ``tools:`` entries naming a legacy identifier.
    2. Prose references (backticked or bare) naming a legacy identifier.

Usage:
    python check-mcp-tool-ids.py [--root <dir>] [--quiet]

Exit codes:
    0 -- no legacy identifiers found
    1 -- legacy identifiers found
    2 -- fatal error (root not found)
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Migration map: legacy identifier -> (current tool, action or None)
# ---------------------------------------------------------------------------

MIGRATIONS: dict[str, tuple[str, str | None]] = {
    # Work items
    "wit_my_work_items": ("wit_work_item", "my"),
    "wit_get_work_item": ("wit_work_item", "get"),
    "wit_get_work_items_batch_by_ids": ("wit_work_item", "get_batch"),
    "wit_get_work_item_type": ("wit_work_item", "get_type"),
    "wit_list_work_item_comments": ("wit_work_item", "list_comments"),
    "wit_get_work_items_for_iteration": ("wit_work_item", "list_for_iteration"),
    "wit_create_work_item": ("wit_work_item_write", "create"),
    "wit_update_work_item": ("wit_work_item_write", "update"),
    "wit_update_work_items_batch": ("wit_work_item_write", "update_batch"),
    "wit_add_child_work_items": ("wit_work_item_write", "add_child"),
    "wit_add_work_item_comment": ("wit_work_item_comment_write", "add"),
    "wit_update_work_item_comment": ("wit_work_item_comment_write", "update"),
    "wit_work_items_link": ("wit_work_item_link_write", "link"),
    "wit_work_item_unlink": ("wit_work_item_link_write", "unlink"),
    "wit_link_work_item_to_pull_request": ("wit_work_item_link_write", "link_to_pull_request"),
    "wit_add_artifact_link": ("wit_work_item_link_write", "add_artifact_link"),
    "wit_query_by_wiql": ("wit_query", "wiql"),
    "wit_get_query": ("wit_query", "get"),
    "wit_get_query_results_by_id": ("wit_query", "get_results"),
    "wit_list_backlogs": ("wit_backlog", "list"),
    "wit_list_backlog_work_items": ("wit_backlog", "list_work_items"),
    # Repositories
    "repo_get_repo_by_name_or_id": ("repo_repository", "get"),
    "repo_list_repos_by_project": ("repo_repository", "list"),
    "repo_get_branch_by_name": ("repo_branch", "get"),
    "repo_list_branches_by_repo": ("repo_branch", "list"),
    "repo_list_my_branches_by_repo": ("repo_branch", "list_mine"),
    "repo_get_file_content": ("repo_file", "get_content"),
    "repo_get_pull_request_by_id": ("repo_pull_request", "get"),
    "repo_list_pull_requests_by_repo": ("repo_pull_request", "list"),
    "repo_list_pull_requests_by_project": ("repo_pull_request", "list"),
    "repo_list_pull_requests_by_repo_or_project": ("repo_pull_request", "list"),
    "repo_list_pull_requests_by_commits": ("repo_pull_request", "list_by_commits"),
    "repo_list_pull_request_threads": ("repo_pull_request_thread", "list"),
    "repo_list_pull_request_thread_comments": ("repo_pull_request_thread", "list_comments"),
    "repo_create_pull_request": ("repo_pull_request_write", "create"),
    "repo_update_pull_request": ("repo_pull_request_write", "update"),
    "repo_update_pull_request_reviewers": ("repo_pull_request_write", "update_reviewers"),
    "repo_update_pull_request_status": ("repo_pull_request_write", "update"),
    "repo_create_pull_request_thread": ("repo_pull_request_thread_write", "create"),
    "repo_reply_to_comment": ("repo_pull_request_thread_write", "reply"),
    "repo_resolve_comment": ("repo_pull_request_thread_write", "update_status"),
    # Pipelines
    "pipelines_create_pipeline": ("pipelines_write", "create_pipeline"),
    "pipelines_run_pipeline": ("pipelines_write", "run_pipeline"),
    "pipelines_update_build_stage": ("pipelines_write", "update_build_stage"),
    "pipelines_get_build_definitions": ("pipelines_definition", "list"),
    "pipelines_get_build_definition_revisions": ("pipelines_definition", "list_revisions"),
    "pipelines_get_builds": ("pipelines_build", "list"),
    "pipelines_get_build_status": ("pipelines_build", "get_status"),
    "pipelines_get_build_changes": ("pipelines_build", "get_changes"),
    "pipelines_get_build_log": ("pipelines_build_log", "list"),
    "pipelines_get_build_log_by_id": ("pipelines_build_log", "get_content"),
    # Wiki
    "wiki_list_wikis": ("wiki", "list_wikis"),
    "wiki_get_wiki": ("wiki", "get_wiki"),
    "wiki_list_pages": ("wiki", "list_pages"),
    "wiki_get_page_by_path": ("wiki", "get_page"),
    "wiki_get_page_content": ("wiki", "get_page_content"),
    "wiki_create_or_update_page": ("wiki_upsert_page", None),
    # Work (teams / iterations)
    "work_list_team_iterations": ("work", "list_team_iterations"),
    "work_list_iterations": ("work", "list_iterations"),
    "work_create_iterations": ("work_iteration_write", "create"),
    "work_assign_iterations": ("work_iteration_write", "assign"),
}

# Word-boundary match so `repo_file` never matches inside `repo_file_content`.
LEGACY_PATTERN = re.compile(r"\b(" + "|".join(sorted(MIGRATIONS, key=len, reverse=True)) + r")\b")

SCAN_GLOB = "**/*.md"
SKIP_DIRS = {".venv", "node_modules", "site-packages", ".git"}


# ---------------------------------------------------------------------------
# Scanning
# ---------------------------------------------------------------------------


def iter_markdown(root: Path):
    """Yield markdown files under root, skipping vendored directories."""
    for path in root.glob(SCAN_GLOB):
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        yield path


def scan_file(path: Path) -> list[tuple[int, str, str]]:
    """Return (line_number, legacy_id, suggestion) for each legacy reference."""
    findings: list[tuple[int, str, str]] = []
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return findings

    for lineno, line in enumerate(text.splitlines(), start=1):
        for match in LEGACY_PATTERN.finditer(line):
            legacy = match.group(1)
            tool, action = MIGRATIONS[legacy]
            suggestion = tool if action is None else f"{tool} (action `{action}`)"
            findings.append((lineno, legacy, suggestion))
    return findings


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    """Scan markdown for legacy azure-devops-mcp tool identifiers."""
    parser = argparse.ArgumentParser(description="Detect legacy Azure DevOps MCP tool identifiers.")
    parser.add_argument("--root", default=".github", help="Directory to scan (default: .github)")
    parser.add_argument("--quiet", action="store_true", help="Only print the summary line")
    args = parser.parse_args(argv)

    root = Path(args.root)
    if not root.is_dir():
        print(f"ERROR: root directory not found: {root}", file=sys.stderr)
        return 2

    total = 0
    files_hit = 0
    for path in sorted(iter_markdown(root)):
        findings = scan_file(path)
        if not findings:
            continue
        files_hit += 1
        total += len(findings)
        if not args.quiet:
            print(f"\n{path}")
            for lineno, legacy, suggestion in findings:
                print(f"  line {lineno}: {legacy}  ->  {suggestion}")

    if total:
        print(
            f"\nFAIL: {total} legacy MCP tool reference(s) in {files_hit} file(s). "
            "These fail prompt validation and are dropped silently at run time."
        )
        return 1

    print(f"OK: no legacy MCP tool references under {root}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
