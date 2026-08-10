"""Pre-commit guard: reject a staged instruction payload that is over budget.

Invoked by the ``.github/hooks/git/pre-commit`` shim on every ``git commit``.

``.github/scripts/check-context-budget.py`` has always been able to measure the
payload; for months nothing ever asked it to. The framework's own conditional
instruction set drifted 273 tokens past its ceiling and stayed there, because
the only thing standing between the payload and its budget was a checklist line
a human had to remember. This guard is the thing that asks.

The measurement itself is *not* reimplemented here. The staged payload is
written out of the index into a temporary tree and handed to the existing
checker, so globs, budgets and ``applyTo`` semantics keep exactly one
definition.

The check runs only when the commit stages something the budget depends on
(``copilot-instructions.md``, ``instructions/*.md``, ``agents/*.agent.md``, or
the ``af-env.conf`` that sets the ceiling), so every other commit pays nothing.

Exit codes: 0 pass, 1 over budget, 2 internal error or unmeasurable payload.
"""
from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

TAG = "[context-budget-guard]"
OVERRIDE_ENV = "ALLOW_CONTEXT_BUDGET"


def _git_text(args: list[str]) -> str:
    result = subprocess.run(
        ["git", *args], capture_output=True, check=True, text=True, encoding="utf-8",
    )
    return result.stdout


def _git_bytes(args: list[str], stdin: bytes | None = None) -> bytes:
    result = subprocess.run(["git", *args], capture_output=True, check=True, input=stdin)
    return result.stdout


def _staged_files() -> list[str]:
    stdout = _git_text(
        ["-c", "core.quotePath=false", "diff", "--cached", "-z",
         "--name-only", "--diff-filter=ACMR"],
    )
    return [entry for entry in stdout.split("\0") if entry]


def _payload_root(path: str) -> str | None:
    """Repo-relative ``.github`` directory a staged file puts under budget.

    Returns ``None`` when the path cannot change the verdict. ``af-env.conf``
    counts even though it is not measured: lowering a ceiling can put an
    untouched payload over budget, and a ceiling that binds only the next edit
    does not bind.

    The directory is derived from the path rather than assumed, because the AF
    source repo nests its payload under ``flavors/github-copilot/`` while a
    deployed project keeps it at the repo root.
    """
    parts = path.split("/")
    if ".github" not in parts:
        return None
    index = parts.index(".github")
    rest = parts[index + 1:]
    relevant = (
        rest in (["copilot-instructions.md"], ["af-env.conf"])
        or (len(rest) == 2 and rest[0] == "instructions" and rest[1].endswith(".md"))
        or (len(rest) == 2 and rest[0] == "agents" and rest[1].endswith(".agent.md"))
    )
    return "/".join(parts[: index + 1]) if relevant else None


def _export_index(root: str, dest: Path) -> bool:
    """Write the indexed payload under ``root`` into ``dest``.

    ``af-env.conf`` travels with it: the budgets that apply are the ones being
    committed to *this* repository, not the framework's own.
    """
    pathspecs = [
        f":(literal){root}/copilot-instructions.md",
        f":(literal){root}/af-env.conf",
        f":(literal){root}/instructions",
        f":(literal){root}/agents",
    ]
    names = _git_bytes(["-c", "core.quotePath=false", "ls-files", "-z", "--", *pathspecs])
    if not names.strip(b"\0"):
        return False
    prefix = dest.as_posix().rstrip("/") + "/"
    _git_bytes(["checkout-index", "-f", "-z", "--stdin", "--prefix", prefix], stdin=names)
    return True


def _measure(checker: Path, github_dir: Path) -> int:
    result = subprocess.run(
        [sys.executable, str(checker), "--github-dir", str(github_dir)],
        capture_output=True, text=True, encoding="utf-8", check=False,
    )
    output = (result.stdout or "") + (result.stderr or "")
    for line in output.splitlines():
        print(f"  {line}")
    return result.returncode


def main() -> int:
    if os.environ.get(OVERRIDE_ENV, "").strip().lower() in {"1", "true", "yes"}:
        print(f"{TAG} {OVERRIDE_ENV} override set -- skipping check.")
        return 0
    try:
        roots = sorted({r for path in _staged_files() if (r := _payload_root(path))})
        if not roots:
            return 0
        # The measurement lives beside this guard: hooks/scripts/ -> scripts/.
        # Guard and checker therefore always ship as one version.
        checker = Path(__file__).resolve().parents[2] / "scripts" / "check-context-budget.py"
        if not checker.is_file():
            print(f"{TAG} WARNING: {checker.name} is missing -- staged payload not measured.")
            return 0
        status = 0
        for root in roots:
            with tempfile.TemporaryDirectory(prefix="ctx-budget-") as tmp:
                dest = Path(tmp)
                if not _export_index(root, dest):
                    print(f"{TAG} WARNING: nothing indexed under {root} -- payload not measured.")
                    continue
                print(f"{TAG} measuring the staged payload in {root}:")
                code = _measure(checker, dest / root)
            if code == 0:
                continue
            status = max(status, 1 if code == 1 else 2)
    except subprocess.CalledProcessError as exc:
        print(f"{TAG} ERROR: git command failed: {exc}", file=sys.stderr)
        return 2
    if status == 0:
        return 0
    print()
    if status == 2:
        print(f"{TAG} COMMIT BLOCKED -- the staged payload could not be measured.")
        print()
        print("Why: an unmeasurable payload is not a payload within budget. The")
        print("checker reported a blocking condition (see its output above).")
        print()
        print("To fix:")
        print("  - Resolve what the checker reported, then commit again.")
        print(f"  - One-off override for this commit: {OVERRIDE_ENV}=1 git commit ...")
        return 2
    print(f"{TAG} COMMIT BLOCKED -- the staged payload is over its context budget.")
    print()
    print("Why: every always-on token is paid on every turn of every workflow.")
    print("The budgets carry deliberate headroom, so the ceiling is reached by")
    print("the change that crosses it -- while its author still has the context")
    print("to decide what should have been narrowed or moved.")
    print()
    print("To fix:")
    print("  - Narrow an over-broad `applyTo` so the file leaves the always-on set.")
    print("  - Move depth into a skill, which loads on demand rather than always.")
    print("  - Raise the ceiling in .github/af-env.conf -- deliberately, not reflexively.")
    print(f"  - One-off override for this commit: {OVERRIDE_ENV}=1 git commit ...")
    return 1


if __name__ == "__main__":
    sys.exit(main())
