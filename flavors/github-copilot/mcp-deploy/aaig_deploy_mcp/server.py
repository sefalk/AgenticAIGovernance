"""AAIG deploy MCP server — proof of concept.

Exposes the deploy over stdio MCP, covering both the ``.github/`` payload and
manifest ``[vscode]`` files (deployed to ``.vscode/``):

* ``af_status``        — compare the bundled framework version against a target.
* ``af_dry_run``       — classify every deployable file (read-only).
* ``af_conflict_diff`` — unified diff for a single file (read-only).
* ``af_apply``         — apply CREATE/UPDATE files (guarded by ``confirm``).
* ``af_write_resolved``— write an agent-merged file (guarded by ``confirm``).
* ``af_update_hashes`` — re-baseline ``.af-hashes`` (guarded by ``confirm``).
* ``af_prune_backups`` — housekeeping (guarded by ``confirm``).

And a resource template ``af://source/{path}`` for bundled source files.

**Safety (this is where the deploy's guards now live — the terminal hook does
not see MCP tool calls):** write tools require ``confirm=True`` (a production
server would use MCP *elicitation* instead), all writes stay under the target's
``.github/``, existing files are backed up before overwrite, and CONFLICT /
PROTECT / PRESERVE / ``[customizable]`` files are never written by ``af_apply``.

The framework payload is resolved from ``AF_SOURCE_ROOT`` if set, else from the
in-repo flavor directory (dev mode). A packaged build would bundle the payload
as package data.
"""

# copilot:generated | implementer | 2026-07-07

from __future__ import annotations

import os
from pathlib import Path

from mcp.server.fastmcp import FastMCP

from . import deploy_core

mcp = FastMCP("aaig-deploy")


def _source_root() -> Path:
    env = os.environ.get("AF_SOURCE_ROOT")
    if env:
        return Path(env).resolve()
    # Dev mode: flavors/github-copilot (two parents above this package).
    return Path(__file__).resolve().parents[2]


def _validate_source(root: Path) -> str | None:
    if not (root / "VERSION").is_file():
        return f"Bundled payload invalid: VERSION not found under {root}"
    if not (root / ".github" / ".af-manifest").is_file():
        return f"Bundled payload invalid: .github/.af-manifest not found under {root}"
    return None


def _validate_target(target: Path) -> str | None:
    if not target.is_dir():
        return f"Workspace root not found or not a directory: {target}"
    return None


def _prep(workspace_root: str) -> tuple[Path | None, Path | None, str | None]:
    """Resolve and validate the bundled source and the target; return (src, target, error)."""
    src = _source_root()
    if err := _validate_source(src):
        return None, None, err
    target = Path(workspace_root).resolve()
    if err := _validate_target(target):
        return None, None, err
    return src, target, None


@mcp.tool()
def af_status(workspace_root: str) -> dict:
    """Report the bundled framework version vs. the version deployed in a repo.

    Args:
        workspace_root: Absolute path to the target project (``${workspaceFolder}``).

    Returns a dict with ``source_version``, ``deployed_version`` and ``state``
    (``up-to-date`` | ``stale`` | ``not-deployed``).
    """
    src = _source_root()
    if err := _validate_source(src):
        return {"error": err}
    target = Path(workspace_root).resolve()
    if err := _validate_target(target):
        return {"error": err}
    return {"source_root": str(src), "workspace_root": str(target), **deploy_core.status(src, target)}


@mcp.tool()
def af_dry_run(workspace_root: str) -> dict:
    """Preview a deploy: classify every deployable file without writing anything.

    Args:
        workspace_root: Absolute path to the target project (``${workspaceFolder}``).

    Returns per-file classifications (UPDATE / CONFLICT / PRESERVE / PROTECT /
    UNCHANGED / CREATE) plus summary counts — the same decisions the deploy
    script would make, computed read-only.
    """
    src = _source_root()
    if err := _validate_source(src):
        return {"error": err}
    target = Path(workspace_root).resolve()
    if err := _validate_target(target):
        return {"error": err}
    result = deploy_core.dry_run(src, target)
    result["source_root"] = str(src)
    result["workspace_root"] = str(target)
    return result


@mcp.tool()
def af_conflict_diff(workspace_root: str, path: str) -> dict:
    """Unified diff between a deployed file and the resolved framework source.

    Args:
        workspace_root: Absolute path to the target project.
        path: ``.github``-relative path (e.g. ``instructions/git-workflow.instructions.md``),
            or a ``.vscode/``-prefixed path for a VS Code file (e.g. ``.vscode/settings.json``).
    """
    src, target, err = _prep(workspace_root)
    if err:
        return {"error": err}
    return {"path": f".github/{path}", "diff": deploy_core.conflict_diff(src, target, path)}


@mcp.tool()
def af_apply(workspace_root: str, confirm: bool = False) -> dict:
    """Apply the pending CREATE/UPDATE files (backs up first).

    With ``confirm=False`` (default) this returns the dry-run preview and writes
    nothing — re-call with ``confirm=True`` to apply. CONFLICT / PROTECT /
    PRESERVE / ``[customizable]`` files are never written.
    """
    src, target, err = _prep(workspace_root)
    if err:
        return {"error": err}
    if not confirm:
        preview = deploy_core.dry_run(src, target)
        return {
            "confirmation_required": True,
            "message": "Re-call af_apply with confirm=true to write these changes.",
            "counts": preview["counts"],
        }
    return {"workspace_root": str(target), **deploy_core.apply(src, target)}


@mcp.tool()
def af_write_resolved(workspace_root: str, path: str, content: str, confirm: bool = False) -> dict:
    """Write agent-merged content to a ``.github/`` (or ``.vscode/``) file.

    Guarded by ``confirm``; refuses paths outside the workspace. A ``.vscode/``
    prefix targets the VS Code tree; a bare path is ``.github``-relative.
    """
    _src, target, err = _prep(workspace_root)
    if err:
        return {"error": err}
    if not confirm:
        return {
            "confirmation_required": True,
            "message": f"Re-call with confirm=true to write .github/{path} ({len(content)} chars).",
        }
    try:
        return deploy_core.write_resolved(target, path, content)
    except ValueError as exc:
        return {"error": str(exc)}


@mcp.tool()
def af_update_hashes(workspace_root: str, confirm: bool = False) -> dict:
    """Re-baseline ``.af-hashes`` after resolving conflicts. Guarded by ``confirm``."""
    src, target, err = _prep(workspace_root)
    if err:
        return {"error": err}
    if not confirm:
        return {"confirmation_required": True, "message": "Re-call with confirm=true to rewrite .af-hashes."}
    return deploy_core.update_hashes(src, target)


@mcp.tool()
def af_prune_backups(workspace_root: str, days: int = 14, confirm: bool = False) -> dict:
    """Remove ``.af-backup-*`` directories older than ``days``. Guarded by ``confirm``."""
    _src, target, err = _prep(workspace_root)
    if err:
        return {"error": err}
    if not confirm:
        return {"confirmation_required": True, "message": f"Re-call with confirm=true to prune backups older than {days}d."}
    return deploy_core.prune_backups(target, days)


@mcp.resource("af://source/{path}")
def source_file(path: str) -> str:
    """Return the content of a bundled source file under ``.github/``.

    Example: ``af://source/agents/planner.agent.md``. Path traversal outside the
    payload is refused.
    """
    src = _source_root()
    base = (src / ".github").resolve()
    target = (base / path).resolve()
    if not str(target).startswith(str(base)):
        return f"Refused: '{path}' resolves outside the bundled payload."
    if not target.is_file():
        return f"Not found: .github/{path}"
    return target.read_text(encoding="utf-8", errors="replace")


def main() -> None:
    """Console-script entry point (stdio transport)."""
    mcp.run()


if __name__ == "__main__":
    main()
