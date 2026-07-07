"""AAIG deploy MCP server — read-only proof of concept.

Exposes two tools over stdio MCP:

* ``af_status``   — compare the bundled framework version against a target repo.
* ``af_dry_run``  — classify every deployable file (UPDATE/CONFLICT/PRESERVE/…)
                    without writing anything.

And one resource template:

* ``af://source/{path}`` — read a bundled source file (e.g. an agent definition).

This PoC is deliberately **read-only**: it never writes to the target. The write
tools (``af_apply``, ``af_write_resolved``, ``af_update_hashes``) are specified
in ``ideas/mcp-deploy-server.md`` but intentionally out of scope here.

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
