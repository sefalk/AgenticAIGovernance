"""An always-on instruction file must not restate a record that is generated elsewhere.

#126 was a 23-row skills table sitting in `copilot-instructions.md` directly
under a line declaring `skills/INDEX.md` canonical. It was the third copy:
agents already receive every skill's name and description in the `<skills>`
block VS Code assembles from the skill files, which cannot drift. The copy
could, and had -- it listed 23 of 30 activated skills, so the non-canonical
duplicate was also wrong.

Deleting the table fixes one instance. It would also regrow: four separate
prompts instructed an agent to write it, including the one that scaffolds every
new project. So this asserts the property instead, over every flavor payload:

1. No always-on file carries a skills catalogue.
2. A format specification has exactly one always-on home. Two always-on files
   disagreeing about the agent commit format is what #126 actually shipped --
   the template taught `{action summary}` while `git-workflow` mandated
   `{phase}: {description}`, and the `coordinator-pretooluse` hook rejected the
   template's version. Both files load on every request, so an agent was given
   a rule and its contradiction at once.
3. No prompt instructs an agent to write a catalogue into an always-on file --
   the generator, not the artifact, is what makes the duplicate come back.

"Always-on" is not defined here. It is imported from `check-context-budget.py`,
which owns that definition for the budget gate; a second notion of the term
would be the same duplication this file exists to prevent.
"""

from __future__ import annotations

import importlib.util
import os
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

# A markdown table row naming a skill directory. The catalogue's shape, not its
# exact columns -- a rewritten header with the same rows is the same duplicate.
CATALOGUE_ROW = re.compile(r"^\|.*`?skills/[A-Za-z0-9._-]+/`?.*\|", re.MULTILINE)

# An agent commit-message format specification: the literal prefix followed by
# a placeholder. Prose that merely mentions commits does not match.
COMMIT_FORMAT = re.compile(r"\[agent:\{[^}\n]*\}\]")

# An instruction to write the catalogue into the always-on template. Both parts
# must appear on one line, so prose that merely names the file is not flagged.
GENERATOR_LINE = re.compile(
    r"^.*copilot-instructions.*(?:Available Skills|skills table).*$", re.MULTILINE | re.IGNORECASE
)

# Directories whose markdown records history or discarded designs rather than
# instructing an agent. They are read, never executed.
NON_EXECUTABLE = {"ideas", "logs", "templates"}

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
    print(f"::error title=Always-on restatement::{escaped[:3000]}")


def check(label: str, condition: bool, detail: str = "") -> None:
    global checks
    checks += 1
    if not condition:
        failures.append(f"{label}{': ' + detail if detail else ''}")


def universal_globs(flavor: Path) -> set[str] | None:
    """The applyTo values that mean "always on", as the budget gate defines them."""
    checker = flavor / ".github" / "scripts" / "check-context-budget.py"
    if not checker.is_file():
        return None
    spec = importlib.util.spec_from_file_location(f"_budget_{flavor.name}", checker)
    if spec is None or spec.loader is None:
        return None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return set(module.UNIVERSAL_GLOBS)


def always_on_files(flavor: Path, globs: set[str]) -> list[Path]:
    """`copilot-instructions.md` plus every instruction file loaded on every request."""
    github = flavor / ".github"
    found = [github / "copilot-instructions.md"]
    for path in sorted((github / "instructions").glob("*.md")):
        text = path.read_text(encoding="utf-8-sig", errors="replace")
        match = re.search(r"^applyTo:\s*(.+)$", text, re.MULTILINE)
        # A missing applyTo loads everywhere, which is the expensive default.
        if match is None:
            found.append(path)
            continue
        value = match.group(1).strip().strip("'\"")
        if any(part.strip().strip("'\"") in globs for part in value.split(",")):
            found.append(path)
    return [p for p in found if p.is_file()]


def instructing_files(flavor: Path) -> list[Path]:
    """Markdown an agent is told to act on: prompts, agents, instructions."""
    github = flavor / ".github"
    found: list[Path] = []
    for sub in ("prompts", "agents", "instructions"):
        found.extend(p for p in sorted((github / sub).rglob("*.md")) if NON_EXECUTABLE.isdisjoint(p.parts))
    return found


def main() -> int:
    flavors = sorted(p for p in (REPO / "flavors").glob("*") if (p / ".github").is_dir())
    # Derivation guard: an empty sweep would pass every rule below vacuously.
    check("at least one flavor payload is measured", bool(flavors), f"found {len(flavors)}")

    for flavor in flavors:
        name = flavor.name
        globs = universal_globs(flavor)
        check(
            f"{name}: the budget gate defines the always-on set", globs is not None, "check-context-budget.py not found"
        )
        if globs is None:
            continue

        files = always_on_files(flavor, globs)
        # Derivation guard: a rule that reads nothing reports nothing.
        check(f"{name}: the always-on set is non-empty", bool(files), f"found {len(files)}")

        homes: list[str] = []
        for path in files:
            text = path.read_text(encoding="utf-8-sig", errors="replace")
            check(f"{name}: {path.name} is non-empty", bool(text.strip()))

            rows = CATALOGUE_ROW.findall(text)
            check(
                f"{name}: {path.name} carries no skills catalogue",
                not rows,
                f"{len(rows)} table rows name a skills/ directory -- the catalogue is `skills/INDEX.md` "
                f"and agents already receive each skill from its own file; a copy here is paid for on every request",
            )

            if COMMIT_FORMAT.search(text):
                homes.append(path.name)

        check(
            f"{name}: the agent commit format has one always-on home",
            len(homes) <= 1,
            f"specified in {homes} -- two always-on files can disagree, and a hook enforces only one of them",
        )

        sources = instructing_files(flavor)
        check(f"{name}: there is instructing markdown to scan", bool(sources), f"found {len(sources)}")
        for path in sources:
            text = path.read_text(encoding="utf-8-sig", errors="replace")
            for line in GENERATOR_LINE.findall(text):
                stripped = line.strip()
                # A prohibition names both terms too. Only an instruction to write one counts.
                if re.search(r"\b(never|not|no|without)\b", stripped, re.IGNORECASE):
                    continue
                check(
                    f"{name}: {path.relative_to(flavor)} does not regenerate the catalogue",
                    False,
                    f"{stripped[:140]!r} -- deleting the copy does not help while something rewrites it",
                )

    if failures:
        body = "\n".join(f"  - {f}" for f in failures)
        print(f"FAIL  always-on restatement: {len(failures)} of {checks} checks failed")
        print(body)
        annotate(f"{len(failures)} of {checks} checks failed\n{body}")
        return 1

    print(f"OK  always-on restatement: no generated record is restated in an always-on file ({checks} checks)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
