"""Foreign-work guard (#120): protect changes that were already uncommitted when a session started.

A path that is dirty at session start was authored by nobody in this session, so a
session discarding it is discarding someone else's work. Git keeps no copy of
uncommitted changes; the one real loss behind #120 left nothing to recover.

Two commands, one module, so the PowerShell and bash hooks cannot disagree:

  record <root>   SessionStart. Writes the baseline for AF_FG_SESSION under
                  .github/logs/, and first reports dirty paths of the previous
                  baseline that went clean without any commit touching them.
                  Prints that report (or nothing).
  check <root>    PreToolUse. Reads AF_FG_COMMAND and AF_FG_SESSION. If a git
                  command would discard a baseline path, prints an `ask` verdict
                  naming the files; otherwise prints nothing.

The command arrives through the environment, not argv: Windows PowerShell 5.1
mangles embedded quotes in native-command arguments. Every failure prints
nothing, so a broken guard degrades to the classifier it sits in front of and
never blocks on its own missing state.
"""

from __future__ import annotations

import fnmatch
import json
import os
import shlex
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

FG_PREFIX = ".worktree-baseline-"
FG_KEEP = 10
FG_SHOWN = 8


def fg_git(root: Path, *args: str) -> str:
    out = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True, encoding="utf-8")
    return out.stdout if out.returncode == 0 else ""


def fg_dirty(root: Path) -> list[tuple[str, str]]:
    """(status, path) of every uncommitted path, logs excluded: the baseline must not record itself."""
    rows = []
    for line in fg_git(root, "status", "--porcelain", "--untracked-files=all").splitlines():
        if len(line) < 4:
            continue
        status, path = line[:2], line[3:]
        if " -> " in path:
            path = path.split(" -> ", 1)[1]
        path = path.strip('"')
        if not path.startswith(".github/logs/"):
            rows.append((status, path))
    return rows


def fg_logs(root: Path) -> Path:
    logs = root / ".github" / "logs"
    logs.mkdir(parents=True, exist_ok=True)
    ignore = logs / ".gitignore"
    if not ignore.exists():
        ignore.write_text("*\n", encoding="utf-8")
    return logs


def fg_safe_id(session: str) -> str:
    return "".join(c for c in session if c.isalnum() or c in "-_")[:80] or "shared"


def fg_read(path: Path) -> tuple[str, str, list[tuple[str, str]]]:
    created, head, rows = "", "", []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("# created "):
            created = line[len("# created ") :].strip()
        elif line.startswith("# head "):
            head = line[len("# head ") :].strip()
        elif "\t" in line:
            status, p = line.split("\t", 1)
            rows.append((status, p))
    return created, head, rows


def fg_committed_since(root: Path, created: str, head: str, path: str) -> bool:
    # By commit range, not by time: a commit made in the baseline's own second read as later (PR #389 CI).
    if head and fg_git(root, "cat-file", "-t", head).strip() == "commit":
        return bool(fg_git(root, "log", "--format=%H", f"{head}..HEAD", "--", path).strip())
    if head == "none":
        return bool(fg_git(root, "log", "--format=%H", "HEAD", "--", path).strip())
    return bool(created and fg_git(root, "log", f"--since={created}", "--format=%H", "--", path).strip())


def fg_record(root: Path, session: str) -> str:
    logs = fg_logs(root)
    previous = sorted(logs.glob(FG_PREFIX + "*"), key=lambda p: p.stat().st_mtime)
    report = ""
    if previous:
        created, head, rows = fg_read(previous[-1])
        now_dirty = {p for _, p in fg_dirty(root)}
        lost = [p for _, p in rows if p not in now_dirty and not fg_committed_since(root, created, head, p)]
        if lost:
            shown = ", ".join(lost[:FG_SHOWN]) + (f" (+{len(lost) - FG_SHOWN} more)" if len(lost) > FG_SHOWN else "")
            report = (
                f"AF WARNING: {len(lost)} path(s) that were uncommitted when the previous session started "
                f"are clean now and no commit since then touched them -- their changes may have been "
                f"discarded: {shown}. Check with the human before assuming they were intended (#120)."
            )
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    head = fg_git(root, "rev-parse", "--verify", "-q", "HEAD").strip() or "none"
    lines = [f"# created {stamp}", f"# head {head}"] + [f"{s}\t{p}" for s, p in fg_dirty(root)]
    target = logs / (FG_PREFIX + fg_safe_id(session))
    target.write_text("\n".join(lines) + "\n", encoding="utf-8")
    for old in sorted(logs.glob(FG_PREFIX + "*"), key=lambda p: p.stat().st_mtime)[:-FG_KEEP]:
        old.unlink(missing_ok=True)
    return report


def fg_segments(command: str) -> list[str]:
    out, cur, quote, i = [], [], "", 0
    while i < len(command):
        c = command[i]
        if quote:
            cur.append(c)
            quote = "" if c == quote else quote
        elif c in "\"'":
            quote = c
            cur.append(c)
        elif command[i : i + 2] in ("&&", "||"):
            out.append("".join(cur))
            cur = []
            i += 1
        elif c in ";|\n":
            out.append("".join(cur))
            cur = []
        else:
            cur.append(c)
        i += 1
    out.append("".join(cur))
    return [s.strip() for s in out if s.strip()]


def fg_tokens(segment: str) -> list[str]:
    try:
        return shlex.split(segment, posix=True)
    except ValueError:
        return segment.split()


ALL = "*ALL*"


def fg_targets(tokens: list[str]) -> tuple[str | None, list[str]]:
    """(git -C dir or None, pathspecs this git call would discard; [ALL] for everything; [] for nothing)."""
    i = 0
    while (
        i < len(tokens)
        and tokens[i].lower() not in ("git", "git.exe")
        and not tokens[i].lower().endswith(("/git", "\\git", "/git.exe", "\\git.exe"))
    ):
        i += 1
    if i >= len(tokens):
        return None, []
    i += 1
    cdir = None
    while i < len(tokens) and tokens[i].startswith("-"):
        if tokens[i] == "-C" and i + 1 < len(tokens):
            cdir = tokens[i + 1]
            i += 2
        elif tokens[i] == "-c" and i + 1 < len(tokens):
            i += 2
        else:
            i += 1
    if i >= len(tokens):
        return cdir, []
    sub, rest = tokens[i], tokens[i + 1 :]
    after_dd = rest[rest.index("--") + 1 :] if "--" in rest else None
    plain = [t for t in (rest[: rest.index("--")] if "--" in rest else rest) if not t.startswith("-")]
    flags = [t for t in rest if t.startswith("-")]

    if sub == "restore":
        if any(f in ("--staged", "-S") for f in flags) and not any(f in ("--worktree", "-W") for f in flags):
            return cdir, []
        skip = {rest[k + 1] for k, t in enumerate(rest) if t in ("-s", "--source") and k + 1 < len(rest)}
        specs = after_dd if after_dd is not None else [t for t in plain if t not in skip]
        return cdir, specs or []
    if sub == "checkout":
        if any(f in ("-f", "--force") for f in flags):
            return cdir, [ALL]
        if after_dd is not None:
            return cdir, after_dd or [ALL]
        return cdir, plain  # a branch name matches no baseline path, so it never asks
    if sub == "switch":
        if any(f in ("-f", "--force", "--discard-changes") for f in flags):
            return cdir, [ALL]
        return cdir, []
    if sub == "stash":
        verb = plain[0] if plain else "push"
        if verb in ("list", "show", "apply", "pop", "branch", "drop", "clear", "create", "store"):
            return cdir, []
        specs = after_dd if after_dd is not None else [t for t in plain[1:] if verb in ("push", "save")]
        return cdir, specs or [ALL]
    if sub == "clean":
        if any(f in ("-n", "--dry-run") or (f.startswith("-") and not f.startswith("--") and "n" in f) for f in flags):
            return cdir, []
        return cdir, (after_dd if after_dd is not None else plain) or [ALL]
    return cdir, []


def fg_hits(root: Path, base: Path, specs: list[str], rows: list[tuple[str, str]], untracked_only: bool) -> list[str]:
    candidates = [p for s, p in rows if (s == "??") or not untracked_only]
    if ALL in specs or any(s in (".", "*", ":/", "./") for s in specs):
        return candidates
    hits = []
    for spec in specs:
        rel = spec.replace("\\", "/")
        if not rel.startswith(":/"):
            try:
                rel = (base / rel).resolve().relative_to(root.resolve()).as_posix()
            except ValueError:
                continue
        else:
            rel = rel[2:]
        rel = rel.rstrip("/")
        for p in candidates:
            if p == rel or p.startswith(rel + "/") or fnmatch.fnmatch(p, rel):
                hits.append(p)
    return sorted(set(hits))


def fg_check(root: Path, session: str, command: str) -> str:
    baseline = root / ".github" / "logs" / (FG_PREFIX + fg_safe_id(session))
    if not baseline.is_file():
        return ""
    _, _, rows = fg_read(baseline)
    if not rows:
        return ""
    found: list[str] = []
    for segment in fg_segments(command):
        tokens = fg_tokens(segment)
        cdir, specs = fg_targets(tokens)
        if not specs:
            continue
        base = root
        if cdir:
            base = Path(cdir) if Path(cdir).is_absolute() else root / cdir
            try:
                base.resolve().relative_to(root.resolve())
            except ValueError:
                continue
        sub = next((t for t in tokens if t in ("restore", "checkout", "switch", "stash", "clean")), "")
        found += fg_hits(root, base, specs, rows, untracked_only=(sub == "clean"))
    found = sorted(set(found))
    if not found:
        return ""
    shown = ", ".join(found[:FG_SHOWN]) + (f" (+{len(found) - FG_SHOWN} more)" if len(found) > FG_SHOWN else "")
    reason = (
        f"Foreign work: this would discard uncommitted changes to {len(found)} path(s) that were already "
        f"modified when this session started, so no agent in this session authored them: {shown}. "
        f"Git keeps no copy of uncommitted changes. Commit them, stash them under an explicit name, or confirm "
        f"that discarding them is intended (#120). Command: {command.strip()[:300]}"
    )
    return json.dumps(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "ask",
                "permissionDecisionReason": reason,
            }
        }
    )


def fg_main(argv: list[str]) -> int:
    try:
        if len(argv) < 3:
            return 0
        root = Path(argv[2])
        session = os.environ.get("AF_FG_SESSION", "") or "shared"
        if argv[1] == "record":
            out = fg_record(root, session)
        elif argv[1] == "check":
            out = fg_check(root, session, os.environ.get("AF_FG_COMMAND", ""))
        else:
            return 0
        if out:
            sys.stdout.write(out)
    except Exception:  # a broken guard degrades, it never blocks on its own failure
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(fg_main(sys.argv))
