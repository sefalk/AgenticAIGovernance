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

That scoping has a failure mode of its own: a guard with nothing to measure
emits nothing, and nothing is exactly what a passing guard emits. A project
that gitignores ``.github/`` can never stage a budget input, so the guard was
installed, wired, and structurally unable to fire -- for months reading as
consent. Whenever the staged set is empty, the guard therefore checks whether
git holds the payload at all, and when it does not, measures the payload from
disk instead. Copilot loads those files from disk too; git tracking changes
nothing about what they cost.

Exit codes: 0 pass, 1 over budget, 2 internal error or unmeasurable payload.
Blindness is reported, never blocked: an exit code is a statement about the
commit in front of the guard, and untracked files are a statement about the
repository. Charging one to the other makes an unrelated commit pay for a
configuration defect.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

TAG = "[context-budget-guard]"
OVERRIDE_ENV = "ALLOW_CONTEXT_BUDGET"
BUDGET_FILES = frozenset({"copilot-instructions.md", "af-env.conf", ".af-manifest"})


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


def _is_budget_input(relative: str) -> bool:
    """Does a path inside ``.github`` change the verdict?

    The measured content, plus the two files that decide how it is measured:
    ``af-env.conf`` sets the ceilings -- lowering one can put an untouched
    payload over budget, and a ceiling that binds only the next edit does not
    bind -- and ``.af-manifest`` decides which files are the framework's and
    which are the project's.
    """
    parts = relative.split("/")
    if len(parts) == 1:
        return parts[0] in BUDGET_FILES
    if len(parts) != 2:
        return False
    if parts[0] == "instructions":
        return parts[1].endswith(".md")
    return parts[0] == "agents" and parts[1].endswith(".agent.md")


def _payload_root(path: str) -> str | None:
    """Repo-relative ``.github`` directory a staged file puts under budget.

    Returns ``None`` when the path cannot change the verdict. The directory is
    derived from the path rather than assumed, because the AF source repo nests
    its payload under ``flavors/github-copilot/`` while a deployed project keeps
    it at the repo root.
    """
    parts = path.split("/")
    if ".github" not in parts:
        return None
    index = parts.index(".github")
    if not _is_budget_input("/".join(parts[index + 1:])):
        return None
    return "/".join(parts[: index + 1])


def _on_disk(root: str) -> set[str]:
    """Budget inputs present in the working tree under ``root``."""
    base = Path(root)
    found = {name for name in BUDGET_FILES if (base / name).is_file()}
    for sub in ("instructions", "agents"):
        directory = base / sub
        if not directory.is_dir():
            continue
        for entry in directory.iterdir():
            relative = f"{sub}/{entry.name}"
            if entry.is_file() and _is_budget_input(relative):
                found.add(relative)
    return found


def _tracked(root: str) -> set[str]:
    """Budget inputs git holds under ``root``."""
    names = _git_bytes(
        ["-c", "core.quotePath=false", "ls-files", "-z", "--", f":(literal){root}"],
    )
    prefix = f"{root}/"
    return {
        entry[len(prefix):]
        for entry in names.decode("utf-8", "replace").split("\0")
        if entry.startswith(prefix) and _is_budget_input(entry[len(prefix):])
    }


def _blind_spot(root: str) -> list[str]:
    """Budget inputs on disk that git does not hold -- invisible to the index."""
    return sorted(_on_disk(root) - _tracked(root))


def _own_root() -> str | None:
    """Repo-relative payload directory this guard was deployed into.

    With nothing staged there is no path to derive the root from, so the guard
    falls back to where it lives: ``hooks/scripts/`` -> ``.github/``. Returns
    ``None`` when that is outside the repository being committed to, which is
    someone else's payload and none of this guard's business.
    """
    top = Path(_git_text(["rev-parse", "--show-toplevel"]).strip()).resolve()
    try:
        return Path(__file__).resolve().parents[2].relative_to(top).as_posix()
    except ValueError:
        return None


def _ignored(paths: list[str]) -> set[str]:
    """Which of ``paths`` a gitignore rule matches. Empty on any git failure."""
    result = subprocess.run(
        ["git", "check-ignore", "-z", "--stdin"],
        input="\0".join(paths).encode("utf-8"), capture_output=True, check=False,
    )
    if result.returncode not in (0, 1):
        return set()
    return {p for p in result.stdout.decode("utf-8", "replace").split("\0") if p}


def _print_names(names: list[str], limit: int = 5) -> None:
    for name in names[:limit]:
        print(f"    {name}")
    if len(names) > limit:
        print(f"    ... and {len(names) - limit} more")


def _report_blind_spot() -> int:
    """Say when the guard has nothing to gate, instead of exiting 0 mutely.

    A commit that stages no budget input is the ordinary case and stays silent;
    the payload it would measure was already measured when it was committed. A
    repository where git holds no budget input at all is not that case -- there
    was no such commit and there cannot be one.
    """
    root = _own_root()
    if root is None:
        return 0
    on_disk = _on_disk(root)
    blind = _blind_spot(root) if on_disk else []
    if not blind:
        return 0
    if len(blind) == len(on_disk):
        print(f"{TAG} NOT GATED -- git tracks none of the {len(on_disk)} files under")
        print(f"  {root}/ that the budget depends on. Nothing about them can be staged,")
        print("  so this guard cannot fire on any commit. Its silence was not a pass.")
    else:
        print(f"{TAG} PARTIALLY GATED -- {len(blind)} of {len(on_disk)} files under {root}/")
        print("  that the budget depends on are untracked, so the index measures a subset")
        print("  and reports it as the total:")
        _print_names(blind)
    if _ignored([f"{root}/{name}" for name in blind]):
        print("  Cause: a gitignore rule matches them.")
    else:
        print("  Cause: they exist on disk but were never added to git.")
    _advise(root)
    print("  Restore the gate by tracking them.")
    return 0


def _advise(root: str) -> None:
    """Measure the working tree, because the index is not what pays.

    Copilot loads instruction files from disk; whether git holds them changes
    nothing about what they cost. The index is the right basis for a *verdict*
    -- it is what the commit is made of -- but the wrong basis for a *number*
    when git holds only part of the payload. So the reading is taken from disk
    and blocks nothing: no commit can be held responsible for a file it did not
    stage and, here, could not have staged.
    """
    checker = _checker()
    if not checker.is_file():
        print(f"  Measure them by hand: python {root}/scripts/check-context-budget.py")
        return
    print("  Measured from the working tree instead -- advisory, blocks nothing:")
    if _measure(checker, Path(root), indent="    ") != 0:
        print("  Over budget, and unenforceable: this guard has no commit to attach")
        print("  the verdict to until git holds the files.")


def _export_index(root: str, dest: Path) -> bool:
    """Write the indexed payload under ``root`` into ``dest``.

    ``af-env.conf`` travels with it: the budgets that apply are the ones being
    committed to *this* repository, not the framework's own. ``.af-manifest``
    likewise decides which files are the framework's and which are the
    project's, and a commit may be changing that.
    """
    pathspecs = [
        f":(literal){root}/copilot-instructions.md",
        f":(literal){root}/af-env.conf",
        f":(literal){root}/.af-manifest",
        f":(literal){root}/instructions",
        f":(literal){root}/agents",
    ]
    names = _git_bytes(["-c", "core.quotePath=false", "ls-files", "-z", "--", *pathspecs])
    if not names.strip(b"\0"):
        return False
    prefix = dest.as_posix().rstrip("/") + "/"
    _git_bytes(["checkout-index", "-f", "-z", "--stdin", "--prefix", prefix], stdin=names)
    # .af-hashes is a deployment record, not source: it is untracked in a
    # consumer, so the index has no copy to export. Without it the checker
    # cannot see that a project's own instruction file was never shipped by AF,
    # and charges it to the framework -- a false failure, not a false pass, but
    # a confusing one. Take the working-tree copy; nothing about it is stageable.
    hashes = Path(root) / ".af-hashes"
    if hashes.is_file():
        shutil.copy2(hashes, dest / root / ".af-hashes")
    return True


def _checker() -> Path:
    """The measurement, which lives beside this guard: hooks/scripts/ -> scripts/.

    Guard and checker therefore always ship as one version.
    """
    return Path(__file__).resolve().parents[2] / "scripts" / "check-context-budget.py"


def _measure(checker: Path, github_dir: Path, indent: str = "  ") -> int:
    result = subprocess.run(
        [sys.executable, str(checker), "--github-dir", str(github_dir)],
        capture_output=True, text=True, encoding="utf-8", check=False,
    )
    output = (result.stdout or "") + (result.stderr or "")
    for line in output.splitlines():
        print(f"{indent}{line}")
    return result.returncode


def main() -> int:
    if os.environ.get(OVERRIDE_ENV, "").strip().lower() in {"1", "true", "yes"}:
        print(f"{TAG} {OVERRIDE_ENV} override set -- skipping check.")
        return 0
    try:
        roots = sorted({r for path in _staged_files() if (r := _payload_root(path))})
        if not roots:
            return _report_blind_spot()
        checker = _checker()
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
            blind = _blind_spot(root)
            if blind:
                print(f"{TAG} the reading above is a floor -- {len(blind)} file(s) under")
                print(f"  {root}/ are untracked, so the index holds no copy to measure:")
                _print_names(blind)
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
