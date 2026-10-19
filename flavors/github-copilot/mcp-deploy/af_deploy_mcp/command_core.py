"""Core runner of the AF command server (#60).

Resolves a script inside a configured folder, picks its interpreter by
extension, derives the walltime, runs it without a shell, and logs the run.

The walltime is an upper bound, never a duration: ``run_script`` returns as
soon as the process exits. Past the walltime the whole process tree is killed
and the verdict is ``TIMEOUT``.
"""

# copilot:generated | coordinator | 2026-10-19

from __future__ import annotations

import contextlib
import hashlib
import json
import os
import re
import signal
import subprocess
import sys
import time
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from .deploy_core import get_af_env_value

MODES = ("off", "reviewed", "ask", "ask-always", "autonomous")
DEFAULT_SCRIPT_DIRS = ".github/scripts/agent"
DEFAULT_TASK_SCRIPT_DIRS = ".github/scripts"
TAIL_LINES = 60
TAIL_CHARS = 6000
HISTORY_RUNS = 5
HISTORY_FACTOR = 2
HISTORY_FLOOR_S = 30
POLL_S = 0.2
EXTENSIONS = (".py", ".ps1", ".sh")


class Refused(Exception):
    """A script that must not run; the message says why."""


@dataclass(frozen=True)
class ScriptDir:
    rel: str
    mode: str | None


@dataclass(frozen=True)
class Config:
    dirs: list[ScriptDir]
    approval: str
    walltime_default: int
    walltime_max: int
    task_dirs: list[str]


@dataclass(frozen=True)
class Resolved:
    path: Path
    rel: str
    folder: str
    folder_mode: str | None


def _check_mode(mode: str, origin: str) -> str:
    if mode not in MODES:
        raise ValueError(f"unknown approval mode '{mode}' in {origin}; expected one of {', '.join(MODES)}")
    return mode


def parse_script_dirs(value: str) -> list[ScriptDir]:
    """Parse ``AF_SCRIPT_DIRS``: comma-separated folders, each with an optional ``:mode``."""
    dirs: list[ScriptDir] = []
    for raw in value.split(","):
        entry = raw.strip()
        if not entry:
            continue
        rel, sep, mode = entry.rpartition(":")
        if not sep or "/" in mode or "\\" in mode:
            dirs.append(ScriptDir(entry.strip("/\\").replace("\\", "/"), None))
            continue
        dirs.append(ScriptDir(rel.strip().strip("/\\").replace("\\", "/"), _check_mode(mode.strip(), entry)))
    return dirs


def _int(af_env: Path, key: str, default: int) -> int:
    value = get_af_env_value(af_env, key)
    return int(value) if value else default


def load_config(workspace_root: Path) -> Config:
    """Read the command-server keys from ``.github/af-env.conf``, with defaults."""
    af_env = workspace_root / ".github" / "af-env.conf"
    dirs = parse_script_dirs(get_af_env_value(af_env, "AF_SCRIPT_DIRS") or DEFAULT_SCRIPT_DIRS)
    approval = _check_mode(get_af_env_value(af_env, "AF_SCRIPT_APPROVAL") or "ask", "AF_SCRIPT_APPROVAL")
    task_dirs = [
        d.strip().strip("/\\").replace("\\", "/")
        for d in (get_af_env_value(af_env, "AF_TASK_SCRIPT_DIRS") or DEFAULT_TASK_SCRIPT_DIRS).split(",")
        if d.strip()
    ]
    return Config(
        dirs=dirs,
        approval=approval,
        walltime_default=_int(af_env, "AF_SCRIPT_WALLTIME_DEFAULT", 600),
        walltime_max=_int(af_env, "AF_SCRIPT_WALLTIME_MAX", 3600),
        task_dirs=task_dirs,
    )


def _folders(config: Config) -> list[ScriptDir]:
    configured = {d.rel for d in config.dirs}
    implicit = [ScriptDir(rel, "reviewed") for rel in config.task_dirs if rel not in configured]
    return [*config.dirs, *implicit]


def _within(base: Path, target: Path) -> bool:
    try:
        target.relative_to(base)
    except ValueError:
        return False
    return True


def resolve_script(workspace_root: Path, config: Config, path: str) -> Resolved:
    """Resolve ``path`` to a script inside the deepest configured folder, or raise ``Refused``."""
    root = workspace_root.resolve()
    candidate = Path(path)
    if not candidate.is_absolute():
        candidate = root / candidate
    real = candidate.resolve()
    owner: ScriptDir | None = None
    for folder in _folders(config):
        base = (root / folder.rel).resolve()
        if _within(base, real) and (owner is None or len(folder.rel) > len(owner.rel)):
            owner = folder
    if owner is None:
        raise Refused(f"'{path}' is outside every configured script folder")
    if real.suffix.lower() not in EXTENSIONS:
        raise Refused(f"'{path}' has no supported extension ({', '.join(EXTENSIONS)})")
    if not real.is_file():
        raise Refused(f"'{path}' not found")
    return Resolved(real, real.relative_to(root).as_posix(), owner.rel, owner.mode)


def interpreter_for(script: Path, workspace_root: Path) -> list[str]:
    """Return the argv prefix that runs ``script``; no shell is involved."""
    suffix = script.suffix.lower()
    if suffix == ".py":
        venv = workspace_root / (".venv/Scripts/python.exe" if sys.platform == "win32" else ".venv/bin/python")
        return [str(venv) if venv.is_file() else sys.executable, str(script)]
    if suffix == ".ps1":
        shell = "powershell.exe" if sys.platform == "win32" else "pwsh"
        return [shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script)]
    if suffix == ".sh":
        return ["bash", str(script)]
    raise Refused(f"no interpreter for '{script.name}'")


def resolve_walltime(explicit: int | None, history: list[float], budget: int | None, config: Config) -> tuple[int, str]:
    """Pick the walltime and say where it came from: explicit, history, suite budget, default."""
    cap = config.walltime_max
    if explicit is not None:
        return (cap, "explicit-capped") if explicit > cap else (int(explicit), "explicit")
    if history:
        derived = max(HISTORY_FLOOR_S, int(max(history) * HISTORY_FACTOR + 0.999))
        return min(derived, cap), "history"
    if budget is not None:
        return min(budget, cap), "suite-budget"
    return min(config.walltime_default, cap), "default"


def _run_log(workspace_root: Path) -> Path:
    return workspace_root / ".github" / "logs" / "command-runs.jsonl"


def read_history(workspace_root: Path, rel: str) -> list[float]:
    """Durations of the last passing runs of ``rel``, oldest first."""
    log = _run_log(workspace_root)
    if not log.is_file():
        return []
    durations: list[float] = []
    for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        if row.get("path") == rel and row.get("verdict") == "PASS":
            durations.append(row["duration_s"])
    return durations[-HISTORY_RUNS:]


def suite_budget(workspace_root: Path, rel: str) -> int | None:
    """The ceiling ``suite-budgets.json`` lists for this script's basename, if any."""
    budgets = workspace_root / ".github" / "scripts" / "suite-budgets.json"
    if not budgets.is_file():
        return None
    try:
        suites = json.loads(budgets.read_text(encoding="utf-8")).get("suites", {})
    except json.JSONDecodeError:
        return None
    value = suites.get(Path(rel).name)
    return int(value) if value is not None else None


def content_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _tail(text: str) -> str:
    tail = "\n".join(text.splitlines()[-TAIL_LINES:])
    return tail[-TAIL_CHARS:]


def _kill_tree(proc: subprocess.Popen) -> None:
    if sys.platform == "win32":
        subprocess.run(["taskkill", "/T", "/F", "/PID", str(proc.pid)], capture_output=True, check=False)
    else:
        with contextlib.suppress(ProcessLookupError):
            os.killpg(proc.pid, signal.SIGKILL)
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()


def _spawn(argv: list[str], cwd: Path, log_file) -> subprocess.Popen:
    kwargs: dict = {"cwd": str(cwd), "stdout": log_file, "stderr": subprocess.STDOUT, "stdin": subprocess.DEVNULL}
    if sys.platform == "win32":
        kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        kwargs["start_new_session"] = True
    return subprocess.Popen(argv, **kwargs)


def execute(
    argv: list[str],
    cwd: Path,
    log_path: Path,
    walltime_s: int,
    on_tick: Callable[[float, str], None] | None = None,
    tick_s: float = 15.0,
) -> tuple[str, int | None, float, str]:
    """Run ``argv`` to completion or walltime; return (verdict, exit code, duration, full output)."""
    log_path.parent.mkdir(parents=True, exist_ok=True)
    t0 = time.monotonic()
    next_tick = tick_s
    with log_path.open("wb") as log_file:
        proc = _spawn(argv, cwd, log_file)
        while True:
            try:
                code = proc.wait(timeout=POLL_S)
                break
            except subprocess.TimeoutExpired:
                elapsed = time.monotonic() - t0
                if elapsed >= walltime_s:
                    _kill_tree(proc)
                    code = None
                    break
                if on_tick is not None and elapsed >= next_tick:
                    next_tick += tick_s
                    last = log_path.read_bytes()[-400:].decode("utf-8", errors="replace").splitlines()
                    on_tick(elapsed, last[-1] if last else "")
    duration = round(time.monotonic() - t0, 2)
    output = log_path.read_bytes().decode("utf-8", errors="replace")
    if code is None:
        return "TIMEOUT", None, duration, output
    return ("PASS" if code == 0 else "FAIL"), code, duration, output


def _slug(rel: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "_", Path(rel).stem)[:60]


def _append_run(workspace_root: Path, row: dict) -> None:
    log = _run_log(workspace_root)
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("a", encoding="utf-8") as f:
        f.write(json.dumps(row) + "\n")


def run_script(
    workspace_root: Path,
    path: str,
    args: list[str],
    walltime_s: int | None = None,
    approve: Callable[[Resolved, str, Config], str | None] | None = None,
    on_tick: Callable[[float, str], None] | None = None,
    tick_s: float = 15.0,
) -> dict:
    """Resolve, approve, run and log one script. Never raises for a refusal.

    ``approve`` returns ``None`` to allow, or the refusal reason. Without it,
    every resolvable script runs (the caller owns the approval policy).
    """
    root = workspace_root.resolve()
    result = {
        "verdict": "REFUSED",
        "exit_code": None,
        "duration_s": 0.0,
        "walltime_s": None,
        "walltime_source": None,
        "tail": "",
        "log_path": None,
        "reason": None,
    }
    try:
        config = load_config(root)
        resolved = resolve_script(root, config, path)
        argv = [*interpreter_for(resolved.path, root), *[str(a) for a in args]]
    except (Refused, ValueError) as exc:
        result["reason"] = str(exc)
        return result

    digest = content_hash(resolved.path)
    if approve is not None and (reason := approve(resolved, digest, config)) is not None:
        result["reason"] = reason
        _append_run(root, _row(resolved, digest, args, "REFUSED", None, 0.0, None, reason))
        return result

    walltime, source = resolve_walltime(
        walltime_s, read_history(root, resolved.rel), suite_budget(root, resolved.rel), config
    )
    stamp = datetime.now().strftime("%Y%m%dT%H%M%S%f")
    log_path = root / ".github" / "logs" / "command-runs" / f"{stamp}-{_slug(resolved.rel)}.log"
    verdict, code, duration, output = execute(argv, root, log_path, walltime, on_tick, tick_s)
    _append_run(root, _row(resolved, digest, args, verdict, code, duration, walltime, None))
    result.update(
        verdict=verdict,
        exit_code=code,
        duration_s=duration,
        walltime_s=walltime,
        walltime_source=source,
        tail=_tail(output),
        log_path=str(log_path),
        reason=f"walltime of {walltime}s exceeded; process tree killed" if verdict == "TIMEOUT" else None,
    )
    return result


def _row(
    resolved: Resolved,
    digest: str,
    args: list[str],
    verdict: str,
    code: int | None,
    duration: float,
    walltime: int | None,
    reason: str | None,
) -> dict:
    return {
        "time": datetime.now().isoformat(timespec="seconds"),
        "path": resolved.rel,
        "sha256": digest,
        "args": [str(a) for a in args],
        "folder": resolved.folder,
        "verdict": verdict,
        "exit_code": code,
        "duration_s": duration,
        "walltime_s": walltime,
        "reason": reason,
    }
