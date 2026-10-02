"""Every test suite in this repository must be executed by CI.

#270 was not "someone forgot a workflow step". The repository has two ways a
suite gets run — `run-all-tests.ps1` sweeps a directory, the workflow names
Python gates one by one — and a suite that fits neither simply falls between
them. `mcp-deploy/tests/` sat there for its whole life: 122 tests, none of them
ever executed, and the first run turned up a test that had been failing
unnoticed.

Naming this one suite in the workflow would fix one instance. This asserts the
property instead: every test artifact is reachable from something CI runs. A
suite added in a new place fails here on the pull request that adds it, which
is the only moment the gap is cheap to close.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
WORKFLOWS = REPO / ".github" / "workflows"

# Directories that are not sources: build output, virtualenvs, and the payload
# copy that the MCP wheel carries (the originals are already covered).
EXCLUDED_PARTS = {".venv", "venv", "node_modules", "__pycache__", ".git", "build", "dist", "payload"}

# Suites deliberately not run by CI, each with the reason it is exempt.
EXEMPT: dict[str, str] = {}

failures: list[str] = []
checks = 0


def annotate(body: str) -> None:
    """Raise a failure as a workflow annotation.

    A step that exits non-zero publishes nothing but its exit code to anyone
    who cannot open the run log, so the reason is attached to the run itself.
    """
    if os.environ.get("GITHUB_ACTIONS") != "true":
        return
    escaped = body.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    print(f"::error title=CI suite coverage::{escaped[:3000]}")


def check(label: str, condition: bool, detail: str = "") -> None:
    global checks
    checks += 1
    if not condition:
        failures.append(f"{label}{': ' + detail if detail else ''}")


def _visible(path: Path) -> bool:
    return not (EXCLUDED_PARTS & set(path.relative_to(REPO).parts))


def _is_agent_hook(path: Path) -> bool:
    """An agent hook that only looks like a test, because an agent is called test-writer.

    Hooks live in `hooks/scripts/` and are named `{agent}-{event}`, so
    `test-writer-stop.ps1` matches a `test-*` glob while being nothing of the
    kind. Rather than exempting the two files by name -- which would also hide
    a real suite dropped in that directory -- the rule verifies its own premise:
    the prefix must resolve to an agent that actually exists.
    """
    if "hooks" not in path.parts:
        return False
    stem = path.stem
    for agent in REPO.glob("flavors/*/.github/agents/*.agent.md"):
        name = agent.name[: -len(".agent.md")]
        if stem.startswith(f"{name}-"):
            return True
    return False


def test_artifacts() -> list[Path]:
    """Every file in the repository that exists to be executed as a test."""
    found: set[Path] = set()
    for pattern in ("**/test_*.py", "**/test-*.py", "**/test-*.ps1", "**/test-*.sh"):
        found.update(p for p in REPO.glob(pattern) if p.is_file() and _visible(p) and not _is_agent_hook(p))
    return sorted(found)


def executed_text() -> str:
    """What CI runs: the workflows, plus the scripts they invoke, one level deep.

    The indirection matters -- `run-all-tests.ps1` and `run-deploy-suite.py`
    are what the workflow names, but the suites they reach are named inside
    them. Without following that step, every swept suite would look uncovered.
    """
    parts: list[str] = []
    for wf in sorted(WORKFLOWS.glob("*.y*ml")):
        parts.append(wf.read_text(encoding="utf-8"))
    joined = "\n".join(parts)

    for script in REPO.glob(".github/scripts/*"):
        if script.is_file() and script.name in joined:
            parts.append(script.read_text(encoding="utf-8"))
    for script in REPO.glob("flavors/*/.github/scripts/*"):
        if script.is_file() and script.name in joined:
            parts.append(script.read_text(encoding="utf-8"))
    return "\n".join(parts)


def swept_dirs(text: str) -> set[Path]:
    """Directories covered by a sweep rather than by name.

    `run-all-tests.ps1` globs `test-*.ps1` beside itself; a pytest invocation
    covers the tree below the directory it names. Both mean a new file in that
    directory is already run, and must not be reported as a gap.
    """
    covered: set[Path] = set()
    if "run-all-tests.ps1" in text:
        for runner in REPO.glob("flavors/*/.github/scripts/run-all-tests.ps1"):
            covered.add(runner.parent)
    if "pytest" in text:
        for suite in REPO.glob("**/mcp-deploy"):
            if _visible(suite) and (suite / "tests").is_dir():
                covered.add(suite / "tests")
    return covered


def main() -> int:
    check("workflow directory exists", WORKFLOWS.is_dir(), str(WORKFLOWS))
    if not WORKFLOWS.is_dir():
        report = "\n".join(f"FAIL {f}" for f in failures)
        print(report)
        annotate(report)
        return 1

    artifacts = test_artifacts()
    check("found test artifacts to check", len(artifacts) > 10, f"{len(artifacts)} found")

    text = executed_text()
    check("workflow text was read", len(text) > 1000, f"{len(text)} chars")

    sweeps = swept_dirs(text)
    check("at least one sweep was resolved", bool(sweeps), "no swept directory found")

    uncovered: list[str] = []
    for path in artifacts:
        rel = path.relative_to(REPO).as_posix()
        if rel in EXEMPT:
            continue
        if path.name in text:
            continue
        if any(sweep in path.parents for sweep in sweeps):
            continue
        uncovered.append(rel)

    check(
        "every test artifact is reachable from something CI runs",
        not uncovered,
        f"{len(uncovered)} uncovered: " + ", ".join(uncovered),
    )

    for rel, reason in EXEMPT.items():
        check(f"exemption {rel} still refers to a real file", (REPO / rel).is_file())
        check(f"exemption {rel} carries a reason", len(reason) >= 15, reason)

    if failures:
        report = "\n".join(f"FAIL {f}" for f in failures)
        print(report)
        print(f"\n{len(failures)} of {checks} checks failed")
        annotate(report)
        return 1
    print(f"OK  CI suite coverage: {len(artifacts)} test artifacts, all reachable ({checks} checks)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
