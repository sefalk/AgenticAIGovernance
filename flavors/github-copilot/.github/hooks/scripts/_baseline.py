"""Shared surface for the per-invocation working-tree baseline (issue #101).

Every producer stop gate scopes itself from ``git diff``, which is global to the
checkout. Uncommitted work that was already there when the subagent started --
an earlier producer's output the coordinator has not committed yet -- then lands
in this subagent's scope, and its provenance gate makes it stamp an authorship
marker on a file it never touched.

Two halves, one record format, hence one module:

  write  ``subagent-baseline.py`` (SubagentStart) records, per ``agent_id``, every
         dirty path and the blob hash of its content.
  read   ``concurrent-agent-edits.py --baseline-dir`` (producer Stop) lists the
         paths whose content is still byte-identical: the subagent cannot have
         authored them.

``agent_id`` is the parent's ``runSubagent`` tool-call id; SubagentStart and
SubagentStop carry the same value (probe of 2026-10-22, #101).

Every failure on either side yields no record or an empty list, which the stop
gate reads as "subtract nothing" -- the behaviour before this module existed.
Stdlib only, like every hook core here.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import time
from pathlib import Path
from urllib.parse import unquote, urlparse

PRODUCERS = frozenset({"test-writer", "implementer", "refactorer"})
# The id becomes a file name; one carrying a path must not.
AGENT_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")
STORE = Path(".github") / "logs" / "subagent-baseline"
KEEP_SECONDS = 7 * 24 * 3600
GIT_TIMEOUT = 10


def git(repo: Path, *args: str, stdin: str | None = None) -> str | None:
    try:
        out = subprocess.run(
            ["git", "-C", str(repo), *args],
            input=stdin,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=GIT_TIMEOUT,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return out.stdout if out.returncode == 0 else None


def repo_key(path: Path) -> str | None:
    """The record key of the repository containing ``path``: its normalised toplevel."""
    if not path.is_dir():
        return None
    out = git(path, "rev-parse", "--show-toplevel")
    if not out or not out.strip():
        return None
    return os.path.normcase(str(Path(out.strip()).resolve()))


def workspace_folders(transcript: str) -> list[Path]:
    """Folders of the multi-root workspace this session runs in, if it has a workspace file.

    ``<workspaceStorage>/<hash>/workspace.json`` names the ``.code-workspace``
    file; a single-folder window names a ``folder`` instead and adds nothing.
    """
    if not transcript:
        return []
    try:
        meta = json.loads((Path(transcript).parents[2] / "workspace.json").read_text(encoding="utf-8"))
        uri = urlparse(str(meta.get("workspace") or ""))
        if uri.scheme != "file":
            return []
        local = unquote(uri.path)
        if os.name == "nt":
            local = local.lstrip("/")
        ws_file = Path(local)
        text = ws_file.read_text(encoding="utf-8")
    except (OSError, ValueError, IndexError, AttributeError):
        return []
    # A .code-workspace is JSONC; only the folder paths are wanted.
    folders = []
    for raw in re.findall(r'"path"\s*:\s*"((?:[^"\\]|\\.)*)"', text):
        try:
            folder = Path(json.loads(f'"{raw}"'))
        except ValueError:
            continue
        folders.append(folder if folder.is_absolute() else ws_file.parent / folder)
    return folders


def hashes(repo: Path, paths: list[str]) -> dict[str, str | None] | None:
    """Blob hash of each path's current content; None for a path that is not a file."""
    present = [p for p in paths if (repo / p).is_file()]
    out = git(repo, "hash-object", "--stdin-paths", stdin="\n".join(present) + "\n") if present else ""
    if out is None:
        return None
    values = out.split()
    if len(values) != len(present):
        return None
    result: dict[str, str | None] = dict.fromkeys(paths)
    result.update(zip(present, values, strict=True))
    return result


def snapshot(repo: Path) -> dict | None:
    """HEAD plus every dirty path with the blob hash of its content."""
    head = git(repo, "rev-parse", "HEAD")
    status = git(repo, "status", "--porcelain=v1", "-z", "--untracked-files=all")
    if head is None or status is None:
        return None
    paths: list[str] = []
    entries = status.split("\0")
    i = 0
    while i < len(entries):
        entry = entries[i]
        i += 1
        if len(entry) < 4:
            continue
        paths.append(entry[3:])
        if entry[0] in "RC":
            i += 1  # with -z the rename source follows as its own field
    dirty = hashes(repo, paths)
    if dirty is None:
        return None
    return {"head": head.strip(), "dirty": dirty}


def prune(store: Path, now: float) -> None:
    for old in store.glob("*.json"):
        try:
            if now - old.stat().st_mtime > KEEP_SECONDS:
                old.unlink()
        except OSError:
            pass


def write_baseline(payload: dict, root: Path, extra_roots: list[Path]) -> Path | None:
    """Write the baseline for a producer's SubagentStart payload; the record path, or None."""
    agent_id = str(payload.get("agent_id") or "")
    if payload.get("agent_type") not in PRODUCERS or not AGENT_ID.fullmatch(agent_id):
        return None
    candidates = [root, *extra_roots, *workspace_folders(str(payload.get("transcript_path") or ""))]
    repos: dict[str, dict] = {}
    for candidate in candidates:
        key = repo_key(candidate)
        if key is None or key in repos:
            continue
        shot = snapshot(Path(key))
        if shot is not None:
            repos[key] = shot
    if not repos:
        return None
    store = root / STORE
    store.mkdir(parents=True, exist_ok=True)
    now = time.time()
    prune(store, now)
    body = {"agent_id": agent_id, "agent_type": payload.get("agent_type"), "taken": now, "repos": repos}
    target = store / f"{agent_id}.json"
    tmp = store / f"{agent_id}.json.tmp"
    tmp.write_text(json.dumps(body), encoding="utf-8")
    os.replace(tmp, target)
    return target


def untouched(store: Path, agent_id: str, repo_root: Path) -> list[str]:
    """Paths dirty when ``agent_id`` started whose content is still unchanged.

    Empty whenever it cannot be shown: no record, the repository not in it, or
    HEAD moved (a commit in between makes the dirty sets incomparable).
    """
    if not AGENT_ID.fullmatch(agent_id):
        return []
    try:
        body = json.loads((store / f"{agent_id}.json").read_text(encoding="utf-8"))
        key = repo_key(repo_root)
        shot = body["repos"][key] if key else None
        if not isinstance(shot, dict) or not isinstance(shot.get("dirty"), dict):
            return []
        head = git(Path(key), "rev-parse", "HEAD")
        if head is None or head.strip() != shot.get("head"):
            return []
        before: dict = shot["dirty"]
        now = hashes(Path(key), list(before))
    except (OSError, ValueError, KeyError, TypeError):
        return []
    if now is None:
        return []
    return sorted(p for p, h in before.items() if now.get(p) == h)
