"""Decision table for the staged-formatting gate in .githooks/pre-commit.

This hook is the AF repository's own machinery, not payload: run-all-tests.ps1
sweeps flavors/, so nothing there would ever execute it. Without this file the
gate would be a shipped script that no suite runs -- the defect class recorded
in #61, and the reason #253 existed at all.

The real hook is copied verbatim into a throwaway repository and executed
there. Retyping its logic here would prove only that the copy works. The
throwaway carries the repository's own ruff.toml, because a check run against
ruff's defaults is measuring a width nobody chose.

Usage:
    python .github/scripts/test-precommit-format-gate.py
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
HOOK = REPO / ".githooks/pre-commit"
RUFF_TOML = REPO / "ruff.toml"

FORMATTED = "x = [1, 2, 3]\n"
UNFORMATTED = "x = [1,2,3]\n"

REAL_PIN = "0.16.2"


def find_bash() -> str | None:
    """Locate a Git-for-Windows/POSIX bash.

    The Windows runner's `bash` is Git bash; preferring the known install path
    keeps a WSL bash -- which cannot see the Windows path this test hands it --
    from being picked up on a developer machine.
    """
    git_bash = Path(r"C:\Program Files\Git\bin\bash.exe")
    if git_bash.is_file():
        return str(git_bash)
    return shutil.which("bash")


def path_without_ruff() -> str:
    """PATH with every directory that offers a ruff executable removed.

    Emptying PATH outright would also remove git, grep and awk, and the hook
    would fail for a reason the case is not about.
    """
    kept = []
    for entry in os.environ.get("PATH", "").split(os.pathsep):
        if not entry:
            continue
        directory = Path(entry)
        try:
            has_ruff = any((directory / name).exists() for name in ("ruff", "ruff.exe"))
        except OSError:
            has_ruff = False
        if not has_ruff:
            kept.append(entry)
    return os.pathsep.join(kept)


def git(work: Path, *args: str) -> None:
    subprocess.run(
        ["git", "-c", "user.name=af-test", "-c", "user.email=af-test@example.invalid", *args],
        cwd=work,
        check=True,
        capture_output=True,
        text=True,
    )


def make_repo(work: Path, pin: str) -> None:
    git(work, "init", "-q", "-b", "main")
    hooks = work / ".githooks"
    hooks.mkdir()
    shutil.copyfile(HOOK, hooks / "pre-commit")
    shutil.copyfile(RUFF_TOML, work / "ruff.toml")
    workflow = work / ".github/workflows"
    workflow.mkdir(parents=True)
    # Only the line the hook reads; the rest of CI is irrelevant to it.
    (workflow / "regression.yml").write_text(
        f"jobs:\n  suites:\n    steps:\n      - run: python -m pip install ruff=={pin} pyyaml\n",
        encoding="utf-8",
    )


def write(work: Path, name: str, text: str) -> None:
    target = work / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8", newline="\n")


def run_hook(bash: str, work: Path, env_path: str | None) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    if env_path is not None:
        env["PATH"] = env_path
    return subprocess.run(
        [bash, ".githooks/pre-commit"],
        cwd=work,
        capture_output=True,
        text=True,
        env=env,
    )


# name -> (setup, pin, strip ruff from PATH, expected exit, expected text)
def case_no_python_staged(work: Path) -> None:
    write(work, "README.md", "# hello\n")
    write(work, "loose.py", UNFORMATTED)
    git(work, "add", "README.md")


def case_formatted_python(work: Path) -> None:
    write(work, "good.py", FORMATTED)
    git(work, "add", "good.py")


def case_unformatted_python(work: Path) -> None:
    write(work, "bad.py", UNFORMATTED)
    git(work, "add", "bad.py")


def case_unstaged_is_ignored(work: Path) -> None:
    write(work, "good.py", FORMATTED)
    write(work, "bad.py", UNFORMATTED)
    git(work, "add", "good.py")


def case_deleted_python(work: Path) -> None:
    write(work, "bad.py", UNFORMATTED)
    git(work, "add", "bad.py")
    git(work, "commit", "-q", "--no-verify", "-m", "seed")
    git(work, "rm", "-q", "bad.py")


def case_path_with_space(work: Path) -> None:
    write(work, "a dir/b file.py", UNFORMATTED)
    git(work, "add", "a dir/b file.py")


CASES: list[tuple[str, object, str, bool, int, str]] = [
    ("no_python_staged_passes", case_no_python_staged, REAL_PIN, False, 0, ""),
    ("formatted_python_passes", case_formatted_python, REAL_PIN, False, 0, ""),
    ("unformatted_python_fails", case_unformatted_python, REAL_PIN, False, 1, "bad.py"),
    ("unstaged_unformatted_is_ignored", case_unstaged_is_ignored, REAL_PIN, False, 0, ""),
    ("deleted_python_is_not_checked", case_deleted_python, REAL_PIN, False, 0, ""),
    ("a_path_with_a_space_is_still_checked", case_path_with_space, REAL_PIN, False, 1, "b file.py"),
    ("other_ruff_version_stands_aside", case_unformatted_python, "0.0.1", False, 0, "CI uses 0.0.1"),
    ("absent_ruff_stands_aside", case_unformatted_python, REAL_PIN, True, 0, "is not installed"),
]


def main() -> int:
    bash = find_bash()
    if bash is None:
        print("FAIL: no bash found -- the hook cannot be executed, so nothing here is proven.")
        return 2
    if not HOOK.is_file():
        print(f"FAIL: {HOOK} does not exist.")
        return 2

    installed = ""
    ruff = shutil.which("ruff")
    if ruff:
        probe = subprocess.run([ruff, "--version"], capture_output=True, text=True)
        installed = probe.stdout.split()[1] if len(probe.stdout.split()) > 1 else ""
    if installed != REAL_PIN:
        # Announced, not skipped in silence: the cases that need the pinned
        # ruff would otherwise pass by not running (#224).
        print(f"SKIP: ruff {installed or 'is not installed'}, this suite needs the pinned {REAL_PIN}.")
        print(f"      pip install ruff=={REAL_PIN}")
        return 0

    failures = 0
    for name, setup, pin, strip_ruff, want_exit, want_text in CASES:
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            make_repo(work, pin)
            setup(work)  # type: ignore[operator]
            proc = run_hook(bash, work, path_without_ruff() if strip_ruff else None)
            out = proc.stdout + proc.stderr
            passed = proc.returncode == want_exit and want_text in out
            # A pass must not be a pass by accident: only the failing cases may
            # mention formatting at all.
            if want_exit == 0 and "not formatted" in out:
                passed = False
            failures += 0 if passed else 1
            print(f"[{'PASS' if passed else 'FAIL'}] {name}: exit={proc.returncode} (want {want_exit})")
            if not passed:
                for line in out.splitlines():
                    if line.strip():
                        print(f"        | {line.rstrip()}")

    print()
    print(f"=== {len(CASES) - failures}/{len(CASES)} passed ===")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
