"""Availability probes for the external tools the parity tests shell out to.

``shutil.which`` answers whether a name resolves, not whether running it does
anything. On a GitHub-hosted Windows runner ``bash`` resolves to
``C:\\Windows\\System32\\bash.exe`` -- the WSL launcher -- and a runner with no
distribution installed answers any call to it with "Windows Subsystem for Linux
has no installed distributions" and exit 1. A ``which``-based guard therefore
reads as "bash is available", runs ``deploy.sh`` through it, and reports the
resulting exit 1 as a deploy failure. That is exactly how the first CI run of
this suite went red (#270), for a reason that had nothing to do with the code
under test, and it is invisible on a developer machine where ``bash`` does not
resolve at all and the test simply skips.

So the probe is the check: run the tool on something trivial and require it to
succeed. Results are cached because a skip decision is asked once per test and
launching a process is not free.
"""

from __future__ import annotations

import shutil
import subprocess
from functools import cache

# A trivial invocation per tool that must exit 0 if the tool is usable. There is
# deliberately no default: `--version` is wrong for awk, which reads its first
# argument as a program, and Windows PowerShell 5.1 answers it with a non-zero
# exit, so a guessed probe would turn into a permanent silent skip.
PROBES: dict[str, list[str]] = {
    "bash": ["-c", "exit 0"],
    "awk": ["BEGIN { exit 0 }"],
    "git": ["--version"],
}


@cache
def usable(exe: str) -> bool:
    """True when ``exe`` resolves *and* a trivial invocation of it succeeds."""
    if exe not in PROBES:
        raise KeyError(f"no probe defined for {exe!r}; add one to PROBES rather than assuming a --version flag")
    if shutil.which(exe) is None:
        return False
    try:
        proc = subprocess.run(
            [exe, *PROBES[exe]],
            capture_output=True,
            timeout=60,
            stdin=subprocess.DEVNULL,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return proc.returncode == 0
