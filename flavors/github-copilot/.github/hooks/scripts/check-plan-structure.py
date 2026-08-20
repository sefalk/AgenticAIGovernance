"""Pre-commit guard: reject staged plan documents whose structure is incomplete.

Invoked by the ``.github/hooks/git/pre-commit`` shim, over the same scope as
``check-plan-budget.py``: every staged ``*.md`` under a ``plans/`` directory
except ``WIP.md``.

The plan is the only artifact the framework produces that no agent reviews --
tests have the test-critic, code has the code-critic, the process has the
compliance-checker, and the plan has a subtask count. This guard is not that
reviewer. It cannot tell whether an acceptance criterion is useful; it can tell
that one exists and is not still the template's placeholder, which is the defect
class an unreviewed plan actually carries.

What it deliberately does not do: reject a Standard plan for containing a
section the template reserves for Deep. Thoroughness beyond the tier is already
paid for by the budget guard, and a rule that punished it would be telling
authors to write less than they know.

Exit codes: 0 pass, 1 blocked, 2 internal error.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

TAG = "[plan-structure]"

# Section names the templates define. Anything else is a heading invented for one
# document -- measured at 45% of the text across 19 Standard plans (#26).
PLAN_SECTIONS = frozenset(
    {
        "context",
        "references",
        "scope assessment",
        "current baseline",
        "subtasks",
        "implementation sequence",
        "quality gates",
        "plan approval",
        "open findings",
        "follow-up",
        "change log",
    }
)
INVESTIGATION_SECTIONS = frozenset(
    {
        "trigger",
        "root cause analysis",
        "fix description",
        "alternatives considered",
        "validation approach",
        "quality gates",
        "change log",
    }
)
INVESTIGATION_REQUIRED = ("trigger", "root cause analysis", "fix description", "validation approach")

# The document's own title, in the shapes the templates and the planner produce.
TITLE = re.compile(r"^(implementation plan\b.*|investigation\b.*|plan\s*[:\u2014-].*)$", re.IGNORECASE)

# `### 1. Extract the mapping` / `#### 2) ...` -- a subtask block, not a section.
SUBTASK = re.compile(r"^\d+[.)]")
# Deep-tier plans may organise subtasks as phases; the template says so.
PHASE = re.compile(r"^phase\b", re.IGNORECASE)

HEADING = re.compile(r"^(#{2,4})\s+(.+?)\s*$")

# A field whose value is still the template comment: `- **Action:** <!-- ... -->`
PLACEHOLDER_FIELD = re.compile(r"^\s*(?:[-*]\s*)?\*\*(?P<field>[^*]+?):?\*\*\s*<!--.*-->\s*$")

FIELD = re.compile(r"^\s*(?:[-*]\s*)?\*\*(?P<field>[^*]+?):?\*\*")

BULLET = re.compile(r"^\s+[-*]\s+\S")

SCOPE_FIELDS = ("files affected", "layers touched", "complexity tier", "estimated size", "risks")
SUBTASK_FIELDS = ("acceptance criteria", "files", "exit criterion")

TIER = re.compile(r"complexity\s+tier[\s*]*[:|][\s*]*(trivial|standard|deep)", re.IGNORECASE)
STATUS_DRAFT = re.compile(r"^\*\*status:?\*\*\s*:?\s*draft\b", re.IGNORECASE | re.MULTILINE)
COMMENT = re.compile(r"<!--.*?-->", re.DOTALL)


def _repo_root() -> Path:
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=True,
    )
    return Path(result.stdout.strip())


def _staged_files() -> list[str]:
    result = subprocess.run(
        ["git", "-c", "core.quotePath=false", "diff", "--cached", "-z", "--name-only", "--diff-filter=ACMR"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=True,
    )
    return [entry for entry in result.stdout.split("\0") if entry]


def _is_plan(path: str) -> bool:
    parts = path.split("/")
    if not parts[-1].lower().endswith(".md") or parts[-1] == "WIP.md":
        return False
    return "plans" in parts[:-1]


def _staged_text(path: str) -> str | None:
    listed = subprocess.run(
        ["git", "ls-files", "-s", "--", f":(literal){path}"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=True,
    )
    line = listed.stdout.strip()
    if not line:
        return None
    fields = line.split()  # "<mode> <blob-sha> <stage>\t<path>"
    if len(fields) < 2:
        return None
    blob = subprocess.run(
        ["git", "cat-file", "blob", fields[1]],
        capture_output=True,
        check=True,
    )
    return blob.stdout.decode("utf-8", errors="replace")


def _normalise(heading: str) -> str:
    text = heading.strip().strip("#").strip()
    text = re.sub(r"[`*_]", "", text)
    text = re.sub(r"\s*\(optional\)\s*$", "", text, flags=re.IGNORECASE)
    return text.strip().lower()


def _kind(text: str) -> str:
    """Which template the document follows. Both kinds live in the plans dir."""
    for line in text.splitlines():
        match = re.match(r"^#{1,2}\s+(.+?)\s*$", line)
        if match and _normalise(match.group(1)).startswith("investigation"):
            return "investigation"
    return "plan"


def _blocks(text: str, known: frozenset[str]) -> tuple[list[str], list[tuple[str, list[str]]]]:
    """Split the document into its sections and its subtask blocks.

    Returns the headings no template section explains, and the body lines of
    every subtask block. A list, not a map: two subtasks numbered `1.` are two
    subtasks, and collapsing them would hide one from the check.
    """
    unknown: list[str] = []
    subtasks: list[tuple[str, list[str]]] = []
    in_subtask = False
    for line in text.splitlines():
        match = HEADING.match(line)
        if match:
            name = _normalise(match.group(2))
            in_subtask = False
            if TITLE.match(name) or name in known:
                continue
            if SUBTASK.match(name) or PHASE.match(name):
                subtasks.append((name, []))
                in_subtask = True
                continue
            unknown.append(match.group(2).strip())
            continue
        if in_subtask:
            subtasks[-1][1].append(line)
    return unknown, subtasks


def _section_body(text: str, section: str) -> list[str]:
    body: list[str] = []
    inside = False
    for line in text.splitlines():
        match = HEADING.match(line)
        if match:
            inside = _normalise(match.group(2)) == section
            continue
        if inside:
            body.append(line)
    return body


def _fields(lines: list[str]) -> set[str]:
    found = set()
    for line in lines:
        match = FIELD.match(line)
        if match:
            found.add(match.group("field").strip().lower())
    return found


def _list(items: list[str], limit: int = 5) -> str:
    shown = ", ".join(items[:limit])
    return shown + (f" (and {len(items) - limit} more)" if len(items) > limit else "")


def _has_criteria(lines: list[str]) -> bool:
    """An acceptance-criteria label followed by at least one indented bullet."""
    for index, line in enumerate(lines):
        match = FIELD.match(line)
        if match and match.group("field").strip().lower() == "acceptance criteria":
            rest = line.split("**", 2)[-1].strip()
            if rest and not rest.startswith("<!--"):
                return True
            for follower in lines[index + 1 :]:
                if not follower.strip():
                    continue
                return bool(BULLET.match(follower))
    return False


def _findings(text: str) -> list[str]:
    kind = _kind(text)
    known = INVESTIGATION_SECTIONS if kind == "investigation" else PLAN_SECTIONS
    findings: list[str] = []

    placeholders = [
        match.group("field").strip() for match in (PLACEHOLDER_FIELD.match(line) for line in text.splitlines()) if match
    ]
    if placeholders:
        findings.append("fields left as template placeholders: " + _list(placeholders))

    unknown, subtasks = _blocks(text, known)
    if unknown:
        findings.append(f"sections {kind} documents do not define: " + _list(unknown))

    if kind == "investigation":
        present = {_normalise(m.group(2)) for m in (HEADING.match(line) for line in text.splitlines()) if m}
        missing = [name for name in INVESTIGATION_REQUIRED if name not in present]
        if missing:
            findings.append("investigation is missing: " + ", ".join(missing))
        return findings

    if not TIER.search(COMMENT.sub("", text)):
        findings.append("no complexity tier stated in Scope Assessment")

    scope = _fields(_section_body(text, "scope assessment"))
    missing_scope = [name for name in SCOPE_FIELDS if name not in scope]
    if missing_scope:
        findings.append("Scope Assessment is missing: " + ", ".join(missing_scope))

    if not subtasks:
        findings.append("no subtasks -- a plan with nothing to hand to the implementer plans nothing")
    for name, lines in subtasks:
        if PHASE.match(name):
            continue
        present_fields = _fields(lines)
        missing_fields = [f for f in SUBTASK_FIELDS if f not in present_fields]
        if missing_fields:
            findings.append(f"subtask '{name}' is missing: " + ", ".join(missing_fields))
        elif not _has_criteria(lines):
            findings.append(f"subtask '{name}' states acceptance criteria but lists none")
    return findings


def main() -> int:
    if os.environ.get("ALLOW_PLAN_STRUCTURE", "").strip().lower() in {"1", "true", "yes"}:
        print(f"{TAG} ALLOW_PLAN_STRUCTURE override set -- skipping check.")
        return 0
    offenders: dict[str, list[str]] = {}
    drafts: list[str] = []
    try:
        _repo_root()
        for path in _staged_files():
            if not _is_plan(path):
                continue
            text = _staged_text(path)
            if text is None:
                continue
            # A DRAFT says outright that it is unfinished; checking it would only
            # teach authors to leave the status at DRAFT. Naming it keeps that
            # from becoming a quiet way out.
            if STATUS_DRAFT.search(text):
                drafts.append(path)
                continue
            findings = _findings(text)
            if findings:
                offenders[path] = findings
    except subprocess.CalledProcessError as exc:
        print(f"{TAG} ERROR: git command failed: {exc}", file=sys.stderr)
        return 2

    for path in drafts:
        print(f"{TAG} {path} is marked DRAFT -- structure not checked.")
    if not offenders:
        return 0

    print(f"{TAG} COMMIT BLOCKED -- plan document(s) incomplete:")
    for path, findings in offenders.items():
        print(f"  {path}")
        for finding in findings:
            print(f"    - {finding}")
    print()
    print("To fix:")
    print("  - Fill the field, or delete the section the template marks optional.")
    print("    A placeholder left in place is not a shorter plan, it is an unanswered one.")
    print("  - Put findings that need a home into Risks, into a subtask, or into a")
    print("    separate investigation document -- not into a new heading.")
    print("  - Acceptance criteria are what the implementer and the critics act on.")
    print("    A subtask without them hands the decision to whoever reads it next.")
    print("  - Still drafting: set **Status:** DRAFT and this guard stands down.")
    print("  - One-off override for this commit: ALLOW_PLAN_STRUCTURE=1 git commit ...")
    return 1


if __name__ == "__main__":
    sys.exit(main())
