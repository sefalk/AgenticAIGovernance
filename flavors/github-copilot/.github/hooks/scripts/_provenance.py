"""Shared provenance-marker detector for hooks written in Python.

The third dialect of one rule. `Test-AfProvenanceMarker` in `_common.ps1` and
`af_has_provenance_marker` in `_common.sh` already exist so that no gate
carries its own copy of the marker pattern -- issue #69 was a detector nobody
called, and the guard in `test-hooks` now checks that every gate asks the
shared one rather than grepping for `copilot:` itself.

As gate logic moves out of the shells and into Python cores (issue #287), that
guard needs something to point at on the Python side. This is it. It is
deliberately a separate module from `_agentlog`: that one is the reading
surface for subagent logs, and a marker detector is not a log reader.

A script in this directory imports it with a plain `import _provenance`,
because Python puts the script's own directory on `sys.path[0]`.
"""

from __future__ import annotations

import re

ANY_MARKER = re.compile(r"copilot:(generated|modified)")
GENERATED_MARKER = re.compile(r"copilot:generated")

DETAIL = (
    "No copilot:generated or copilot:modified marker found anywhere in this file. "
    "If this file was created or substantially modified by an agent, add a provenance marker. "
    "See instructions/provenance.instructions.md."
)


def has_provenance_marker(text: str | None, kind: str = "any") -> bool:
    """Whether file contents carry a Copilot provenance marker anywhere.

    `kind='generated'` accepts only `copilot:generated`; test-writer's gate is
    about authorship of a *new* file, so `copilot:modified` must not satisfy
    it. Contents of ``None`` -- an unreadable or binary file -- count as
    unmarked rather than raising: a gate must not turn a file it cannot read
    into a crash.
    """
    if not text:
        return False
    pattern = GENERATED_MARKER if kind == "generated" else ANY_MARKER
    return bool(pattern.search(text))
