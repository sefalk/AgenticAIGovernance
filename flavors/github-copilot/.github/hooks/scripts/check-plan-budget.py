"""Pre-commit guard: reject staged plan documents over their complexity-tier budget.

Invoked by the ``.github/hooks/git/pre-commit`` shim. Measures every staged
``*.md`` under a ``plans/`` directory (``WIP.md`` excepted) against the ceiling
its own complexity tier earns, from ``.github/af-env.conf``.

Why a tier and not one flat limit: a Deep architectural change genuinely needs
the room a bug fix does not, and a single number for both is either useless for
one or punitive for the other. The tier is already assigned by the planner and
already written in the plan, so the budget can read it rather than guess.

Why enforce it here rather than instruct the planner to be brief: the plan is
produced by a model, and "keep it short" has no failure mode -- it produces a
long document and no signal. The staged blob is the one place where the size is
a fact rather than an intention.

Exit codes: 0 pass, 1 blocked, 2 internal error.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

TAG = "[plan-budget]"

# Same estimate as check-context-budget.py: calibrated against tiktoken, errs
# high by ~3%, which is the safe direction for a ceiling. Kept as a literal
# rather than imported -- this guard runs from a git hook with no package
# context, and a broken import would fail every commit.
CHARS_PER_TOKEN = 4

DEFAULT_BUDGETS = {"trivial": 0, "standard": 3000, "deep": 12000}

# `- **Complexity tier:** **Deep**` and `| Complexity Tier | Standard |` are
# both in use in the wild, so the separator is `:` or `|`, and the emphasis
# markers around the value are part of the noise rather than the statement.
TIER_PATTERNS = (
    re.compile(r"complexity\s+tier[\s*]*[:|][\s*]*(trivial|standard|deep)", re.IGNORECASE),
    re.compile(r"\btier[\s*]*[:|][\s*]*(trivial|standard|deep)", re.IGNORECASE),
)

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


def _read_budgets(conf_path: Path) -> dict[str, int]:
    budgets = dict(DEFAULT_BUDGETS)
    if not conf_path.is_file():
        return budgets
    text = conf_path.read_text(encoding="utf-8")
    for tier in budgets:
        match = re.search(rf"^PLAN_BUDGET_{tier.upper()}_TOKENS=(.+)$", text, re.MULTILINE)
        if match:
            value = match.group(1).strip()
            if value.isdigit():
                budgets[tier] = int(value)
    return budgets


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


def _tier(text: str) -> str | None:
    """The tier as the plan states it, or None.

    Template placeholders are HTML comments, so they are stripped first: an
    unfilled `<!-- Trivial / Standard / Deep -->` states nothing, and reading a
    tier out of it would let the template's own wording set the budget.
    """
    stripped = COMMENT.sub("", text)
    for pattern in TIER_PATTERNS:
        match = pattern.search(stripped)
        if match:
            return match.group(1).lower()
    return None


def _tokens(text: str) -> int:
    return len(text) // CHARS_PER_TOKEN


def _report(offenders: list[tuple[str, str | None, int, int]]) -> None:
    print(f"{TAG} COMMIT BLOCKED -- plan document(s) over the tier budget:")
    for path, tier, tokens, budget in offenders:
        stated = tier or "unstated, charged as standard"
        if budget == 0:
            print(f"  - {path}: {tokens:,} tok, tier {stated} -- a Trivial fix gets no plan file")
        else:
            print(f"  - {path}: {tokens:,} tok over {budget:,} ({tier or 'unstated'} tier)")
    print()
    print("To fix, in order of preference:")
    print("  - Cut sections the template does not define. Measured across 19 Standard")
    print("    plans, 45% of the text sat in headings invented for that one plan.")
    print("  - Shorten the subtask blocks. They are the largest named section by far")
    print("    (avg 6,607 characters). Acceptance criteria are the part that is read;")
    print("    the narrative around them is not.")
    print("  - Do not restate what the issue, the code, or the diff already says. The")
    print("    plan is a working document, not the record -- the workflow log and the")
    print("    retro carry traceability.")
    print("  - If the work genuinely is Deep, state that tier in the plan and the Deep")
    print("    budget applies. Raising a tier to fit a document is the wrong direction.")
    print("  - One-off override for this commit: ALLOW_PLAN_BUDGET=1 git commit ...")
    print("  - Adjust PLAN_BUDGET_*_TOKENS in .github/af-env.conf, with a stated reason.")


def main() -> int:
    if os.environ.get("ALLOW_PLAN_BUDGET", "").strip().lower() in {"1", "true", "yes"}:
        print(f"{TAG} ALLOW_PLAN_BUDGET override set -- skipping check.")
        return 0
    try:
        root = _repo_root()
        budgets = _read_budgets(root / ".github" / "af-env.conf")
        offenders: list[tuple[str, str | None, int, int]] = []
        for path in _staged_files():
            if not _is_plan(path):
                continue
            text = _staged_text(path)
            if text is None:
                continue
            tier = _tier(text)
            budget = budgets[tier] if tier else budgets["standard"]
            tokens = _tokens(text)
            if tokens > budget:
                offenders.append((path, tier, tokens, budget))
    except subprocess.CalledProcessError as exc:
        print(f"{TAG} ERROR: git command failed: {exc}", file=sys.stderr)
        return 2
    if not offenders:
        return 0
    _report(offenders)
    return 1


if __name__ == "__main__":
    sys.exit(main())
