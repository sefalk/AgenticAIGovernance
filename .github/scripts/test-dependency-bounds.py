"""Declared dependencies cannot go stale unnoticed (#275).

`mcp` went a full major version out of date and the framework found out only
when a clean install could not import its own server (#274): `>=1.2` with no
upper bound let a fresh resolve pick up the breaking major, and a dev
virtualenv that already held 1.x hid it. Two halves close that gap:

1. Notification -- `.github/dependabot.yml` covers `pip` (mcp-deploy) and
   `github-actions`, so a new major arrives as a pull request, not a red build.
2. Prevention -- every runtime dependency in a tracked `pyproject.toml` carries
   an upper bound, or a reason under `[tool.af.unbounded-dependencies]`.
   Dependabot proposes upgrades; it does not stop a clean install from
   resolving a breaking major in the meantime.

The gate is proved by negative control on temporary copies: an unbounded
declaration is rejected, a justified one accepted. The tree is never touched.

Usage:
    python .github/scripts/test-dependency-bounds.py
"""

# copilot:generated | coordinator | 2026-10-20

from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

import tomllib
import yaml

REPO = Path(__file__).resolve().parents[2]
DEPENDABOT = REPO / ".github" / "dependabot.yml"
MCP_DEPLOY_DIR = "/flavors/github-copilot/mcp-deploy"
MIN_REASON = 10

# A requirement's name, before any extras, specifier or marker.
NAME = re.compile(r"^\s*([A-Za-z0-9][A-Za-z0-9._-]*)")
# An operator that caps the version from above. `==1.*` and `~=1.4` both cap.
UPPER = re.compile(r"(<|<=|==|~=|===)")


def _canonical(name: str) -> str:
    return re.sub(r"[-_.]+", "-", name).lower()


def unbounded(pyproject: Path) -> list[str]:
    """Runtime dependencies with no upper bound and no recorded reason."""
    data = tomllib.loads(pyproject.read_text(encoding="utf-8"))
    deps = data.get("project", {}).get("dependencies", [])
    reasons = data.get("tool", {}).get("af", {}).get("unbounded-dependencies", {})
    justified = {_canonical(k) for k, v in reasons.items() if isinstance(v, str) and len(v.strip()) >= MIN_REASON}
    found: list[str] = []
    for req in deps:
        match = NAME.match(req)
        if not match:
            found.append(req)
            continue
        # A marker (`; python_version < '3.12'`) is not a version bound.
        spec = req.split(";", 1)[0][match.end() :]
        spec = re.sub(r"^\s*\[[^\]]*\]", "", spec)
        if UPPER.search(spec):
            continue
        if _canonical(match.group(1)) in justified:
            continue
        found.append(req.strip())
    return found


def tracked_pyprojects() -> list[Path]:
    out = subprocess.run(
        ["git", "-C", str(REPO), "ls-files", "*pyproject.toml"], capture_output=True, text=True, check=True
    ).stdout
    return [REPO / line for line in out.splitlines() if line and "/payload/" not in line]


failures = 0
checks = 0


def check(label: str, ok: bool, detail: str = "") -> None:
    global failures, checks
    checks += 1
    failures += 0 if ok else 1
    print(f"[{'PASS' if ok else 'FAIL'}] {label}{'' if ok or not detail else ' -- ' + detail}")


def check_dependabot() -> None:
    check("dependabot.yml exists", DEPENDABOT.is_file(), str(DEPENDABOT))
    if not DEPENDABOT.is_file():
        return
    config = yaml.safe_load(DEPENDABOT.read_text(encoding="utf-8")) or {}
    updates = config.get("updates") or []
    pip = [u for u in updates if u.get("package-ecosystem") == "pip"]
    actions = [u for u in updates if u.get("package-ecosystem") == "github-actions"]
    check(
        "dependabot covers pip for mcp-deploy",
        any(u.get("directory") == MCP_DEPLOY_DIR for u in pip),
        f"no pip entry with directory {MCP_DEPLOY_DIR}",
    )
    check("dependabot covers github-actions", bool(actions), "no github-actions entry")
    # Integration happens on dev; a pull request against main would bypass it.
    check(
        "every dependabot entry targets dev",
        bool(updates) and all(u.get("target-branch") == "dev" for u in updates),
        "an entry without target-branch: dev",
    )


def check_tree() -> None:
    files = tracked_pyprojects()
    check("at least one tracked pyproject.toml", bool(files), "git ls-files found none -- the glob is wrong")
    for path in files:
        bad = unbounded(path)
        check(
            f"runtime dependencies bounded in {path.relative_to(REPO).as_posix()}",
            not bad,
            "no upper bound and no [tool.af.unbounded-dependencies] reason: " + ", ".join(bad),
        )


# name, pyproject body, expected offenders
CONTROLS: list[tuple[str, str, list[str]]] = [
    ("unbounded is rejected", '[project]\ndependencies = ["mcp>=2"]\n', ["mcp>=2"]),
    ("bare name is rejected", '[project]\ndependencies = ["pyyaml"]\n', ["pyyaml"]),
    ("upper bound passes", '[project]\ndependencies = ["mcp>=2,<3"]\n', []),
    ("compatible release passes", '[project]\ndependencies = ["mcp~=2.1"]\n', []),
    ("exact pin passes", '[project]\ndependencies = ["ruff==0.16.2"]\n', []),
    (
        "a marker is not a bound",
        "[project]\ndependencies = [\"tomli>=2; python_version < '3.11'\"]\n",
        ["tomli>=2; python_version < '3.11'"],
    ),
    (
        "justified unbounded passes",
        '[project]\ndependencies = ["pyyaml>=6"]\n\n'
        '[tool.af.unbounded-dependencies]\npyyaml = "stable API for a decade, major bumps are rare"\n',
        [],
    ),
    (
        "a token reason is rejected",
        '[project]\ndependencies = ["pyyaml>=6"]\n\n[tool.af.unbounded-dependencies]\npyyaml = "ok"\n',
        ["pyyaml>=6"],
    ),
    (
        "names compare canonically",
        '[project]\ndependencies = ["Py_YAML>=6"]\n\n'
        '[tool.af.unbounded-dependencies]\npy-yaml = "stable API for a decade, major bumps are rare"\n',
        [],
    ),
]


def check_controls() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        for name, body, want in CONTROLS:
            path = Path(tmp) / f"{abs(hash(name))}.toml"
            path.write_text(body, encoding="utf-8")
            got = unbounded(path)
            check(f"control: {name}", got == want, f"got {got}, want {want}")


def main() -> int:
    check_dependabot()
    check_tree()
    check_controls()
    print(f"\n=== {checks - failures}/{checks} passed ===")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
