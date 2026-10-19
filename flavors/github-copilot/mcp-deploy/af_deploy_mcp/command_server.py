"""AF command server -- run project scripts with agent-supplied arguments (#60).

A stdio MCP server, separate from the deploy server, so agent tool tables can
grant it on its own. Two tools:

* ``run_script``   -- run one script inside a configured script folder.
* ``list_scripts`` -- list the runnable scripts per folder (read-only).

Scripts run without a shell, with an argv list, under a walltime that is an
upper bound: the call returns as soon as the script exits. Approval follows
``AF_SCRIPT_APPROVAL`` / ``AF_SCRIPT_DIRS`` in ``.github/af-env.conf``; see
``command_trust``. Elicitation is the approval channel; without it, the
asking modes refuse.
"""

# copilot:generated | coordinator | 2026-10-19

from __future__ import annotations

import contextlib
import os
from pathlib import Path

import anyio
import anyio.from_thread
import anyio.to_thread
from mcp.server.mcpserver import Context, MCPServer
from mcp.types import ToolAnnotations
from pydantic import BaseModel, Field

from . import command_core as core
from . import command_trust as trust

mcp = MCPServer("af-command")
PROGRESS_TICK_S = 15.0
_APPROVERS: dict[str, trust.Approver] = {}


class Approval(BaseModel):
    approve: bool = Field(description="Run this script now?")


def _trust_base(root: Path) -> Path | None:
    """``AF_COMMAND_TRUST_DIR`` if set and outside the workspace; agents can edit the workspace."""
    override = os.environ.get("AF_COMMAND_TRUST_DIR")
    if not override:
        return None
    base = Path(override).resolve()
    try:
        base.relative_to(root)
    except ValueError:
        return base
    return None


def _approver(root: Path) -> trust.Approver:
    key = os.path.normcase(str(root))
    if key not in _APPROVERS:
        _APPROVERS[key] = trust.Approver(root, trust.TrustStore(trust.store_path(root, _trust_base(root))), None)
    return _APPROVERS[key]


def _elicitor(ctx: Context | None) -> trust.Elicit | None:
    caps = getattr(ctx, "client_capabilities", None)
    if ctx is None or caps is None or caps.elicitation is None:
        return None

    def elicit(message: str) -> bool | None:
        try:
            result = anyio.from_thread.run(ctx.elicit, message, Approval)
        except Exception:
            return None
        if getattr(result, "action", None) != "accept":
            return False
        return bool(getattr(result.data, "approve", False))

    return elicit


def _ticker(ctx: Context | None):
    if ctx is None:
        return None

    def tick(elapsed: float, last_line: str) -> None:
        message = f"{int(elapsed)}s: {last_line}"[:200]
        with contextlib.suppress(Exception):
            anyio.from_thread.run(ctx.report_progress, elapsed, None, message)

    return tick


@mcp.tool()
async def run_script(
    workspace_root: str,
    path: str,
    args: list[str] | None = None,
    walltime_s: int | None = None,
    ctx: Context | None = None,
) -> dict:
    """Run a project script with arguments; returns when it exits.

    ``path`` is repo-relative and must lie in a configured script folder
    (default ``.github/scripts/agent``; reviewed scripts in ``.github/scripts``).
    ``.py`` runs with the project venv, ``.ps1`` with PowerShell, ``.sh`` with bash.
    ``args`` are passed as argv, never through a shell. ``walltime_s`` is an
    optional upper bound; omitted, it comes from past runs or the suite budget.
    Past it the process tree is killed and the verdict is TIMEOUT.

    Returns ``verdict`` (PASS, FAIL, TIMEOUT, REFUSED), ``exit_code``,
    ``duration_s``, ``walltime_s``, ``walltime_source``, the output ``tail``,
    the full ``log_path`` and, when refused or timed out, the ``reason``.
    """
    root = Path(workspace_root).resolve()
    if not root.is_dir():
        return {
            "verdict": "REFUSED",
            "exit_code": None,
            "duration_s": 0.0,
            "walltime_s": None,
            "walltime_source": None,
            "tail": "",
            "log_path": None,
            "reason": f"workspace root {root} is not a directory",
        }
    approver = _approver(root)
    approver.elicit = _elicitor(ctx)
    tick_s = PROGRESS_TICK_S

    def work() -> dict:
        return core.run_script(root, path, list(args or []), walltime_s, approver, _ticker(ctx), tick_s)

    return await anyio.to_thread.run_sync(work)


@mcp.tool(annotations=ToolAnnotations(readOnlyHint=True))
def list_scripts(workspace_root: str) -> dict:
    """List the scripts ``run_script`` accepts, per folder, with mode and default walltime."""
    root = Path(workspace_root).resolve()
    config = core.load_config(root)
    folders = []
    for folder in [*config.dirs, *[core.ScriptDir(d, "reviewed") for d in config.task_dirs]]:
        if any(f["folder"] == folder.rel for f in folders):
            continue
        base = root / folder.rel
        scripts = []
        if base.is_dir():
            for file in sorted(p for p in base.rglob("*") if p.suffix.lower() in core.EXTENSIONS):
                rel = file.relative_to(root).as_posix()
                try:
                    resolved = core.resolve_script(root, config, rel)
                except core.Refused:
                    continue
                if resolved.folder != folder.rel:
                    continue
                walltime, source = core.resolve_walltime(
                    None, core.read_history(root, rel), core.suite_budget(root, rel), config
                )
                scripts.append({"path": rel, "default_walltime_s": walltime, "walltime_source": source})
        folders.append({"folder": folder.rel, "mode": folder.mode or config.approval, "scripts": scripts})
    return {"folders": folders, "approval_default": config.approval}


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
