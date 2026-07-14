#!/usr/bin/env python3
"""Hard-gate linting checks using ruff.

Reads LINTING_STRICTNESS from af-env.conf (or --strictness override) to
select the ruff rule set. Requires ruff in the active venv or on PATH.

Strictness levels:
  minimal   F8                    pyflakes only (unused imports, undefined names)
  standard  E,F,I                 + pycodestyle errors + isort
  strict    E,F,I,B,UP,SIM,C90   + bugbear, pyupgrade, simplify, complexity

Exit codes:
  0  PASS  — no violations
  1  BLOCKED — ruff not installed (hooks treat as advisory skip, not block)
  2  FAIL  — lint violations found
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

STRICTNESS_RULES: dict[str, str] = {
    "minimal":  "F8",
    "standard": "E,F,I",
    "strict":   "E,F,I,B,UP,SIM,C90",
}

DEFAULT_STRICTNESS = "standard"


def _read_conf(conf_path: Path, key: str) -> str | None:
    """Read a key=value entry from af-env.conf.

    Parameters
    ----------
    conf_path : Path
        Path to the conf file.
    key : str
        Key to look up.

    Returns
    -------
    str | None
        The value if found, else None.
    """
    if not conf_path.exists():
        return None
    for line in conf_path.read_text(encoding="utf-8").splitlines():
        m = re.match(rf"^{re.escape(key)}=(.+)$", line.strip())
        if m:
            return m.group(1).strip()
    return None


def _find_conf() -> Path:
    """Walk up from cwd to find .github/af-env.conf.

    Returns
    -------
    Path
        Path to the conf file (may not exist if not found).
    """
    for parent in [Path.cwd(), *Path.cwd().parents]:
        candidate = parent / ".github" / "af-env.conf"
        if candidate.exists():
            return candidate
    return Path(".github/af-env.conf")


def _find_ruff() -> str | None:
    """Locate ruff: venv first, then PATH.

    Returns
    -------
    str | None
        Absolute path to ruff executable, or None if not found.
    """
    for candidate in [
        Path(".venv/Scripts/ruff.exe"),   # Windows venv
        Path(".venv/bin/ruff"),            # Unix venv
    ]:
        if candidate.exists():
            return str(candidate)
    return shutil.which("ruff")


def main() -> int:
    """CLI entry point for hard-gate linting validation.

    Returns
    -------
    int
        0 = pass, 1 = blocked (ruff missing), 2 = fail.
    """
    parser = argparse.ArgumentParser(
        description="Hard-gate linting checks via ruff",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="\n".join([
            "Strictness levels (LINTING_STRICTNESS in af-env.conf):",
            "  minimal   F8                  -- pyflakes only",
            "  standard  E,F,I               -- + pycodestyle + isort",
            "  strict    E,F,I,B,UP,SIM,C90  -- + bugbear, pyupgrade, simplify, complexity",
        ]),
    )
    parser.add_argument("--files", nargs="+", required=True,
                        help="Python files to lint")
    parser.add_argument("--conf", default=None,
                        help="Path to af-env.conf (auto-detected if omitted)")
    parser.add_argument("--strictness", default=None,
                        help="Override strictness from af-env.conf")
    args = parser.parse_args()

    # --- Resolve strictness ---
    conf_path = Path(args.conf) if args.conf else _find_conf()
    strictness = (
        args.strictness
        or _read_conf(conf_path, "LINTING_STRICTNESS")
        or DEFAULT_STRICTNESS
    )
    if strictness not in STRICTNESS_RULES:
        print(
            f"LINTING_GATE_ERROR: unknown LINTING_STRICTNESS '{strictness}'. "
            f"Valid: {list(STRICTNESS_RULES)}"
        )
        return 1

    rules = STRICTNESS_RULES[strictness]

    # --- Filter to existing .py files ---
    files = [f for f in args.files if Path(f).exists() and f.endswith(".py")]
    if not files:
        print("LINTING_GATE_PASS (no files to check)")
        return 0

    # --- Locate ruff ---
    ruff_exe = _find_ruff()
    if ruff_exe is None:
        print(
            "LINTING_GATE_SKIP: ruff not found in .venv or PATH.\n"
            "Install with: pip install ruff\n"
            "Or add to DEP_DEV_FILE in af-env.conf."
        )
        return 1  # BLOCKED — hooks skip with advisory, not deny

    # --- Run ruff ---
    cmd = [ruff_exe, "check", f"--select={rules}", "--output-format=text"] + files
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
    except Exception as exc:
        print(f"LINTING_GATE_ERROR: failed to run ruff: {exc}")
        return 1

    if result.returncode == 0:
        print(f"LINTING_GATE_PASS (strictness={strictness}, rules={rules}, files={len(files)})")
        return 0

    print(f"LINTING_GATE_FAIL (strictness={strictness}, rules={rules})")
    if result.stdout.strip():
        print(result.stdout.strip())
    if result.stderr.strip():
        print(result.stderr.strip())
    return 2


if __name__ == "__main__":
    sys.exit(main())
