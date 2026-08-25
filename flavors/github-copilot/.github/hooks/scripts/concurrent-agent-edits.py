#!/usr/bin/env python3
"""Report files edited by a *different* subagent running at the same time.

Issue #101. `coordinator.agent.md` sanctions running producer subagents in
parallel, but every producer stop-hook gate derives its file scope from shared
git state (`git diff` against the index / `HEAD` / `merge-base`), which is
global to the checkout. Two producers on one branch therefore see each other's
in-flight edits. The observed consequence was not a warning: the implementer's
docstring gate demanded work on the refactorer's file, the implementer complied
-- it had no way to know the file was not its own -- and the provenance gate
then made it stamp an authorship marker recording the wrong agent.

The editor already writes one `runSubagent-{agent}-{toolcallid}.jsonl` per
subagent invocation, and each edit tool call appears in it as a `tool_call`
span carrying the file path it wrote. That is a per-invocation, per-agent,
machine-written record of who touched what, and it never passes through a
model -- the same channel and the same principle as `collect-agent-invocations`
(issue #173): a value a model can get wrong should be measured, not requested.

WHY SUBTRACTION RATHER THAN INTERSECTION. Scoping a gate to "the files my own
log says I edited" would be the tighter rule, but it fails dangerously: if a
future editor renames an edit tool, this script stops recognising the call, the
scope collapses to empty, and every gate silently passes. Subtracting only what
a *peer* log positively claims inverts that. Every failure mode -- no session
directory, an unreadable log, an unrecognised tool name, a peer that never
overlapped -- subtracts less, and subtracting less lands exactly on today's
behaviour. The gate can lose the fix; it cannot lose its teeth.

For the same reason nothing here blocks and nothing here reports an error: a
watchdog that fails a legitimate workflow gets switched off, and a hook nobody
runs protects nothing (issue #108).

WHAT THIS IS NOT. Peers are matched by *time overlap* within one chat session.
A workflow spanning several sessions sees only the session it is running in,
and a peer whose log the editor has not yet flushed is invisible. Both cases
subtract nothing, which is the safe direction. A file the peer edited and the
caller edited too is NOT subtracted -- shared authorship is real authorship,
and the caller must still answer for it.

Identifying the caller's own log is a heuristic: the most recently modified
`runSubagent-{agent}-*.jsonl`. A Stop hook runs as its own invocation finishes,
so that log is the one still being written. Two invocations of the SAME agent
in parallel would defeat it; the reported incident is implementer against
refactorer, and the misidentification degrades to subtracting less.

Stdlib only, on purpose -- a gate that needs `pip install` stops being run.

Usage:
    concurrent-agent-edits.py --session-dir <dir> --agent <name>
                              [--repo-root <path>]

Output:
    Repo-relative POSIX paths, one per line -- files a concurrent peer agent
    edited and the caller did not.

Exit codes:
    0  a list was emitted (possibly empty -- nothing to subtract)
    1  nothing measurable (no session dir, or no log for this agent)
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

# Same shape as `collect-agent-invocations.py`: the agent name itself contains
# hyphens, so the split is on the LAST one. Duplicated rather than imported --
# the filename carries a hyphen and is not importable as a module.
SUBAGENT = re.compile(r"^runSubagent-(?P<agent>.+)-(?P<call>[^-]+)\.jsonl$")

# Cheap prefilter so a 20 MB log is not JSON-parsed line by line. The optional
# whitespace is not decoration: the editor writes compact JSON, but a log
# rewritten by any pretty-printer would carry `"ts": 123`, and an anchored
# pattern silently found no timestamps at all.
TS = re.compile(rb'"ts":\s*(\d+)')
TOOL_CALL_HINT = b'"tool_call"'

# Allowlist, not a denylist. `read_file` and `grep_search` also carry a
# `filePath`, and harvesting those would subtract files nobody wrote.
#
# Deliberately the same rule as `Test-AfWriteTool` in `_common` rather than a
# second, narrower one: those names were read out of captured PreToolUse
# payloads instead of tool documentation (issue #69), and two lists of write
# tools in one hook directory would drift apart the first time a client added
# a tool. The trailing heuristic covers a tool that does not exist yet -- a
# writing verb plus a file noun. `read_file` carries no verb and
# `create_and_run_task` no file noun, so neither is caught.
EDIT_TOOLS = frozenset(
    {
        "create_file",
        "replace_string_in_file",
        "multi_replace_string_in_file",
        "create_directory",
        "edit_notebook_file",
        "create_new_jupyter_notebook",
        "insert_edit_into_file",
        "apply_patch",
        "editFiles",
        "editFile",
        "createFile",
        "createDirectory",
        "createDir",
        "editNotebook",
        "writeFile",
        "applyPatch",
        "insertEdit",
    }
)
EDIT_VERB = re.compile(r"create|write|edit|insert|apply|replace")
EDIT_NOUN = re.compile(r"file|notebook|dir")

# Where write payloads keep their paths, mirroring `Get-AfWritePaths`.
# `multi_replace_string_in_file` keeps none at the top level -- its paths sit
# in `replacements[].filePath`, which the recursive walk reaches.
PATH_KEYS = frozenset({"filePath", "path", "dirPath", "notebookUri", "uri"})


def is_edit_tool(name: object) -> bool:
    if not isinstance(name, str) or not name:
        return False
    if name in EDIT_TOOLS:
        return True
    return bool(EDIT_VERB.search(name) and EDIT_NOUN.search(name))


def agent_from(filename: str) -> str:
    match = SUBAGENT.match(filename)
    if match:
        return match.group("agent")
    return filename[len("runSubagent-") : -len(".jsonl")]


def harvest_paths(value: object, into: set[str]) -> None:
    """Collect every path string anywhere inside a tool call's args.

    Recursive rather than shape-specific: `replace_string_in_file` puts the
    path at the top level, `multi_replace_string_in_file` nests one per entry
    of `replacements`, and a tool added later may nest it somewhere else again.
    Only ever called for tools that passed `is_edit_tool`.
    """
    if isinstance(value, dict):
        for key, item in value.items():
            if key in PATH_KEYS and isinstance(item, str) and item:
                into.add(item)
            else:
                harvest_paths(item, into)
    elif isinstance(value, list):
        for item in value:
            harvest_paths(item, into)


def scan(path: str) -> tuple[int | None, int | None, set[str]]:
    """One pass over a subagent log: time span and files it edited."""
    first_ts: int | None = None
    last_ts: int | None = None
    edited: set[str] = set()
    try:
        with open(path, "rb") as handle:
            for raw in handle:
                stamp = TS.search(raw)
                if stamp:
                    value = int(stamp.group(1))
                    if first_ts is None or value < first_ts:
                        first_ts = value
                    if last_ts is None or value > last_ts:
                        last_ts = value
                if TOOL_CALL_HINT not in raw:
                    continue
                try:
                    span = json.loads(raw.decode("utf-8", "replace"))
                except (ValueError, UnicodeDecodeError):
                    continue
                if not isinstance(span, dict) or span.get("type") != "tool_call":
                    continue
                if not is_edit_tool(span.get("name")):
                    continue
                attrs = span.get("attrs")
                if not isinstance(attrs, dict):
                    continue
                args = attrs.get("args")
                if isinstance(args, str):
                    try:
                        args = json.loads(args)
                    except ValueError:
                        continue
                harvest_paths(args, edited)
    except OSError:
        return None, None, set()
    return first_ts, last_ts, edited


def overlaps(a: tuple[int | None, int | None], b: tuple[int | None, int | None]) -> bool:
    """True only when concurrency can be positively established.

    An unknown bound means "I could not read this log's clock", and that is
    answered with False rather than True. Treating it as an overlap would
    subtract a peer's files on no evidence, which weakens the caller's gate --
    the one direction this script must never fail in. Unreadable timestamps
    therefore subtract nothing and leave today's behaviour in place.
    """
    a_start, a_end = a
    b_start, b_end = b
    if a_start is None or a_end is None or b_start is None or b_end is None:
        return False
    return not (a_end < b_start or b_end < a_start)


def relativise(paths: set[str], repo_root: str) -> list[str]:
    """Repo-relative POSIX paths; anything outside the repo is dropped."""
    root = os.path.normcase(os.path.abspath(repo_root))
    out: set[str] = set()
    for raw in paths:
        absolute = os.path.normcase(os.path.abspath(raw))
        if absolute == root:
            continue
        if not absolute.startswith(root + os.sep):
            continue
        out.add(os.path.relpath(absolute, root).replace(os.sep, "/"))
    return sorted(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session-dir", required=True)
    parser.add_argument("--agent", required=True)
    parser.add_argument("--repo-root", default=".")
    args = parser.parse_args()

    try:
        names = [
            n
            for n in os.listdir(args.session_dir)
            if n.startswith("runSubagent-") and n.endswith(".jsonl")
        ]
    except OSError:
        return 1

    mine: str | None = None
    mine_mtime = -1.0
    for name in names:
        if agent_from(name) != args.agent:
            continue
        full = os.path.join(args.session_dir, name)
        try:
            mtime = os.path.getmtime(full)
        except OSError:
            continue
        if mtime > mine_mtime:
            mine_mtime = mtime
            mine = name
    if mine is None:
        return 1

    my_start, my_end, my_edits = scan(os.path.join(args.session_dir, mine))

    peer_edits: set[str] = set()
    for name in names:
        if name == mine:
            continue
        start, end, edited = scan(os.path.join(args.session_dir, name))
        if not edited:
            continue
        if not overlaps((my_start, my_end), (start, end)):
            continue
        peer_edits |= edited

    # Shared authorship is real authorship: a file the caller also edited stays
    # in its own scope.
    exclusive = {
        p
        for p in peer_edits
        if os.path.normcase(os.path.abspath(p))
        not in {os.path.normcase(os.path.abspath(m)) for m in my_edits}
    }

    for path in relativise(exclusive, args.repo_root):
        print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
