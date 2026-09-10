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
"""

from __future__ import annotations

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


def agent_from(filename: str) -> str:
    """The agent name encoded in a `runSubagent-*.jsonl` filename."""
    match = SUBAGENT.match(filename)
    if match:
        return match.group("agent")
    return filename[len("runSubagent-") : -len(".jsonl")]


def find_own_log(session_dir: str, agent: str) -> str | None:
    """The caller's own log: the most recently modified one for this agent.

    A Stop hook runs as its own invocation finishes, so that log is the one
    still being written. Two invocations of the same agent in parallel would
    defeat the heuristic; the consequence is reading a sibling's prompt and
    file list together, which stays self-consistent.
    """
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
