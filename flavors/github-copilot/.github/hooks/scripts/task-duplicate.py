"""Name the existing task that a ``create_and_run_task`` payload would duplicate (#396).

``createAndRunTask`` refuses an existing label and can never be auto-approved, so
an agent re-running an invocation minted a new label every time: the MP project
held 227 tasks for 118 distinct invocations. ``runTask`` on the existing label
runs the same command and can be auto-approved.

Reads the PreToolUse payload on stdin and prints the label of a task in
``<workspaceFolder>/.vscode/tasks.json`` with the same invocation, or nothing.
Hygiene rather than a security gate: anything unreadable prints nothing.
"""

from __future__ import annotations

import json
import os
import sys

_SHELLS = {"powershell", "pwsh"}


def _slashed(value: object) -> str:
    text = str(value).replace("\\", "/")
    for prefix in ("${workspaceFolder}/", "./"):
        if text.startswith(prefix):
            text = text[len(prefix) :]
    return text


def signature(command: object, args: object) -> tuple[str, tuple[str, ...]]:
    """The script a task runs and its arguments, with ``powershell -File`` unwrapped."""
    cmd = _slashed(command or "")
    rest = [_slashed(a) for a in args] if isinstance(args, list) else []
    if os.path.splitext(os.path.basename(cmd))[0].lower() in _SHELLS:
        lowered = [a.lower() for a in rest]
        if "-file" in lowered:
            at = lowered.index("-file")
            if at + 1 < len(rest):
                cmd, rest = rest[at + 1], rest[at + 2 :]
    return cmd.lower(), tuple(rest)


def main() -> int:
    try:
        payload = json.loads(sys.stdin.read())
        tool_input = payload.get("tool_input") or {}
        task = tool_input.get("task") or {}
        folder = tool_input.get("workspaceFolder") or (sys.argv[1] if len(sys.argv) > 1 else "")
        wanted = signature(task.get("command"), task.get("args"))
        with open(os.path.join(folder, ".vscode", "tasks.json"), encoding="utf-8-sig") as fh:
            existing = json.load(fh).get("tasks") or []
    except (OSError, ValueError, AttributeError):
        return 0
    if not wanted[0]:
        return 0
    for entry in existing:
        if (
            isinstance(entry, dict)
            and entry.get("label")
            and signature(entry.get("command"), entry.get("args")) == wanted
        ):
            print(str(entry["label"]).splitlines()[0])
            return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
