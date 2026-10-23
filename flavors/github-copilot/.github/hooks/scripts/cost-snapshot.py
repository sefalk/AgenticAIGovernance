"""Global Stop / SubagentStop hook core: refresh the session cost store (issue #457).

The chat debug log loses its head at a moment nobody controls, so the cost rows
are read out as often as the session offers a chance: after every turn and every
subagent. The collector reads only what the logs gained since its last run (see
logs/README.md, "The session store").

The collector is started detached and this hook answers ``{}`` at once: no turn
waits for it, and it never decides anything. ``AF_COST_SNAPSHOT_SYNC=1`` runs it
in the foreground so a test can read the store it wrote.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

# The session id becomes a directory and file name; one carrying a path must not.
SESSION_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")


def session_dir(payload: dict) -> Path | None:
    sid = str(payload.get("session_id") or "")
    transcript = str(payload.get("transcript_path") or "")
    if not SESSION_ID.fullmatch(sid) or not transcript:
        return None
    # <ws>/GitHub.copilot-chat/transcripts/<sid>.jsonl -> .../debug-logs/<sid>
    return Path(transcript).parent.parent / "debug-logs" / sid


def launch(argv: list[str]) -> None:
    if os.environ.get("AF_COST_SNAPSHOT_SYNC"):
        subprocess.run(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        return
    options: dict = {"stdin": subprocess.DEVNULL, "stdout": subprocess.DEVNULL, "stderr": subprocess.DEVNULL}
    if os.name == "nt":
        # Detached from the hook's console and process group, so it outlives the hook.
        options["creationflags"] = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        options["start_new_session"] = True
    subprocess.Popen(argv, close_fds=True, **options)


def main() -> int:
    try:
        payload = json.loads(sys.stdin.read() or "{}")
        target = session_dir(payload) if isinstance(payload, dict) else None
        root = Path(__file__).resolve().parents[3]
        collector = root / ".github" / "scripts" / "collect-session-cost.py"
        store = root / ".github" / "logs" / "cost" / "sessions"
        if target is not None and target.is_dir() and collector.is_file():
            launch([sys.executable, str(collector), "--session-dir", str(target), "--store", str(store), "--snapshot"])
    except (OSError, ValueError):
        # Advisory: a failed refresh is retried by the next Stop.
        pass
    print("{}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
