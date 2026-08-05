"""Report scratch task labels left behind in ``.vscode/tasks.json``.

``createAndRunTask`` writes its payload into ``.vscode/tasks.json`` as a side
effect, so every one-off invocation an agent improvises becomes a permanent
entry. The file is a *cache of what agents may run*, not an audit trail of what
they did, and scratch entries accumulate in it silently.

This checker reports the entries that could not be created today: interpreter
invocations carrying an inline payload (``powershell -Command "..."``,
``bash -c "..."``) and tasks referencing prompt-resolved variables. Both are
denied by the task classifier in ``block-dangerous``, so their presence means
they predate the classifier or were written by hand.

Curated tasks are deliberately *not* flagged. A task that calls ``git`` or the
venv interpreter with fixed arguments is a legitimate ``run_task`` label -- it
is only ``createAndRunTask`` that is confined to ``AF_TASK_SCRIPT_DIRS``.

ADVISORY: always exits 0. A hygiene report must never block a workflow, and a
malformed or absent ``tasks.json`` is the strict-JSON guard's business, not
this one's.

Usage::

    python check-scratch-tasks.py [path/to/tasks.json]
"""

from __future__ import annotations

import json
import sys

DEFAULT_PATH = ".vscode/tasks.json"

# Commands that execute a payload handed to them rather than a reviewed file.
INTERPRETERS = {
    "powershell",
    "powershell.exe",
    "pwsh",
    "pwsh.exe",
    "cmd",
    "cmd.exe",
    "bash",
    "sh",
    "zsh",
    "python",
    "python3",
    "node",
    "perl",
    "ruby",
    "wscript",
    "cscript",
}

# Flags that introduce an inline script instead of a path.
INLINE_FLAGS = {"-command", "-c", "/c", "/k", "-encodedcommand", "-e"}

# Variables VS Code resolves at run time, to content the classifier never saw.
INDIRECTION = ("${input:", "${command:", "${config:")

SCOPES = ("windows", "linux", "osx")


def _basename(command: str) -> str:
    """Return the bare executable name of a command string, lowercased."""
    normalised = command.replace("\\", "/").strip().strip('"')
    return normalised.rsplit("/", 1)[-1].lower()


def _as_list(value: object) -> list[str]:
    """Coerce an ``args`` value into a flat list of strings.

    VS Code allows an argument to be an object (``{"value": ..., "quoting": ...}``),
    so the raw list is not always a list of strings.
    """
    if not isinstance(value, list):
        return []
    out: list[str] = []
    for item in value:
        if isinstance(item, str):
            out.append(item)
        elif isinstance(item, dict) and isinstance(item.get("value"), str):
            out.append(item["value"])
    return out


def scratch_reason(task: dict) -> str | None:
    """Return why ``task`` looks like scratch, or ``None`` if it looks curated.

    Every operating-system scope is inspected, not just the task scope: an OS
    override replaces the command that actually runs.
    """
    scopes: list[dict] = [task]
    scopes.extend(task[name] for name in SCOPES if isinstance(task.get(name), dict))

    for scope in scopes:
        command = scope.get("command") if isinstance(scope.get("command"), str) else ""
        args = _as_list(scope.get("args"))

        blob = " ".join([command, *args])
        for marker in INDIRECTION:
            if marker in blob:
                return f"resolves {marker}...}} at run time"

        if command and _basename(command) in INTERPRETERS:
            for arg in args:
                if arg.lower() in INLINE_FLAGS:
                    return f"inline payload via {_basename(command)} {arg}"

    return None


def main(argv: list[str]) -> int:
    """Print one line per scratch label found. Always succeeds."""
    path = argv[1] if len(argv) > 1 else DEFAULT_PATH

    try:
        with open(path, encoding="utf-8-sig") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return 0

    tasks = data.get("tasks") if isinstance(data, dict) else None
    if not isinstance(tasks, list):
        return 0

    for task in tasks:
        if not isinstance(task, dict):
            continue
        reason = scratch_reason(task)
        if reason:
            label = task.get("label") if isinstance(task.get("label"), str) else "(unlabelled)"
            print(f"{label} -- {reason}")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
