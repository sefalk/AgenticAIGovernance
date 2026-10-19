"""Approval and trust for the AF command server (#60).

Decides whether a resolved script may run, per the folder's approval mode:

* ``off``        -- refuse.
* ``reviewed``   -- run a script committed and unchanged against ``HEAD``;
                    anything else falls back to ``AF_SCRIPT_APPROVAL``.
* ``ask``        -- ask the user once per content hash; an accepted hash runs freely.
* ``ask-always`` -- ask on every run.
* ``autonomous`` -- run without asking.

Every mode except ``reviewed`` first passes the script text through the
project's own ``block-dangerous`` hook; a ``deny`` refuses. Asking fails
closed: no elicitation, a failed one, or a decline all refuse.

The trust store lives outside the workspace, under the user profile, so an
agent's file edits cannot approve its own script.
"""

# copilot:generated | coordinator | 2026-10-19

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
from collections.abc import Callable
from pathlib import Path

from .command_core import Config, Resolved

Elicit = Callable[[str], "bool | None"]
Scanner = Callable[[Path, Path], "str | None"]
HOOK_TIMEOUT_S = 60


def default_store_base() -> Path:
    """Per-user trust directory: ``%LOCALAPPDATA%`` on Windows, XDG state elsewhere."""
    if sys.platform == "win32":
        base = Path(os.environ.get("LOCALAPPDATA") or Path.home() / "AppData" / "Local")
    else:
        base = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state")
    return base / "af-command-mcp" / "trust"


def store_path(workspace_root: Path, base: Path | None = None) -> Path:
    """The trust file for one repository, keyed by a hash of its resolved path."""
    key = os.path.normcase(str(workspace_root.resolve()))
    return (base or default_store_base()) / f"{hashlib.sha256(key.encode('utf-8')).hexdigest()}.json"


class TrustStore:
    """Accepted ``(path, sha256)`` pairs for one repository."""

    def __init__(self, path: Path) -> None:
        self.path = path

    def _load(self) -> dict[str, list[str]]:
        if not self.path.is_file():
            return {}
        try:
            return json.loads(self.path.read_text(encoding="utf-8")).get("trusted", {})
        except (json.JSONDecodeError, OSError):
            return {}

    def is_trusted(self, rel: str, digest: str) -> bool:
        return digest in self._load().get(rel, [])

    def add(self, rel: str, digest: str) -> None:
        trusted = self._load()
        trusted.setdefault(rel, [])
        if digest not in trusted[rel]:
            trusted[rel].append(digest)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps({"trusted": trusted}, indent=2), encoding="utf-8")


def _git_ok(workspace_root: Path, *args: str) -> bool:
    try:
        proc = subprocess.run(["git", "-C", str(workspace_root), *args], capture_output=True, timeout=30, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return proc.returncode == 0


def is_reviewed(workspace_root: Path, rel: str) -> bool:
    """True if ``rel`` is tracked and byte-equal to ``HEAD``."""
    return _git_ok(workspace_root, "ls-files", "--error-unmatch", "--", rel) and _git_ok(
        workspace_root, "diff", "--quiet", "HEAD", "--", rel
    )


def effective_mode(workspace_root: Path, resolved: Resolved, config: Config) -> str:
    """The approval mode that applies to this script right now."""
    mode = resolved.folder_mode or config.approval
    if mode != "reviewed":
        return mode
    if is_reviewed(workspace_root, resolved.rel):
        return "reviewed"
    return "off" if config.approval == "reviewed" else config.approval


def hook_scan(workspace_root: Path, script: Path) -> str | None:
    """Pass the script text through ``block-dangerous``; return the refusal reason or ``None``."""
    hooks = workspace_root / ".github" / "hooks" / "scripts"
    if sys.platform == "win32":
        hook = hooks / "block-dangerous.ps1"
        argv = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(hook)]
    else:
        hook = hooks / "block-dangerous.sh"
        argv = ["bash", str(hook)]
    if not hook.is_file():
        return f"content scan unavailable: {hook} not found; refusing (fail closed)"
    payload = json.dumps(
        {
            "hookEventName": "PreToolUse",
            "cwd": str(workspace_root),
            "tool_name": "run_in_terminal",
            "tool_input": {"command": script.read_text(encoding="utf-8", errors="replace")},
        }
    )
    try:
        proc = subprocess.run(
            argv,
            input=payload,
            capture_output=True,
            text=True,
            encoding="utf-8",
            cwd=str(workspace_root),
            timeout=HOOK_TIMEOUT_S,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return f"content scan unavailable: {exc}; refusing (fail closed)"
    lines = [line for line in proc.stdout.splitlines() if line.strip().startswith("{")]
    try:
        output = json.loads(lines[-1]) if lines else None
    except json.JSONDecodeError:
        output = None
    if not isinstance(output, dict):
        return "content scan unavailable: unreadable hook output; refusing (fail closed)"
    decision = output.get("hookSpecificOutput", {})
    if decision.get("permissionDecision") == "deny":
        return f"content scan denied: {decision.get('permissionDecisionReason', 'no reason given')}"
    return None


class Approver:
    """The ``approve`` callback for ``command_core.run_script``."""

    def __init__(
        self, workspace_root: Path, store: TrustStore, elicit: Elicit | None, scanner: Scanner = hook_scan
    ) -> None:
        self.root = workspace_root
        self.store = store
        self.elicit = elicit
        self.scanner = scanner
        self._scans: dict[str, str | None] = {}

    def __call__(self, resolved: Resolved, digest: str, config: Config) -> str | None:
        mode = effective_mode(self.root, resolved, config)
        if mode == "off":
            return f"'{resolved.rel}' may not run: approval mode is off for {resolved.folder}"
        if mode == "reviewed":
            return None
        if digest not in self._scans:
            self._scans[digest] = self.scanner(self.root, resolved.path)
        if (reason := self._scans[digest]) is not None:
            return reason
        if mode == "autonomous" or (mode == "ask" and self.store.is_trusted(resolved.rel, digest)):
            return None
        if self.elicit is None:
            return f"mode {mode} needs the user's approval, but the client offers no elicitation; refusing"
        answer = self.elicit(
            f"Run the agent script '{resolved.rel}' (sha256 {digest[:12]})? Approval mode: {mode}."
            + (" An approval holds until the script changes." if mode == "ask" else "")
        )
        if answer is None:
            return f"elicitation failed for '{resolved.rel}'; refusing (fail closed)"
        if not answer:
            return f"'{resolved.rel}' declined by the user"
        if mode == "ask":
            self.store.add(resolved.rel, digest)
        return None
