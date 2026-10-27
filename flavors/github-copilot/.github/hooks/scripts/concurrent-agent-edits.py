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

The caller's own log is `runSubagent-{agent}-{agent_id}.jsonl` when the stop
payload's `agent_id` is passed (`--agent-id`); the id in the file name is the
payload's (probe of 2026-10-22). Without it, or when no such file exists, the
fallback is the heuristic it replaced: the most recently modified
`runSubagent-{agent}-*.jsonl`, which two parallel invocations of the SAME agent
defeat -- degrading to subtracting less.

THE SEQUENTIAL CASE. Peer logs cannot see an earlier producer's output that is
still uncommitted: it did not overlap. `--baseline-dir` adds the files that were
dirty when this invocation started and are still byte-identical (`_baseline`,
written by the SubagentStart hook). Same failure direction: no record, no
subtraction.

Stdlib only, on purpose -- a gate that needs `pip install` stops being run.

Usage:
    concurrent-agent-edits.py --session-dir <dir> --agent <name>
                              [--repo-root <path>] [--agent-id <id>]
                              [--baseline-dir <dir>]

Output:
    Repo-relative POSIX paths, one per line -- files a concurrent peer agent
    edited and the caller did not, plus files untouched since the caller
    started.

Exit codes:
    0  a list was emitted (possibly empty -- nothing to subtract)
    1  nothing measurable (no session dir, or no log for this agent)
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from _agentlog import find_own_log, scan_edits
from _baseline import untouched


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
    parser.add_argument("--agent-id", default="")
    parser.add_argument("--baseline-dir", default="")
    args = parser.parse_args()

    unchanged: list[str] = []
    if args.agent_id and args.baseline_dir:
        unchanged = untouched(Path(args.baseline_dir), args.agent_id, Path(args.repo_root))

    try:
        names = [n for n in os.listdir(args.session_dir) if n.startswith("runSubagent-") and n.endswith(".jsonl")]
    except OSError:
        names = []

    own = find_own_log(args.session_dir, args.agent, args.agent_id) if names else None
    mine = os.path.basename(own) if own else None
    if mine is None:
        for path in unchanged:
            print(path)
        return 0 if unchanged else 1

    my_start, my_end, my_edits = scan_edits(os.path.join(args.session_dir, mine))

    peer_edits: set[str] = set()
    for name in names:
        if name == mine:
            continue
        start, end, edited = scan_edits(os.path.join(args.session_dir, name))
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
        if os.path.normcase(os.path.abspath(p)) not in {os.path.normcase(os.path.abspath(m)) for m in my_edits}
    }

    for path in sorted(set(relativise(exclusive, args.repo_root)) | set(unchanged)):
        print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
