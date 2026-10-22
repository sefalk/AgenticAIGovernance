"""Remove agent-minted tasks from ``.vscode/tasks.json`` (#396).

``createAndRunTask`` writes only ``label``, ``type``, ``command``, ``args``,
``isBackground``, ``problemMatcher`` and ``group`` -- never ``detail``. A task
without ``detail`` was therefore minted by an agent; curated tasks carry one.
The MP project held 227 tasks, 196 of them minted, most re-running an
invocation a curated task already offered.

A dry run by default: it lists what ``--apply`` would remove and writes
nothing. ``--apply`` keeps a timestamped backup next to the file. A minted task
that a kept task names in ``dependsOn`` is kept, so no kept task breaks.

Usage::

    python prune-tasks.py [--workspace DIR] [--apply]

af-caller-ok: run by a human on purpose. No hook or agent may delete tasks, so
its options have no production caller by design (#396).
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from datetime import datetime
from pathlib import Path


def _depends_on(task: dict) -> list[str]:
    deps = task.get("dependsOn")
    if isinstance(deps, str):
        return [deps]
    if isinstance(deps, list):
        return [d for d in deps if isinstance(d, str)]
    return []


def plan(tasks: list) -> tuple[list, list]:
    """Split tasks into (kept, removed); a dependency of a kept task is kept."""
    keep = {i for i, t in enumerate(tasks) if not isinstance(t, dict) or t.get("detail")}
    labels = {t.get("label"): i for i, t in enumerate(tasks) if isinstance(t, dict)}
    pending = list(keep)
    while pending:
        task = tasks[pending.pop()]
        if not isinstance(task, dict):
            continue
        for dep in _depends_on(task):
            at = labels.get(dep)
            if at is not None and at not in keep:
                keep.add(at)
                pending.append(at)
    kept = [t for i, t in enumerate(tasks) if i in keep]
    removed = [t for i, t in enumerate(tasks) if i not in keep]
    return kept, removed


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--workspace", default=".", help="workspace folder holding .vscode/tasks.json")
    parser.add_argument("--apply", action="store_true", help="write the pruned file (default: dry run)")
    args = parser.parse_args(argv)

    path = Path(args.workspace) / ".vscode" / "tasks.json"
    try:
        doc = json.loads(path.read_text(encoding="utf-8-sig"))
        tasks = doc.get("tasks") or []
    except FileNotFoundError:
        print(f"No tasks.json at {path}.", file=sys.stderr)
        return 2
    except (ValueError, AttributeError) as exc:
        print(f"{path} is not strict JSON ({exc}); nothing was changed.", file=sys.stderr)
        return 2

    kept, removed = plan(tasks)
    mode = "Removing" if args.apply else "Would remove"
    print(f"{path}: {len(tasks)} tasks, {len(kept)} kept, {len(removed)} agent-minted.")
    for task in removed:
        print(f"  {mode}: {task.get('label')}")
    if not args.apply or not removed:
        if removed:
            print("Dry run: nothing written. Re-run with --apply to prune.")
        return 0

    backup = path.with_name(f"tasks.json.bak-{datetime.now():%Y%m%d%H%M%S}")
    shutil.copy2(path, backup)
    doc["tasks"] = kept
    path.write_text(json.dumps(doc, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Written. Backup: {backup}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
