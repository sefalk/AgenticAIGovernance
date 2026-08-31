#!/usr/bin/env python3
"""Reconcile the three records of curated-skill state against each other.

Curation state is written to three places by the same prompt run, so at
curation time they agree by construction. They drift apart later -- a
hand-edit, an interrupted run, a schema change between versions -- and until
now nothing revisited the question (AAIG issue #257):

  1. skills/curated-assignments.json   the only file `--reapply` consumes
  2. .af-skills-curated                the sentinel snapshot
  3. skills/INDEX.md                   the agent-skill matrix
  4. agents/*.agent.md                 the managed region that reapply writes

The failure this catches is silent by construction: `--reapply` visits the
agents named in `assignments` and no others, so an agent missing from that map
is never written, never warned about, and keeps a stale or empty region while
the other two records go on claiming it has the skill.

Exits 1 on drift and names the specific disagreement. Exits 0 when the records
agree or when there is no curation state to check.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REGION_START = "<!-- AF:MANAGED:curated-skills:START -->"
REGION_END = "<!-- AF:MANAGED:curated-skills:END -->"

# `- **skill-name** (`skills/skill-name/SKILL.md`) -- description`
BULLET_NAME = re.compile(r"^\s*-\s+\*\*(?P<name>[a-z0-9][a-z0-9-]*)\*\*")
BULLET_TARGET = re.compile(r"skills/(?P<name>[a-z0-9][a-z0-9-]*)/SKILL\.md")
# `| **agent-name** | skill-a, skill-b |`
MATRIX_ROW = re.compile(r"^\|\s*\*\*(?P<agent>[a-z0-9][a-z0-9-]*)\*\*\s*\|(?P<skills>[^|]*)\|")


class CurationState:
    """The four records, parsed. Missing files are represented as empty."""

    def __init__(self, github_dir: Path) -> None:
        self.github_dir = github_dir
        self.assignments_path = github_dir / "skills" / "curated-assignments.json"
        self.sentinel_path = github_dir / ".af-skills-curated"
        self.index_path = github_dir / "skills" / "INDEX.md"
        self.agents_dir = github_dir / "agents"

        self.assignments: dict[str, list[str]] = {}
        self.activated: list[str] = []
        self.sentinel_agents: dict[str, list[str]] = {}
        self.matrix: dict[str, list[str]] = {}
        self.parse_errors: list[str] = []

    # ── parsing ────────────────────────────────────────────────────────────

    def load(self) -> None:
        self._load_assignments()
        self._load_sentinel()
        self._load_index()

    def _load_assignments(self) -> None:
        if not self.assignments_path.exists():
            return
        try:
            # utf-8-sig: PowerShell and Windows editors write a BOM, and a BOM is
            # not corruption. Plain utf-8 rejects it and the file reads as broken.
            data = json.loads(self.assignments_path.read_text(encoding="utf-8-sig"))
        except (OSError, json.JSONDecodeError) as exc:
            self.parse_errors.append(f"curated-assignments.json is unreadable: {exc}")
            return
        raw = data.get("assignments", {})
        if isinstance(raw, dict):
            self.assignments = {
                agent: [s for s in skills if isinstance(s, str)]
                for agent, skills in raw.items()
                if isinstance(skills, list)
            }
        activated = data.get("activated", [])
        if isinstance(activated, list):
            self.activated = [s for s in activated if isinstance(s, str)]

    def _load_sentinel(self) -> None:
        """Read `activated[].name` / `activated[].agents` from the sentinel.

        Hand-rolled rather than PyYAML: the framework may not have it installed,
        and the shape needed here is two fixed keys inside one top-level list.
        """
        if not self.sentinel_path.exists():
            return
        try:
            lines = self.sentinel_path.read_text(encoding="utf-8-sig", errors="replace").splitlines()
        except OSError as exc:
            self.parse_errors.append(f".af-skills-curated is unreadable: {exc}")
            return

        in_activated = False
        current: str | None = None
        for line in lines:
            if re.match(r"^[a-z_]+:", line):
                in_activated = line.startswith("activated:")
                current = None
                continue
            if not in_activated:
                continue
            name_match = re.match(r"^\s*-\s+name:\s*(\S+)", line)
            if name_match:
                current = name_match.group(1).strip("\"'")
                continue
            agents_match = re.match(r"^\s*agents:\s*\[(.*)\]", line)
            if agents_match and current:
                agents = [a.strip().strip("\"'") for a in agents_match.group(1).split(",")]
                self.sentinel_agents[current] = [a for a in agents if a]

    def _load_index(self) -> None:
        if not self.index_path.exists():
            return
        try:
            text = self.index_path.read_text(encoding="utf-8-sig", errors="replace")
        except OSError as exc:
            self.parse_errors.append(f"INDEX.md is unreadable: {exc}")
            return
        for line in text.splitlines():
            row = MATRIX_ROW.match(line)
            if not row:
                continue
            skills = [s.strip().strip("`") for s in row.group("skills").split(",")]
            self.matrix[row.group("agent")] = [s for s in skills if s]

    # ── agent files ────────────────────────────────────────────────────────

    def agent_path(self, agent: str) -> Path:
        return self.agents_dir / f"{agent}.agent.md"

    def region_skills(self, agent: str) -> list[str] | None:
        """Skill names inside the agent's managed region, or None if no region."""
        path = self.agent_path(agent)
        if not path.exists():
            return None
        text = path.read_text(encoding="utf-8-sig", errors="replace")
        start = text.find(REGION_START)
        end = text.find(REGION_END)
        if start == -1 or end == -1 or end < start:
            return None
        body = text[start + len(REGION_START) : end]
        return [m.group("name") for m in (BULLET_NAME.match(ln) for ln in body.splitlines()) if m]

    def base_skills(self, agent: str) -> set[str]:
        """Skills referenced OUTSIDE the region.

        Curation deliberately drops these from the region (a skill promoted into
        the framework base would otherwise appear twice), so a name missing from
        a region is only drift if it is not a base bullet.
        """
        path = self.agent_path(agent)
        if not path.exists():
            return set()
        text = path.read_text(encoding="utf-8-sig", errors="replace")
        start = text.find(REGION_START)
        end = text.find(REGION_END)
        if start != -1 and end != -1 and end > start:
            text = text[:start] + text[end + len(REGION_END) :]
        return {m.group("name") for m in BULLET_TARGET.finditer(text)}


def check(state: CurationState) -> list[str]:
    """Return one line per disagreement. Empty means the records agree."""
    problems: list[str] = list(state.parse_errors)

    # 1. Every agent in `assignments` has a region whose body matches its list.
    for agent, assigned in sorted(state.assignments.items()):
        region = state.region_skills(agent)
        if region is None:
            # 4. An assignment naming an agent with no region can never be applied.
            if not state.agent_path(agent).exists():
                problems.append(f"assignments names '{agent}', but agents/{agent}.agent.md does not exist")
            else:
                problems.append(
                    f"assignments names '{agent}', but that agent carries no curated-skills region "
                    f"-- the assignment cannot be applied and is silently lost on reapply"
                )
            continue
        base = state.base_skills(agent)
        missing = [s for s in assigned if s not in region and s not in base]
        extra = [s for s in region if s not in assigned]
        promoted = [s for s in assigned if s not in region and s in base]
        if missing:
            problems.append(
                f"{agent}: assigned {sorted(missing)} but the region does not contain them "
                f"-- run /af-curate-skills --reapply"
            )
        if extra:
            problems.append(f"{agent}: the region contains {sorted(extra)}, which assignments does not list")
        if promoted:
            problems.append(
                f"{agent}: assigned {sorted(promoted)}, which are already base skills of that agent "
                f"-- reapply drops them; remove them from assignments to settle the record"
            )

    # 2. Every agent named in the sentinel's activated[].agents appears in assignments.
    for skill, agents in sorted(state.sentinel_agents.items()):
        for agent in agents:
            if agent not in state.assignments:
                problems.append(
                    f".af-skills-curated says '{skill}' is assigned to '{agent}', "
                    f"but assignments has no key for that agent -- reapply never visits it"
                )
            elif skill not in state.assignments[agent] and skill not in state.base_skills(agent):
                problems.append(
                    f".af-skills-curated says '{skill}' is assigned to '{agent}', "
                    f"but assignments[{agent}] does not list it"
                )

    # 3. Curated agent/skill pairs in the INDEX matrix appear in assignments.
    curated = set(state.activated) | set(state.sentinel_agents)
    for agent, skills in sorted(state.matrix.items()):
        for skill in skills:
            if skill not in curated:
                continue  # a base skill in the matrix says nothing about curation
            if skill in state.base_skills(agent):
                continue
            if skill not in state.assignments.get(agent, []):
                problems.append(f"INDEX.md lists '{skill}' for '{agent}', but assignments does not")

    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--project-dir", default=".", help="Project root containing .github/ (default: cwd)")
    parser.add_argument("--brief", action="store_true", help="Print nothing when the records agree")
    args = parser.parse_args()

    github_dir = Path(args.project_dir).resolve() / ".github"
    state = CurationState(github_dir)

    if not state.assignments_path.exists():
        if not args.brief:
            print("No curated-assignments.json -- this project has no curated skill state to reconcile.")
        return 0

    state.load()
    problems = check(state)

    if not problems:
        if not args.brief:
            agents = len(state.assignments)
            print(f"Curation state is consistent across all three records ({agents} agent(s) assigned).")
        return 0

    print("  Curated skill records disagree:")
    for problem in problems:
        print(f"    {problem}")
    print("  -> Run /af-curate-skills --reapply, or correct curated-assignments.json.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
