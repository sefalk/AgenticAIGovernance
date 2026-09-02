"""Guard the work-item state contract: transitions are resolved, never named.

Issue #267 was not a typo. The framework mandated a transition to `Resolved`,
the `Task` type has no such state, and nothing in the repository could notice
the contradiction — so items were unclosable by construction and the gate that
caused it read as correct prose. Measurement (`wit_work_item` action
`get_type`, Agile template) also showed `Resolved` sitting in a *different*
state category on `User Story` than on `Bug`, so matching the name is wrong
even where the name exists.

The fix is a role resolved from the type. These assertions fail when someone
writes the state name back into a transition, when the guard loses one of its
paths, or when the skill and the agent drift apart on what the target is.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PAYLOAD = REPO / "flavors" / "github-copilot" / ".github"
AGENT = PAYLOAD / "agents" / "ado-work-item-manager.agent.md"
SHARED = PAYLOAD / "skills" / "ado-shared" / "SKILL.md"
WORKITEM = PAYLOAD / "skills" / "ado-workitem" / "SKILL.md"
GITFLOW = PAYLOAD / "skills" / "git-workflow" / "SKILL.md"

GUARD_HEADING = "## State-Applicability Guard"
TAG = "delivered-pending-verification"
STATUS = "BLOCKED_NO_DELIVERED_STATE"

# Phrasings that promise a named state instead of resolving one from the type.
# Each is a way the old contract was actually written somewhere in the payload.
BANNED = [
    r"reconcile:\s*Resolved",
    r"to \*\*Resolved\*\*",
    r"set \*\*Resolved\*\*",
    r"at most \*\*Resolved\*\*",
    r"leave \*\*Resolved\*\*",
    r"\*\*\u2192 Resolved\*\*",
    r"\*\*-> Resolved\*\*",
]

failures: list[str] = []
checks = 0


def check(label: str, condition: bool, detail: str = "") -> None:
    global checks
    checks += 1
    if not condition:
        failures.append(f"{label}{': ' + detail if detail else ''}")


def section(text: str, heading: str) -> str:
    """Return the text from a heading up to the next one outside a code fence.

    The fence tracking is not decoration: the Return Format section embeds a
    fenced block that itself starts with `## ADO Work Item Result`, and a naive
    search ends the section there — silently, on the exact heading whose body
    this guard has to inspect.
    """
    lines = text.splitlines()
    out: list[str] = []
    fenced = False
    started = False
    for line in lines:
        if line.startswith("```"):
            fenced = not fenced
        if not started:
            started = line.startswith(heading)
            if started:
                out.append(line)
            continue
        if not fenced and line.startswith("## "):
            break
        out.append(line)
    return "\n".join(out)


def row(text: str, first_cell: str) -> str:
    """Return the markdown table row whose first cell is `first_cell`."""
    for line in text.splitlines():
        if line.strip().startswith(f"| {first_cell} |"):
            return line
    return ""


def main() -> int:
    for label, path in (
        ("agent", AGENT),
        ("ado-shared skill", SHARED),
        ("ado-workitem skill", WORKITEM),
        ("git-workflow skill", GITFLOW),
    ):
        check(f"{label} file exists", path.is_file(), str(path))
    if failures:
        print("\n".join(f"FAIL {f}" for f in failures))
        return 1

    agent = AGENT.read_text(encoding="utf-8")
    shared = SHARED.read_text(encoding="utf-8")
    workitem = WORKITEM.read_text(encoding="utf-8")
    gitflow = GITFLOW.read_text(encoding="utf-8")

    # ── The guard itself ────────────────────────────────────────────────
    guard = section(agent, GUARD_HEADING)
    check("agent has a State-Applicability Guard", bool(guard))

    check("guard probes the type", "get_type" in guard)
    check("guard reads the state list", "states[]" in guard)
    check("guard resolves by category", "category `Resolved`" in guard and "category `InProgress`" in guard)
    check("guard refuses to guess between candidates", "NEEDS_CONFIRMATION" in guard)
    check(f"guard names the {STATUS} outcome", STATUS in guard)
    check(f"guard names the {TAG} tag", TAG in guard)

    for path_label, needle in (
        ("on create", "**On create:**"),
        ("on an existing item", "**On an existing item:**"),
        ("type must remain", "**If the type must remain:**"),
    ):
        check(f"guard keeps the '{path_label}' path", needle in guard)

    check(
        "guard forbids closing as the escape hatch",
        "closing authority" in guard and "`Completed`-category state" in guard,
    )

    # ── The measurement that justifies the rule stays in the document ───
    task_row = row(guard, "Task")
    story_row = row(guard, "User Story")
    bug_row = row(guard, "Bug")
    check("guard shows the measured Task states", bool(task_row))
    check(
        "the Task row still shows no Resolved state",
        bool(task_row) and "Resolved" not in task_row,
        task_row.strip(),
    )
    check(
        "the User Story row keeps the category mismatch that defeats name-matching",
        "Resolved (**InProgress**)" in story_row,
        story_row.strip(),
    )
    check("the Bug row keeps its Resolved category", "Resolved (**Resolved**)" in bug_row, bug_row.strip())

    # ── Wiring: responsibilities, return format, exit gates ─────────────
    check("responsibilities name the guard", "**State-Applicability Guard**" in section(agent, "## Responsibilities"))

    ret = section(agent, "## Return Format")
    check(f"return status enum offers {STATUS}", STATUS in ret)
    check("return format reports the resolved mapping", "**Delivered-state mapping:**" in ret)

    gates = section(agent, "## Exit Gates")
    probe_gates = [
        ln for ln in gates.splitlines() if "get_type" in ln and "| HARD |" in ln and "transition" in ln.lower()
    ]
    check("a HARD exit gate requires the type probe before transitions", bool(probe_gates))
    check(
        f"the probe gate names the {STATUS} outcome",
        any(STATUS in ln for ln in probe_gates),
    )
    finalize_gates = [ln for ln in gates.splitlines() if "finalize" in ln.lower() and "| HARD |" in ln]
    check("the finalize gate survives", bool(finalize_gates))
    check(
        "the finalize gate is stated in categories, not state names",
        any("`Completed`-category" in ln for ln in finalize_gates),
    )
    check(
        "the finalize gate rejects Active as a silent outcome",
        any("silent outcome" in ln for ln in finalize_gates),
    )

    # ── The type-selection rule that prevents the situation ─────────────
    selection = "#### Work-item type selection"
    check("ado-shared carries a type-selection rule", selection in shared)
    sel = shared[shared.find(selection) :] if selection in shared else ""
    sel = sel[: sel.find("\n### ")] if "\n### " in sel else sel
    for wit_type in ("Feature", "User Story", "Bug", "Task"):
        check(f"type-selection rule covers {wit_type}", f"**{wit_type}**" in sel)
    check("type-selection rule states the measured Task constraint", "no `Resolved`" in sel)
    check("type-selection rule points at the guard", "State-Applicability Guard" in sel)

    # ── Reconciliation is type-aware and honest about auto-transition ───
    recon = section(shared, "### Post-Merge Reconciliation")
    check("reconciliation resolves the target via the probe", "get_type" in recon)
    check("reconciliation defers to the guard", "State-Applicability Guard" in recon)
    check(
        "reconciliation records why ADO's auto-transition never fires here",
        "default" in recon and "auto-transition" in recon,
    )

    # ── Cross-file drift ────────────────────────────────────────────────
    check("ado-workitem closure discipline points at the guard", "State-Applicability Guard" in workitem)
    check(
        "git-workflow lifecycle resolves the delivered state from the type",
        "resolved from the work-item type" in gitflow,
    )

    scanned = sorted(PAYLOAD.glob("skills/*/SKILL.md")) + sorted(PAYLOAD.glob("agents/ado-*.agent.md"))
    check("drift scan covers the payload", len(scanned) > 10, f"{len(scanned)} files")
    for pattern in BANNED:
        hits = [
            f"{p.relative_to(PAYLOAD)}:{i}"
            for p in scanned
            for i, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1)
            if re.search(pattern, line)
        ]
        check(f"no transition promises a named state ({pattern})", not hits, ", ".join(hits))

    if failures:
        print("\n".join(f"FAIL {f}" for f in failures))
        print(f"\n{len(failures)} of {checks} checks failed")
        return 1
    print(f"OK  work-item state contract: {checks} checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
