#!/usr/bin/env python3
"""Hard-gate linting checks using ruff.

Reads LINTING_STRICTNESS from af-env.conf (or --strictness override) to
select the ruff rule set. Requires ruff in the active venv or on PATH.

Strictness levels:
  minimal   F8                    pyflakes only (unused imports, undefined names)
  standard  E,F,I                 + pycodestyle errors + isort
  strict    E,F,I,B,UP,SIM,C90   + bugbear, pyupgrade, simplify, complexity

Precedence: the strictness rule set is the framework floor, but a rule the
project *explicitly* ignores in its own ruff config wins. A rule the project
merely does not `select` is not an exception -- the floor still applies. See
CORE_RULES for the part no project may switch off.

Formatting (`ruff format --check`) is a second, independent gate over the same
file set as the lint check. It is binary and runs at every strictness level --
it is not part of STRICTNESS_RULES and not affected by project_ignore. Drift
is a violation like any other (issue #124).

Exit codes:
  0  PASS  — no violations, formatting clean
  1  BLOCKED — ruff not installed, or format check could not be executed
  2  FAIL  — lint violations found and/or formatting drift
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # Python < 3.11
    tomllib = None  # type: ignore[assignment]

STRICTNESS_RULES: dict[str, str] = {
    "minimal": "F8",
    "standard": "E,F,I",
    "strict": "E,F,I,B,UP,SIM,C90",
}

DEFAULT_STRICTNESS = "standard"

# Rules a project may not switch off. Suppressing F821 (undefined name) hides a
# bug; suppressing E501 (line length) is a formatting preference. Enforcing this
# needs BOTH mechanisms below, because ruff resolves selectors by specificity
# rather than by CLI group order:
#   --extend-select=F8  beats a broader project ignore  (ignore = ["F"])
#   dropping the entry  beats an exact project ignore   (ignore = ["F821"])
CORE_RULES = "F8"

# ruff's config discovery order within a directory.
RUFF_CONFIG_NAMES = (".ruff.toml", "ruff.toml", "pyproject.toml")


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
        Path(".venv/Scripts/ruff.exe"),  # Windows venv
        Path(".venv/bin/ruff"),  # Unix venv
    ]:
        if candidate.exists():
            return str(candidate)
    return shutil.which("ruff")


def _discover_ruff_config(start: Path) -> Path | None:
    """Find the ruff config governing a directory, mirroring ruff's own search.

    Walks up from ``start`` and returns the first ``.ruff.toml`` / ``ruff.toml``,
    or a ``pyproject.toml`` that actually carries a ``[tool.ruff]`` table.

    Parameters
    ----------
    start : Path
        Directory to start the upward search from.

    Returns
    -------
    Path | None
        Path to the governing config file, or None if the tree has none.
    """
    for parent in [start, *start.parents]:
        for name in RUFF_CONFIG_NAMES:
            candidate = parent / name
            if not candidate.exists():
                continue
            if name != "pyproject.toml":
                return candidate
            if _load_toml(candidate).get("tool", {}).get("ruff") is not None:
                return candidate
    return None


def _load_toml(path: Path) -> dict:
    """Parse a TOML file, returning an empty mapping on any failure.

    Parameters
    ----------
    path : Path
        File to parse.

    Returns
    -------
    dict
        Parsed content, or ``{}`` if unreadable or tomllib is unavailable.
    """
    if tomllib is None:
        return {}
    try:
        return tomllib.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def _read_project_overrides(config_path: Path) -> tuple[list[str], dict[str, list[str]], list[str]]:
    """Extract the project's explicit lint exceptions from its ruff config.

    Only *explicit* suppressions are read (``ignore``, ``extend-ignore``,
    ``per-file-ignores``, ``extend-per-file-ignores``). The project's ``select``
    is deliberately not read: not selecting a rule is not an exception, and the
    framework floor still applies there.

    Parameters
    ----------
    config_path : Path
        Path to ``.ruff.toml``, ``ruff.toml`` or ``pyproject.toml``.

    Returns
    -------
    tuple[list[str], dict[str, list[str]], list[str]]
        Ignored rule codes, per-file ignore mapping, and notices describing
        anything that could not be resolved faithfully.
    """
    notices: list[str] = []
    data = _load_toml(config_path)
    if config_path.name == "pyproject.toml":
        root = data.get("tool", {}).get("ruff", {})
    else:
        root = data

    # ruff moved these keys under [lint] in 0.2; top level is deprecated but
    # still honoured. Prefer [lint] and flag the ambiguous both-present case
    # rather than silently merging two sources.
    lint = root.get("lint")
    if isinstance(lint, dict):
        section = lint
        if any(k in root for k in ("ignore", "extend-ignore", "per-file-ignores")):
            notices.append(
                f"{config_path.name} defines lint keys both at top level and under [lint]; "
                "only [lint] is read (matches ruff)."
            )
    else:
        section = root

    if "extend" in root:
        notices.append(
            f"{config_path.name} uses 'extend = {root['extend']!r}'; inherited exceptions "
            "are not resolved and will not be honoured by the gate."
        )

    ignores: list[str] = []
    for key in ("ignore", "extend-ignore"):
        value = section.get(key)
        if isinstance(value, list):
            ignores.extend(str(code).strip() for code in value if str(code).strip())

    per_file: dict[str, list[str]] = {}
    for key in ("per-file-ignores", "extend-per-file-ignores"):
        value = section.get(key)
        if isinstance(value, dict):
            for pattern, codes in value.items():
                if isinstance(codes, list):
                    per_file.setdefault(pattern, []).extend(str(code).strip() for code in codes if str(code).strip())

    return ignores, per_file, notices


def _strip_core(codes: list[str]) -> tuple[list[str], list[str]]:
    """Remove suppressions that would disable the non-overridable core.

    An entry at or below ``CORE_RULES`` (``F8``, ``F82``, ``F821``) is dropped,
    because ruff's specificity rule would let it beat ``--extend-select``.
    Broader entries (``F``, ``ALL``) are kept -- ``--extend-select=CORE_RULES``
    already outranks those.

    Parameters
    ----------
    codes : list[str]
        Rule codes the project wants suppressed.

    Returns
    -------
    tuple[list[str], list[str]]
        Codes to pass through, and codes rejected for protecting the core.
    """
    kept: list[str] = []
    rejected: list[str] = []
    for code in codes:
        (rejected if code.strip().upper().startswith(CORE_RULES) else kept).append(code)
    return kept, rejected


# ruff names the files it would reformat differently across versions, so both
# shapes are matched and drift is never silently missed on a ruff upgrade.
# Measured on ruff 0.16.1:
#     unformatted: File would be reformatted
#      --> C:\path\to\file.py:1:6
# Older releases print a single line instead:
#     Would reformat: path/to/file.py
_FORMAT_DRIFT_RES = (
    re.compile(r"^Would reformat:\s*(.+)$"),
    re.compile(r"^-->\s*(.+?):\d+:\d+$"),
)


def _check_formatting(ruff_exe: str, files: list[str]) -> tuple[bool, list[str]]:
    """Run ``ruff format --check`` over the exact lint file set.

    Formatting is binary and independent of ``LINTING_STRICTNESS`` and of any
    project ``ignore`` -- it is not a rule selection, so neither applies.
    Fails closed: any inability to execute the check is reported as blocked
    (the caller maps that to exit 1), never as clean.

    Parameters
    ----------
    ruff_exe : str
        Path to the resolved ruff executable.
    files : list[str]
        Exactly the file set passed to ``ruff check``.

    Returns
    -------
    tuple[bool, list[str]]
        ``(blocked, drifted_files)``. ``blocked`` is True if the check could
        not be executed or ruff itself errored. ``drifted_files`` lists the
        files that would be reformatted (only meaningful when not blocked).
    """
    try:
        result = subprocess.run(
            [ruff_exe, "format", "--check"] + files, capture_output=True, text=True, encoding="utf-8", errors="replace"
        )
    except Exception as exc:
        print(f"LINTING_GATE_ERROR: failed to run ruff format --check: {exc}")
        return True, []

    # ruff format --check: 0 = clean, 1 = would reformat, >=2 = ruff itself failed.
    if result.returncode not in (0, 1):
        print(f"LINTING_GATE_ERROR: ruff format --check exited {result.returncode}")
        if result.stdout.strip():
            print(result.stdout.strip())
        if result.stderr.strip():
            print(result.stderr.strip())
        return True, []

    if result.returncode == 0:
        return False, []

    drifted: list[str] = []
    for line in result.stdout.splitlines():
        stripped = line.strip()
        for pattern in _FORMAT_DRIFT_RES:
            m = pattern.match(stripped)
            if m:
                path = m.group(1).strip()
                if path not in drifted:
                    drifted.append(path)
                break

    # ruff reported drift (exit 1) but the message format didn't match what we
    # parse for -- fail closed rather than silently report zero drifted files.
    if not drifted:
        drifted = list(files)

    return False, drifted


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
        epilog="\n".join(
            [
                "Strictness levels (LINTING_STRICTNESS in af-env.conf):",
                "  minimal   F8                  -- pyflakes only",
                "  standard  E,F,I               -- + pycodestyle + isort",
                "  strict    E,F,I,B,UP,SIM,C90  -- + bugbear, pyupgrade, simplify, complexity",
            ]
        ),
    )
    parser.add_argument("--files", nargs="+", required=True, help="Python files to lint")
    parser.add_argument("--conf", default=None, help="Path to af-env.conf (auto-detected if omitted)")
    parser.add_argument("--strictness", default=None, help="Override strictness from af-env.conf")
    args = parser.parse_args()

    # --- Resolve strictness ---
    conf_path = Path(args.conf) if args.conf else _find_conf()
    strictness = args.strictness or _read_conf(conf_path, "LINTING_STRICTNESS") or DEFAULT_STRICTNESS
    if strictness not in STRICTNESS_RULES:
        print(f"LINTING_GATE_ERROR: unknown LINTING_STRICTNESS '{strictness}'. Valid: {list(STRICTNESS_RULES)}")
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

    notices: list[str] = []
    if tomllib is None:
        notices.append("tomllib unavailable (Python < 3.11); project lint exceptions are not honoured.")

    # --- Group files by the ruff config that governs them ---
    # One group in virtually every repo; nested configs are handled correctly
    # instead of being approximated by a single root config.
    groups: dict[Path | None, list[str]] = defaultdict(list)
    for path in files:
        groups[_discover_ruff_config(Path(path).resolve().parent)].append(path)

    applied: list[str] = []
    rejected: list[str] = []
    outputs: list[str] = []
    failed = False

    for config_path, group_files in groups.items():
        if config_path is None:
            ignores, per_file = [], {}
        else:
            ignores, per_file, group_notices = _read_project_overrides(config_path)
            notices.extend(group_notices)

        passthrough, core_rejected = _strip_core(ignores)
        applied.extend(passthrough)
        rejected.extend(core_rejected)

        # "concise" (not the legacy "text"): ruff removed --output-format=text in
        # 0.9. Passing it makes ruff exit 2 on every run, which the gate would
        # otherwise report as "violations found" on a clean tree.
        cmd = [
            ruff_exe,
            "check",
            f"--select={rules}",
            f"--extend-select={CORE_RULES}",
            "--output-format=concise",
        ]
        if passthrough:
            cmd.append("--ignore=" + ",".join(passthrough))
        for pattern, codes in per_file.items():
            kept, kept_rejected = _strip_core(codes)
            rejected.extend(kept_rejected)
            if kept:
                cmd.append(f"--per-file-ignores={pattern}:{','.join(kept)}")
        cmd += group_files

        try:
            result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
        except Exception as exc:
            print(f"LINTING_GATE_ERROR: failed to run ruff: {exc}")
            return 1

        # ruff: 1 = lint violations, >=2 = ruff itself failed (bad args, bad config).
        # Only the former is a gate FAIL; a broken invocation is BLOCKED, so it
        # cannot masquerade as a code-quality problem.
        if result.returncode not in (0, 1):
            print(f"LINTING_GATE_ERROR: ruff exited {result.returncode}")
            if result.stdout.strip():
                print(result.stdout.strip())
            if result.stderr.strip():
                print(result.stderr.strip())
            return 1

        if result.returncode == 1:
            failed = True
        for stream in (result.stdout, result.stderr):
            if stream.strip():
                outputs.append(stream.strip())

    # --- Formatting: binary, independent of strictness and project_ignore ---
    format_blocked, format_drift_files = _check_formatting(ruff_exe, files)
    if format_blocked:
        return 1

    # --- Report ---
    # Applied exceptions are printed so that precedence stays visible in the
    # stop-hook output, the workflow log and to the reviewing critic.
    for notice in notices:
        print(f"LINTING_GATE_NOTICE: {notice}")

    summary = [f"strictness={strictness}", f"rules={rules}", f"core={CORE_RULES}"]
    if applied:
        summary.append("project_ignore=" + ",".join(sorted(set(applied))))
    if rejected:
        summary.append("core_override_rejected=" + ",".join(sorted(set(rejected))))
    if format_drift_files:
        summary.append(f"format_drift={len(format_drift_files)}")
    else:
        summary.append("format=clean")

    if not failed and not format_drift_files:
        summary.append(f"files={len(files)}")
        print(f"LINTING_GATE_PASS ({', '.join(summary)})")
        return 0

    print(f"LINTING_GATE_FAIL ({', '.join(summary)})")
    for output in outputs:
        print(output)
    if format_drift_files:
        for path in format_drift_files:
            print(f"LINTING_GATE_FORMAT_DRIFT: {path}")
        print(
            "Remedy: .github/scripts/run-lint.ps1 -Fix   (PowerShell)  |  .github/scripts/run-lint.sh --fix   (POSIX)"
        )
    return 2


if __name__ == "__main__":
    sys.exit(main())
