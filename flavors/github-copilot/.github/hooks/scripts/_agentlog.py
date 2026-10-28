"""Shared reading surface for the hooks that consume subagent logs.

Issue #291. Four readers had grown their own copy of the same code —
`collect-agent-invocations.py`, `concurrent-agent-edits.py`,
`subagent-return.py` and `undeclared-scratch.py`. Three of them carried a
comment explaining that the duplication was deliberate: these scripts have
hyphenated filenames and cannot be imported as modules, so copying was the
cheaper correct answer. The fourth carried no such comment, which is how it
went unnoticed — the only way to find the copies was to grep for the note
admitting to them.

This module has an importable name. A script in this directory reaches it with
a plain `import _agentlog`, because Python puts the script's own directory on
`sys.path[0]` when it is run as `python .../hooks/scripts/foo.py`, which is how
every hook here is invoked.

Two tiers live here, and they have different audiences. Keeping them in one
module is deliberate — a second module for two importers would trade one
duplication for one indirection — but the split is real and worth stating:

  log identification  SUBAGENT, agent_from, find_own_log   all four readers
  payload harvesting  TOOL_CALL_HINT, PATH_KEYS,           two of the four
                      harvest_paths
  edit scan           is_edit_tool, scan_edits             concurrent-agent-edits,
                                                           repo-gates
"""

from __future__ import annotations

import json
import os
import re

# `runSubagent-ado-pr-manager-toolu_011DEuS1yqmhJkPQa1qmtY3U.jsonl`
# The agent name itself contains hyphens, so the split is on the LAST one:
# the trailing segment is the tool-call id (observed 2026-08-21: `toolu_` plus
# alphanumerics, no hyphen). A future id format carrying hyphens would move the
# boundary, which is why a non-matching name falls back to the whole stem
# rather than being dropped -- an unparsed name must not become a silent zero.
SUBAGENT = re.compile(r"^runSubagent-(?P<agent>.+)-(?P<call>[^-]+)\.jsonl$")

# Cheap prefilter so a 20 MB log is not JSON-parsed line by line. The optional
# whitespace in the sibling patterns is not decoration: the editor writes
# compact JSON, but a log rewritten by any pretty-printer would carry
# `"ts": 123`, and an anchored pattern silently found no timestamps at all.
TOOL_CALL_HINT = b'"tool_call"'

# Where write payloads keep their paths, mirroring `Get-AfWritePaths` in
# `_common`. `multi_replace_string_in_file` keeps none at the top level -- its
# paths sit in `replacements[].filePath`, which the recursive walk reaches.
PATH_KEYS = frozenset({"filePath", "path", "dirPath", "notebookUri", "uri"})

TS = re.compile(rb'"ts":\s*(\d+)')

# Allowlist, not a denylist. `read_file` and `grep_search` also carry a
# `filePath`, and harvesting those would attribute files nobody wrote.
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


def is_edit_tool(name: object) -> bool:
    if not isinstance(name, str) or not name:
        return False
    if name in EDIT_TOOLS:
        return True
    return bool(EDIT_VERB.search(name) and EDIT_NOUN.search(name))


def scan_edits(path: str) -> tuple[int | None, int | None, set[str]]:
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


def agent_from(filename: str) -> str:
    """The agent name encoded in a `runSubagent-*.jsonl` filename."""
    match = SUBAGENT.match(filename)
    if match:
        return match.group("agent")
    return filename[len("runSubagent-") : -len(".jsonl")]


def find_own_log(session_dir: str, agent: str, agent_id: str = "") -> str | None:
    """The caller's own log: `runSubagent-{agent}-{agent_id}.jsonl`, else the newest for this agent.

    The stop payload's `agent_id` is the id in the file name (probe of
    2026-10-22, #101), so with it the match is exact. Without it, a Stop hook
    runs as its own invocation finishes, so that log is the one still being
    written. Two invocations of the same agent in parallel would defeat the
    heuristic; the consequence is reading a sibling's prompt and file list
    together, which stays self-consistent.
    """
    if agent_id:
        exact = os.path.join(session_dir, f"runSubagent-{agent}-{agent_id}.jsonl")
        if os.path.isfile(exact):
            return exact
    try:
        names = os.listdir(session_dir)
    except OSError:
        return None
    newest: str | None = None
    newest_mtime = -1.0
    for name in names:
        if not name.startswith("runSubagent-") or not name.endswith(".jsonl"):
            continue
        if agent_from(name) != agent:
            continue
        full = os.path.join(session_dir, name)
        try:
            mtime = os.path.getmtime(full)
        except OSError:
            continue
        if mtime > newest_mtime:
            newest_mtime = mtime
            newest = full
    return newest


def harvest_paths(value: object, into: set[str]) -> None:
    """Collect every path string anywhere inside a tool call's args.

    Recursive rather than shape-specific: `replace_string_in_file` puts the
    path at the top level, `multi_replace_string_in_file` nests one per entry
    of `replacements`, and a tool added later may nest it somewhere else again.
    Only ever called for tools the caller has already classified as writing.
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
