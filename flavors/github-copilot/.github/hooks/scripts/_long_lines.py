"""Announce long lines in a tool result the harness will spill to disk (#341).

Copilot Chat writes a text tool result over its spill threshold to a file and
gives the model only the path; read_file then cuts every line over 2,000
characters, and paging cannot recover a line. This runs in the PostToolUse
process, which still holds the full response, and answers with context plus a
lossless copy whose long lines are wrapped with an explicit marker.
"""

from __future__ import annotations

import json
import re
import tempfile
import time
from pathlib import Path

WRAP_MARKER = " <<AF-WRAP>>"
CHUNK_CHARS = 1000
LIMITS_FILE = Path(__file__).with_name("tool-limits.json")
COPY_DIR = Path(tempfile.gettempdir()) / "af-long-lines"
COPY_TTL_SECONDS = 86400

# Tools the harness exempts from the spill, per its own source.
UNSPILLED_TOOLS = {"search_subagent", "explore_subagent", "execution_subagent", "memory"}

_JSON_KEY = re.compile(r'^\s*"((?:[^"\\]|\\.)+)"\s*:')


def _limits() -> tuple[int, int]:
    try:
        limits = json.loads(LIMITS_FILE.read_text(encoding="utf-8"))["limits"]
        return int(limits["spill_threshold_chars"]["value"]), int(limits["read_file_line_chars"]["value"])
    except (OSError, ValueError, KeyError, TypeError):
        return 8192, 2000


def _spilled_form(response: str) -> tuple[str, bool]:
    """The text as the harness writes it: pretty JSON when it parses, else raw."""
    try:
        return json.dumps(json.loads(response), indent=2, ensure_ascii=False), True
    except ValueError:
        return response, False


def _wrap(line: str, cap: int) -> list[str]:
    if len(line) <= cap:
        return [line]
    chunks = [line[i : i + CHUNK_CHARS] for i in range(0, len(line), CHUNK_CHARS)]
    return [c + WRAP_MARKER for c in chunks[:-1]] + [chunks[-1]]


def _write_copy(tool_use_id: str, lines: list[str], cap: int) -> str:
    COPY_DIR.mkdir(parents=True, exist_ok=True)
    now = time.time()
    for old in COPY_DIR.glob("*.txt"):
        try:
            if now - old.stat().st_mtime > COPY_TTL_SECONDS:
                old.unlink()
        except OSError:
            pass
    safe_id = re.sub(r"[^A-Za-z0-9_.-]", "_", tool_use_id or "unknown")[:120]
    path = COPY_DIR / f"{safe_id}.txt"
    header = (
        f"# AF lossless copy of a tool result. Lines over {cap} characters are split into "
        f"{CHUNK_CHARS}-character chunks; a chunk ending in '{WRAP_MARKER.strip()}' continues on the "
        "next line, with nothing lost or added."
    )
    body = [header] + [chunk for line in lines for chunk in _wrap(line, cap)]
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(body) + "\n")
    return str(path)


def respond(payload: dict[str, object]) -> dict[str, object] | None:
    """PostToolUse output for a non-write tool, or None when there is nothing to say."""
    tool = str(payload.get("tool_name") or "")
    response = payload.get("tool_response")
    if tool in UNSPILLED_TOOLS or not isinstance(response, str) or not response:
        return None

    threshold, cap = _limits()
    if len(response) <= threshold:
        return None

    text, is_json = _spilled_form(response)
    lines = text.split("\n")
    long_lines = []
    for number, line in enumerate(lines, start=1):
        if len(line) > cap:
            key = _JSON_KEY.match(line) if is_json else None
            long_lines.append({"line": number, "chars": len(line), "field": key.group(1) if key else ""})
    if not long_lines:
        return None

    copy = _write_copy(str(payload.get("tool_use_id") or ""), lines, cap)
    named = ", ".join(
        f"{item['field'] or 'line ' + str(item['line'])} ({item['chars']} chars)" for item in long_lines[:10]
    )
    more = f" and {len(long_lines) - 10} more" if len(long_lines) > 10 else ""
    message = (
        f"This {tool} result is {len(response)} characters, over the {threshold}-character spill "
        f"threshold, so it is written to a file and read_file cuts every line over {cap} characters "
        f"there: {named}{more}. Read the lossless copy instead: {copy} -- it pages normally with "
        f"read_file. Limits: .github/hooks/scripts/tool-limits.json (#341)."
    )
    return {
        "additionalContext": message,
        "hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": message},
        "longLines": {"copy": copy, "lines": long_lines},
    }
