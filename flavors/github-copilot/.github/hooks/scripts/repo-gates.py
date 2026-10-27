"""Producer stop gates for every repository the subagent edited (issue #456, phase 2).

In a multi-root workspace the deploying repository's hooks fire for edits in
every folder. The producer gates (`implementer-stop`, `refactorer-stop`,
`test-writer-stop`) scope themselves from the deploying checkout, so an edit in
a second repository was never tested, linted or checked for provenance.

This core reads the subagent's own debug log, maps each edited path to its
repository, and when a repository other than the deploying one appears, runs
the gate once per repository and merges the verdicts:

  * the deploying repository: the calling hook itself, as before;
  * another repository: ITS OWN deployed copy of the same hook, so it is judged
    by its own af-env.conf, venv, test log and hook version. A repository with
    no deployed hook is reported as not gated -- it has no declared policy.

Each child runs with ``AF_GATE_CHILD=1``, which makes this core answer "run
inline" so nothing recurses. Every block is collected, not just the first: the
loop guard skips all gates on the re-invocation after a block, so a second
repository's finding would otherwise surface one stop cycle late.

Exit codes:
    0  the merged verdict was printed; the wrapper prints it and exits
    3  run the gates inline (single repository, a child, or nothing measurable)

Usage:
    repo-gates.py --hook-path <calling hook> --shell <interpreter>
                  --main-root <dir> --code-root <dir> < payload
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

from _agentlog import find_own_log, scan_edits
from _baseline import STORE, repo_key

INLINE = 3
CHILD_TIMEOUT = 280


def edited_repos(payload: dict, agent: str) -> list[str]:
    """Normalised toplevels of the repositories this invocation's own log edited."""
    sid = str(payload.get("session_id") or "")
    transcript = str(payload.get("transcript_path") or "")
    if not sid or not transcript:
        return []
    session_dir = Path(transcript).parent.parent / "debug-logs" / sid
    own = find_own_log(str(session_dir), agent, str(payload.get("agent_id") or ""))
    if own is None:
        return []
    _, _, edited = scan_edits(own)
    keys: dict[str, str | None] = {}
    repos: set[str] = set()
    for raw in edited:
        # A created file may not exist yet; its nearest existing ancestor names the repository.
        probe = Path(raw)
        while not probe.is_dir() and probe != probe.parent:
            probe = probe.parent
        folder = str(probe)
        if folder not in keys:
            keys[folder] = repo_key(probe)
        if keys[folder]:
            repos.add(keys[folder])
    return sorted(repos)


def run_child(command: list[str], payload_raw: str, cwd: Path, env: dict[str, str]) -> dict | None:
    try:
        out = subprocess.run(
            command,
            input=payload_raw,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            cwd=cwd,
            env=env,
            timeout=CHILD_TIMEOUT,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    for line in reversed(out.stdout.splitlines()):
        line = line.strip()
        if line.startswith("{"):
            try:
                verdict = json.loads(line)
            except ValueError:
                continue
            if isinstance(verdict, dict):
                return verdict
    return None


def merge(results: list[tuple[str, dict | None]]) -> dict:
    blocks: list[str] = []
    notes: list[str] = []
    for label, verdict in results:
        if verdict is None:
            notes.append(f"[{label}] gate returned no verdict")
            continue
        specific = verdict.get("hookSpecificOutput")
        if isinstance(specific, dict) and specific.get("decision") == "block":
            blocks.append(f"[{label}] {specific.get('reason', '')}")
        elif verdict.get("systemMessage"):
            notes.append(f"[{label}] {verdict['systemMessage']}")
        else:
            notes.append(f"[{label}] no finding")
    if blocks:
        reason = " || ".join(blocks + [n for n in notes if "not gated" in n])
        return {"hookSpecificOutput": {"hookEventName": "Stop", "decision": "block", "reason": reason}}
    return {"systemMessage": " || ".join(notes)}


def shell_args(shell: str) -> list[str]:
    if Path(shell).stem.lower() in {"powershell", "pwsh"}:
        return ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File"]
    return []


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hook-path", required=True)
    parser.add_argument("--shell", required=True)
    parser.add_argument("--main-root", required=True)
    parser.add_argument("--code-root", default="")
    args = parser.parse_args()

    if os.environ.get("AF_GATE_CHILD"):
        return INLINE
    payload_raw = sys.stdin.read()
    try:
        payload = json.loads(payload_raw or "{}")
    except ValueError:
        return INLINE
    if not isinstance(payload, dict):
        return INLINE

    hook = Path(args.hook_path)
    agent = hook.stem.removesuffix("-stop")
    deploying = {k for k in (repo_key(Path(args.main_root)), repo_key(Path(args.code_root or args.main_root))) if k}
    others = [r for r in edited_repos(payload, agent) if r not in deploying]
    if not others:
        return INLINE

    base_env = dict(os.environ, AF_GATE_CHILD="1")
    base_env.setdefault("AF_BASELINE_DIR", str(Path(args.main_root) / STORE))
    results: list[tuple[str, dict | None]] = []
    here = Path(args.main_root)
    results.append(
        (here.name, run_child([args.shell, *shell_args(args.shell), str(hook)], payload_raw, Path.cwd(), base_env))
    )
    for repo in others:
        root = Path(repo)
        twin = root / ".github" / "hooks" / "scripts" / hook.name
        if not twin.is_file():
            results.append((root.name, {"systemMessage": f"edits here are not gated: no {hook.name} deployed"}))
            continue
        env = {k: v for k, v in base_env.items() if k != "AF_CONF_PATH"}
        results.append((root.name, run_child([args.shell, *shell_args(args.shell), str(twin)], payload_raw, root, env)))

    print(json.dumps(merge(results)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
