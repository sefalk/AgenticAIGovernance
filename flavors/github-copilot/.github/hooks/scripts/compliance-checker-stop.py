#!/usr/bin/env python3
"""Did the compliance-checker read what it quotes? (issue #286)

#174 recorded a post-flight report that quoted a retro which did not say that,
and stated an `af-env.conf` value the file did not hold -- both produced in a
turn that read nothing. The agent file now forbids it; this is the mechanical
half that #174 left open, run from the compliance-checker's SubagentStop hook.

WHAT IS CHECKED, AND WHY ONLY THIS. Measured 2026-10-19 over 88 real
compliance-checker logs (comment on #286):

  * A -- the return cites `{path}:{line}` and the turn made **no** `read_file`
    call at all: 0 of 88. It decides on the absence of evidence, which survives
    the editor's 5000-character truncation of the return, and it is the #174
    failure exactly. This one blocks.
  * B -- a cited path appears in no `read_file` call: 5 of 88, and at least 4
    of those were false (URL-encoded names, a file read through
    `grep_search`, instruction files already in context). So B never blocks;
    it is reported as advisory, after URL-decoding.

The return text comes from `subagent-return.py`, so its honesty statuses carry
through: `empty` or `unavailable` means there is nothing to judge, which is
reported as "not measurable" -- never pass, never fail (#251, #138).

This is the core of the compliance-checker-stop twin pair (#287): the `.ps1`
and `.sh` wrappers only resolve the interpreter and pass stdin through.

Stdlib only, on purpose -- a gate that needs `pip install` stops being run.

Input:   the SubagentStop hook payload on stdin (`session_id`,
         `transcript_path`, `stop_hook_active`).
Output:  one JSON object -- a `block` decision on check A, otherwise a
         `systemMessage` (PASS with any check-B advisory, or not measurable).
Exit:    always 0; a hook must never fail the agent for its own blind spot.
"""

from __future__ import annotations

import importlib.util
import json
import os
import re
import sys
from urllib.parse import unquote

from _agentlog import TOOL_CALL_HINT, find_own_log

AGENT = "compliance-checker"

# `{path}:{line}` or `{path}#L{line}` with a file extension -- the citation
# shape the agent file mandates. A bare word with a colon is not a citation.
CITATION = re.compile(r"([\w./\\%-]+\.[A-Za-z0-9]{1,6})(?::|#L)(\d+)")

# The compliance-checker's only file-reading tool (`read/readFile`). The
# camel-case alias covers a renamed tool id; a new reading tool would have to
# be added here deliberately rather than be guessed from its name.
READ_TOOLS = frozenset({"read_file", "readFile"})


def _return_reader():
    """`subagent-return.py` as a module -- its hyphenated name blocks `import`."""
    here = os.path.dirname(os.path.abspath(__file__))
    spec = importlib.util.spec_from_file_location("subagent_return", os.path.join(here, "subagent-return.py"))
    if spec is None or spec.loader is None:
        return None
    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
    except (OSError, ImportError, SyntaxError):
        return None
    return module


def _name(path: str) -> str:
    """Compare on the decoded, lower-cased file name: the agent cites what it
    saw, and the measured false findings were spelling, not absence."""
    return os.path.basename(unquote(path).replace("\\", "/")).lower()


def reads_in(log: str) -> tuple[int, set[str]]:
    """Number of `read_file` calls in the turn, and the names they read."""
    count = 0
    names: set[str] = set()
    try:
        with open(log, "rb") as handle:
            for raw in handle:
                if TOOL_CALL_HINT not in raw:
                    continue
                try:
                    span = json.loads(raw.decode("utf-8", "replace"))
                except (ValueError, UnicodeDecodeError):
                    continue
                if not isinstance(span, dict) or span.get("type") != "tool_call":
                    continue
                if span.get("name") not in READ_TOOLS:
                    continue
                count += 1
                attrs = span.get("attrs")
                args = attrs.get("args") if isinstance(attrs, dict) else None
                if isinstance(args, str):
                    try:
                        args = json.loads(args)
                    except ValueError:
                        args = None
                if isinstance(args, dict) and isinstance(args.get("filePath"), str):
                    names.add(_name(args["filePath"]))
    except OSError:
        return 0, set()
    return count, names


def citations(text: str) -> set[str]:
    return {_name(m.group(1)) for m in CITATION.finditer(text)}


def judge(session_dir: str, agent: str = AGENT) -> tuple[str, list[str]]:
    """(`pass` | `fail` | `unavailable`, names) for the newest log of `agent`."""
    reader = _return_reader()
    log = find_own_log(session_dir, agent)
    if reader is None or log is None:
        return "unavailable", []
    status, text = reader.classify(reader.last_response(log))
    if status not in (reader.COMPLETE, reader.TRUNCATED):
        return "unavailable", []
    cited = citations(text)
    read_count, read_names = reads_in(log)
    if cited and read_count == 0:
        return "fail", sorted(cited)
    return "pass", sorted(cited - read_names)


def _message(text: str) -> str:
    return json.dumps({"systemMessage": f"compliance-checker:Stop -- {text}"})


def _unmeasured(why: str) -> str:
    return _message(f"read check not measurable ({why}); a report's quotations are unverified, not verified")


def verdict(payload: dict) -> str:
    """The hook's JSON output for one SubagentStop payload."""
    if payload.get("stop_hook_active") is True:
        # The retry a block demanded must not be blocked again (#298).
        return _message("read check already reported on the first stop; not re-blocking the retry")
    sid = payload.get("session_id")
    transcript = payload.get("transcript_path")
    if not isinstance(sid, str) or not isinstance(transcript, str) or not sid or not transcript:
        return _unmeasured("no session in hook input")
    # <ws>/GitHub.copilot-chat/transcripts/<sid>.jsonl -> .../debug-logs/<sid>
    session_dir = os.path.join(os.path.dirname(os.path.dirname(transcript)), "debug-logs", sid)
    if not os.path.isdir(session_dir):
        return _unmeasured("no debug log for this session")
    status, names = judge(session_dir)
    if status == "fail":
        reason = (
            f"Your report quotes file content ({', '.join(names)}) but this turn made no read_file call. "
            "A quotation without a read is not evidence (#174, #286). "
            "Read each file you cite and quote what it says, or remove the citation."
        )
        return json.dumps({"hookSpecificOutput": {"hookEventName": "Stop", "decision": "block", "reason": reason}})
    if status == "pass":
        note = f" -- ADVISORY: cited but not read via read_file: {', '.join(names)}" if names else ""
        return _message(f"read check PASS{note}")
    return _unmeasured("no readable return")


def main() -> int:
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        payload = {}
    print(verdict(payload if isinstance(payload, dict) else {}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
