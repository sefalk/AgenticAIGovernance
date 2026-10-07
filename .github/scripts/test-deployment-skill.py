"""Guard the deployment skill: every delivery path must end in a verification.

Issue #236 was not that the paths were unknown — it was that they were knowable
only from a document outside the payload, that one path was missing, and that
none of them ended in a check on the artifact. Prose cannot hold that; a fifth
path added later would quietly arrive without a verification. These assertions
fail when it does.
"""

from __future__ import annotations

import re
import shlex
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PAYLOAD = REPO / "flavors" / "github-copilot" / ".github"
MCP_DEPLOY = REPO / "flavors" / "github-copilot" / "mcp-deploy"
FLAVOR_VERSION = REPO / "flavors" / "github-copilot" / "VERSION"
SKILL = PAYLOAD / "skills" / "deployment" / "SKILL.md"
INDEX = PAYLOAD / "skills" / "INDEX.md"
COORDINATOR = PAYLOAD / "agents" / "coordinator.agent.md"
WIKI = REPO / "docs" / "wiki" / "12-deployment.md"

VERIFICATION = "**Verification.**"
PATH_HEADING = re.compile(r"^## (\d+) · (.+)$", re.MULTILINE)

failures: list[str] = []
checks = 0


def check(label: str, condition: bool, detail: str = "") -> None:
    global checks
    checks += 1
    if not condition:
        failures.append(f"{label}{': ' + detail if detail else ''}")


def _slug(heading: str) -> str:
    """Reproduce GitHub's heading anchor."""
    return re.sub(r"[^\w\s-]", "", heading.lower()).replace(" ", "-")


def sections(text: str) -> dict[str, str]:
    """Split the skill into its numbered path sections."""
    marks = list(PATH_HEADING.finditer(text))
    out: dict[str, str] = {}
    for i, m in enumerate(marks):
        end = marks[i + 1].start() if i + 1 < len(marks) else len(text)
        out[m.group(2).strip()] = text[m.start() : end]
    return out


def run_documented_build(release: str) -> None:
    """Run the release cut's build command as written and inspect the wheel (#368).

    The command went stale unnoticed because nothing executed it: a bare
    `-m build` goes through the sdist, which lacks the force-included payload.
    """
    line = next((ln.strip() for ln in release.splitlines() if re.search(r"python(\.exe)? -m build", ln)), "")
    args = shlex.split(line.split("-m build", 1)[1]) if line else []
    with tempfile.TemporaryDirectory(prefix="af-wheel-") as out:
        proc = subprocess.run(
            [sys.executable, "-m", "build", *args, "--outdir", out],
            cwd=MCP_DEPLOY,
            capture_output=True,
            text=True,
        )
        tail = (proc.stdout + proc.stderr).strip().splitlines()[-3:]
        check("the documented build command succeeds", proc.returncode == 0, " | ".join(tail))
        wheels = sorted(Path(out).glob("*.whl"))
        check("the documented build command yields exactly one wheel", len(wheels) == 1, str(wheels))
        if len(wheels) != 1:
            return
        with zipfile.ZipFile(wheels[0]) as whl:
            names = whl.namelist()
            bundled = (
                whl.read("af_deploy_mcp/payload/VERSION").decode().strip()
                if "af_deploy_mcp/payload/VERSION" in names
                else ""
            )
        expected = FLAVOR_VERSION.read_text(encoding="utf-8").strip()
        check("the wheel bundles the flavor VERSION", bundled == expected, f"{bundled!r} != {expected!r}")
        check(
            "the wheel bundles the payload .github",
            any(n.startswith("af_deploy_mcp/payload/.github/") for n in names),
        )


def main() -> int:
    check("skill file exists", SKILL.is_file(), str(SKILL))
    if not SKILL.is_file():
        print("\n".join(f"FAIL {f}" for f in failures))
        return 1

    text = SKILL.read_text(encoding="utf-8")
    paths = sections(text)

    # AC 1 — reachable from inside a consumer project: it is payload, not docs/.
    check("skill lives in the payload", str(SKILL).startswith(str(PAYLOAD)))
    check(
        "skill is not an always-on instruction file",
        not (PAYLOAD / "instructions" / "deployment.instructions.md").exists(),
    )

    # AC 6 — links the wiki instead of duplicating it.
    check("wiki page still exists to link to", WIKI.is_file(), str(WIKI))
    check("skill links the deployment wiki page", "12-deployment.md" in text)

    # The four paths the decision table promises.
    expected = ["Release cut", "Routine upgrade", "Hotfix into a running project", "Conflict resolution"]
    for name in expected:
        check(f"path present: {name}", name in paths, f"found {sorted(paths)}")

    # AC 3 — the point of the whole issue.
    for name, body in paths.items():
        check(f"path ends in a verification: {name}", VERIFICATION in body)
        after = body.split(VERIFICATION, 1)[1] if VERIFICATION in body else ""
        check(
            f"verification names something to read, not a counter: {name}",
            any(w in after.lower() for w in ("assert", "select-string", "must", "present", "run")),
        )

    # Every decision-table row must reach a section that exists.
    # GitHub's anchor rule: lowercase, drop punctuation, spaces become hyphens —
    # so "## 1 · Release cut" is "#1--release-cut", with the gap the dropped · leaves.
    slugs = {_slug(f"{n} · {t}") for n, t in PATH_HEADING.findall(text)}
    for anchor in re.findall(r"\]\(#([a-z0-9-]+)\)", text):
        check(f"decision-table link resolves: #{anchor}", anchor in slugs, f"have {sorted(slugs)}")

    # AC 2 — the hotfix path must name local-state restoration and its trap.
    hotfix = paths.get("Hotfix into a running project", "")
    check("hotfix records the branch before touching anything", "rev-parse --abbrev-ref HEAD" in hotfix)
    check("hotfix names the checkout trap", "checkout" in hotfix and ".af-hashes" in hotfix)
    check("hotfix says how to recover from it", "af_update_hashes" in hotfix)

    # AC 5 — the release cut must rebuild and reinstall the wheel.
    release = paths.get("Release cut", "")
    check("release cut rebuilds the wheel", "-m build" in release)
    check("release cut reinstalls it", "--force-reinstall" in release)
    check("release cut builds the wheel from the source tree, not via the sdist", "-m build --wheel" in release)
    verify = release.split(VERIFICATION, 1)[1] if VERIFICATION in release else ""
    check("release verification expects unverifiable for a bundled install", "unverifiable" in verify)
    check("release verification reads the payload VERSION in the installed wheel", "payload/VERSION" in verify)
    run_documented_build(release)

    # AC 4 — the staleness signal the skill tells the reader to trust must exist.
    core = (REPO / "flavors" / "github-copilot" / "mcp-deploy" / "af_deploy_mcp" / "deploy_core.py").read_text(
        encoding="utf-8"
    )
    for state in ("behind-repository", "unverifiable", "not-applicable", "current"):
        check(f"deploy_core can report payload_state={state}", f'"{state}"' in core)
    check("skill and tool agree on the stale wording", "behind-repository" in text)

    # Registered where an agent would look for it.
    check("INDEX.md lists the skill", "`deployment`" in INDEX.read_text(encoding="utf-8"))
    check("coordinator points at the skill", "skills/deployment/SKILL.md" in COORDINATOR.read_text(encoding="utf-8"))

    for f in failures:
        print(f"FAIL {f}")
    print(f"\n{checks - len(failures)}/{checks} checks passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
