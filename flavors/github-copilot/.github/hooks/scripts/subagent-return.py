#!/usr/bin/env python3
"""Read the caller's own final return text, with an explicit honesty status.

Issue #285, split out of #134. A Stop hook can see what its agent just said:
each turn writes an `agent_response` record into
`debug-logs/<sid>/runSubagent-{agent}-{toolcallid}.jsonl`, and it lands 6 ms
before the hook runs -- measured 2026-09-04, recorded on #134.

WHY A STATUS RATHER THAN A STRING. The editor caps `attrs.response` at 5000
characters and appends a literal `[truncated]`. Measured over 300 real logs:
231 complete, 68 truncated -- roughly a quarter of returns lose their tail, and
the tail is exactly where the mandated `### Gate Summary` sits. A caller handed
a bare string cannot tell a whole return from a beheaded one, because both are
non-empty and both look fine. So the status is the product here; the text is
the by-product.

WHY THE PARSE TEST. Truncation is detected by trying to JSON-parse the raw
value, not by testing for length 5011 and not by looking for the `[truncated]`
marker. All three agreed on 8/8 logs when #134 was measured, but AF owns none
of them: the cap can be re-tuned and the marker re-worded by an editor release,
and on that day a length test starts reporting every return as complete. A
value that does not parse is structurally incomplete no matter what the cap is
called.

WHY `unavailable` IS NOT EMPTY TEXT. #123 documents an implementer that
"returned nothing at all" while seven files were modified. The matching
signature is in the logs: a final record whose parts hold a `tool_call` and no
text part. If that surfaced as an empty string, a gate would read "the agent
said nothing" and "the agent's words could not be recovered" as the same fact
and would have to guess which one it was holding. They are therefore different
states, and `complete`/`truncated` never come back with empty text.

WHY `empty` EXISTS (issue #175). The paragraph above declared those two facts
different states and then this reader returned `unavailable` for both, so the
guess it set out to prevent was the one it handed every caller. Measured over
851 real subagent logs: 644 complete, 190 truncated, 17 unavailable -- and that
last bucket is 8 records that parse cleanly with no text part, 8 damaged values
with nothing salvageable, and 1 with no record at all. Five of the 8 silent
returns had already made 10 to 33 file-editing tool calls. Blocking on
`unavailable` would therefore have fired on a coin flip between a real defect
and the hook's own blind spot, which is why `implementer-stop` only warned.

`empty` cannot arise from a blind spot: the log was found, the record was
there, and it parsed. Only the words are missing, so a caller may act on it.
`unavailable` keeps its original meaning -- the reader could not measure -- and
still maps to BLOCKED per the gate taxonomy, exactly as #251 and #138 require
of a check that cannot classify its input.

Identifying the caller's own log is the same heuristic as
`concurrent-agent-edits.py` -- the most recently modified
`runSubagent-{agent}-*.jsonl` -- and carries the same caveat: two invocations
of the SAME agent in parallel would defeat it. Here that degrades to reading a
sibling's return, so a caller that must not confuse agents should verify the
text it gets rather than trust the pairing.

Stdlib only, on purpose -- a gate that needs `pip install` stops being run.

Usage:
    subagent-return.py --session-dir <dir> --agent <name>

Output:
    Line 1   one of `complete` / `truncated` / `empty` / `unavailable`
    Line 2+  the recovered text (absent for `empty` and `unavailable`)

Exit codes:
    0  a status was determined (including `empty` and `unavailable`)
    2  usage error -- arguments missing or unreadable

Exit 0 for `unavailable` is deliberate: it separates "the reader ran and found
nothing readable" from "the reader did not run", so a wrapper can report the
first honestly instead of inferring it from a failure.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

# The agent name itself contains hyphens, so the split is on the LAST one.
# Duplicated from `concurrent-agent-edits.py` rather than imported -- the
# filename carries a hyphen and is not importable as a module.
SUBAGENT = re.compile(r"^runSubagent-(?P<agent>.+)-(?P<call>[^-]+)\.jsonl$")

# Cheap prefilter so a large log is not JSON-parsed line by line.
RESPONSE_HINT = b'"agent_response"'

# Observed identical in 299 of 299 sampled logs: `{"type":"text","content":"`.
# The optional whitespace is not decoration -- the editor writes compact JSON,
# but a log passed through any pretty-printer would carry `"type": "text"`, and
# an exact-match pattern would silently salvage nothing at all.
TEXT_PART = re.compile(r'"type"\s*:\s*"text"\s*,\s*"content"\s*:\s*"')

COMPLETE = "complete"
TRUNCATED = "truncated"
EMPTY = "empty"
UNAVAILABLE = "unavailable"


def agent_from(filename: str) -> str:
    match = SUBAGENT.match(filename)
    if match:
        return match.group("agent")
    return filename[len("runSubagent-") : -len(".jsonl")]


def find_own_log(session_dir: str, agent: str) -> str | None:
    """The most recently modified log belonging to `agent`, or None."""
    try:
        names = [n for n in os.listdir(session_dir) if n.startswith("runSubagent-") and n.endswith(".jsonl")]
    except OSError:
        return None

    newest: str | None = None
    newest_mtime = -1.0
    for name in names:
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


def last_response(path: str) -> str | None:
    """The raw `attrs.response` of the LAST `agent_response` record.

    Last rather than first: a turn can write several, and the one that matters
    to a Stop hook is the one it is about to return.
    """
    raw_value: str | None = None
    try:
        with open(path, "rb") as handle:
            for line in handle:
                if RESPONSE_HINT not in line:
                    continue
                try:
                    record = json.loads(line.decode("utf-8", "replace"))
                except (ValueError, UnicodeDecodeError):
                    continue
                if not isinstance(record, dict) or record.get("type") != "agent_response":
                    continue
                attrs = record.get("attrs")
                if not isinstance(attrs, dict):
                    continue
                value = attrs.get("response")
                if isinstance(value, str):
                    raw_value = value
    except OSError:
        return None
    return raw_value


def texts_from(parsed: object) -> list[str]:
    """Every `text` part's content, in order, from a parsed response array."""
    out: list[str] = []
    if not isinstance(parsed, list):
        return out
    for message in parsed:
        if not isinstance(message, dict):
            continue
        parts = message.get("parts")
        if not isinstance(parts, list):
            continue
        for part in parts:
            if not isinstance(part, dict) or part.get("type") != "text":
                continue
            content = part.get("content")
            if isinstance(content, str) and content:
                out.append(content)
    return out


def _unescape(chunk: str) -> str:
    """Decode a JSON string body that may stop mid-escape.

    A cut can land inside `\\uXXXX` or straight after a backslash, leaving a
    body that no decoder accepts. Trimming a few characters off the tail costs
    at most the last glyph and turns an unusable fragment into real text.
    """
    for cut in range(0, 8):
        candidate = chunk[: len(chunk) - cut] if cut else chunk
        if not candidate:
            break
        try:
            return json.loads('"' + candidate + '"')
        except ValueError:
            continue
    return ""


def salvage(raw: str) -> list[str]:
    """Recover text parts from a value too damaged to parse."""
    out: list[str] = []
    for match in TEXT_PART.finditer(raw):
        start = match.end()
        index = start
        while index < len(raw):
            char = raw[index]
            if char == "\\":
                index += 2
                continue
            if char == '"':
                break
            index += 1
        text = _unescape(raw[start:index])
        if text:
            out.append(text)
    return out


def classify(raw: str | None) -> tuple[str, str]:
    """Map a raw response value onto (status, text)."""
    if not isinstance(raw, str) or not raw:
        return UNAVAILABLE, ""

    try:
        parsed = json.loads(raw)
    except ValueError:
        recovered = "".join(salvage(raw))
        # No text recovered means the words are gone, not that none were said.
        return (TRUNCATED, recovered) if recovered else (UNAVAILABLE, "")

    # Parsed means the record was whole. No text in a whole record is a fact
    # about the agent, not about the reader -- that is the whole distinction.
    texts = "".join(texts_from(parsed))
    return (COMPLETE, texts) if texts else (EMPTY, "")


def main() -> int:
    parser = argparse.ArgumentParser(description="Read this agent's final return text with a status.")
    parser.add_argument("--session-dir", required=True)
    parser.add_argument("--agent", required=True)
    args = parser.parse_args()

    log = find_own_log(args.session_dir, args.agent)
    status, text = classify(last_response(log)) if log else (UNAVAILABLE, "")

    # Bytes, not `print`: agent returns carry em-dashes and box glyphs, and on
    # a cp1252 console Python raises UnicodeEncodeError *after* the status line
    # is already out -- a caller would read a valid status from a reader that
    # died. Encoding here keeps the two on one path.
    payload = (status + "\n" + text).encode("utf-8", "replace")
    stream = getattr(sys.stdout, "buffer", None)
    if stream is None:
        sys.stdout.write(payload.decode("utf-8", "replace"))
    else:
        stream.write(payload)
        stream.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
