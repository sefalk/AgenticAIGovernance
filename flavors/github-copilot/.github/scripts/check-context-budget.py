"""Context budget gate: fail when the always-on instruction payload regrows.

The always-on set is what VS Code prepends to *every* chat request in a project:
``copilot-instructions.md`` plus every ``instructions/*.md`` whose ``applyTo``
glob matches all files. It is fully computable offline -- no instrumentation
needed -- because the globs are static and the file sizes are known.

Instruction files grow by accretion: every new rule looks small in isolation,
and ``applyTo: '**'`` is the path of least resistance for an author who wants a
rule to be seen. This check turns that drift into a build failure.

Also reports the per-agent total (agent file + always-on set), so a single
agent prompt cannot silently regrow either.

The *conditional* files -- those with a narrower ``applyTo`` -- are measured
too. A narrow glob makes a file load less often; it does not make it cheap, and
for the agents whose job is to touch matching files it is close to always-on.
Which conditional files co-occur in a real turn is not computable offline, so
this reports the **upper bound** (all of them) per agent and puts the
enforcement on the conditional set as a whole.

Budgets come from ``.github/af-env.conf``:
  AF_CONTEXT_BUDGET_TOKENS        -- always-on set
  AF_AGENT_CONTEXT_BUDGET_TOKENS  -- agent file + always-on set, per agent
  AF_CONDITIONAL_BUDGET_TOKENS    -- all narrowly-scoped instruction files

Token figures are estimated as characters/4 and are used for drift detection
only; they are not a billed count. The divisor is calibrated against a real
tokenizer -- see ``CHARS_PER_TOKEN`` -- and ``--verify-tokenizer`` re-runs that
calibration wherever tiktoken is installed.

Exit codes: 0 pass, 1 over budget, 2 blocked (required input missing/unreadable).
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# Rough estimate, and deliberately dependency-free: a real tokenizer would make
# this gate unrunnable wherever that package is absent, and this is a drift gate
# -- it has to be invariant, not accurate.
#
# Characters, not bytes on disk. Bytes move when `core.autocrlf` flips, when an
# author types an em dash instead of a hyphen, or when an editor leaves a BOM --
# none of which change a single character the model reads. A gate whose whole
# job is detecting real change must not react to those (issue #59).
#
# The divisor is measured, not assumed. Calibrated 2026-08-12 with tiktoken
# (o200k_base, cross-checked against cl100k_base) over all 24 files this gate
# measures: 183,317 characters to 44,602 real tokens = 4.110 characters per
# token, per-file range 3.83-4.29. Characters/4 therefore lands within
# -4.2%/+7.2% per file (+2.8% median) and errs high -- it reports slightly more
# tokens than exist, which is the safe direction for a ceiling.
#
# It stays 4 rather than 4.11: the correction is smaller than the noise this
# gate exists to ignore, and it would relax all three budgets for nothing. The
# suspicion recorded in issue #59 -- that dense markdown runs 3-3.5 characters
# per token, so every budget understates reality by 15-30% -- was measured and
# is not true of this payload.
#
# `--verify-tokenizer` re-runs that measurement wherever tiktoken happens to be
# installed, so the constant stays falsifiable as the payload's character mix
# drifts.
CHARS_PER_TOKEN = 4

# applyTo globs that match every file. An author writing any of these means
# "always on"; anything narrower is conditional and not part of the budget.
UNIVERSAL_GLOBS = {"**", "**/*", "**/**", "*"}

DEFAULT_CONTEXT_BUDGET = 4950
DEFAULT_AGENT_BUDGET = 10900
DEFAULT_CONDITIONAL_BUDGET = 5500

TAG = "[context-budget]"


class Blocked(Exception):
    """A required input is missing or unreadable, so the result is unknown.

    Distinct from "over budget" on purpose: silence must not read as success.
    """


def _read_text(path: Path) -> str:
    """Read a file as text: universal newlines, BOM stripped.

    Both are deliberate. Text mode folds CRLF and lone CR to a single ``\\n``,
    and ``utf-8-sig`` drops a leading BOM, so the returned string is the content
    itself rather than an artefact of how it was checked out or saved.
    """
    try:
        return path.read_text(encoding="utf-8-sig")
    except OSError as exc:
        raise Blocked(f"cannot read {path}: {exc}") from exc
    except UnicodeDecodeError as exc:
        # Measuring it as bytes would be a guess, and letting the exception
        # escape would exit 1 -- indistinguishable from "over budget".
        raise Blocked(f"{path} is not valid UTF-8: {exc}") from exc


def _tokens(path: Path) -> int:
    return len(_read_text(path)) // CHARS_PER_TOKEN


def _frontmatter(text: str) -> str | None:
    """Return the YAML frontmatter block, or None when the file has none."""
    if not text.startswith("---"):
        return None
    end = text.find("\n---", 3)
    return None if end == -1 else text[3:end]


def _apply_to(path: Path) -> tuple[str | None, bool]:
    """Return (raw applyTo value, is_always_on) for an instruction file.

    A missing or empty ``applyTo`` counts as always-on: that is the expensive
    reading, and an ambiguous file should push the total up rather than hide in
    it. The caller surfaces it as a warning so the author can disambiguate.
    """
    front = _frontmatter(_read_text(path))
    if front is None:
        return None, True
    match = re.search(r"^applyTo:\s*(.+)$", front, re.MULTILINE)
    if not match:
        return None, True
    raw = match.group(1).strip().strip("'\"")
    if not raw:
        return None, True
    globs = {g.strip().strip("'\"") for g in raw.split(",") if g.strip()}
    return raw, bool(globs & UNIVERSAL_GLOBS)


def _read_budgets(conf_path: Path) -> tuple[int, int, int]:
    budgets = {
        "AF_CONTEXT_BUDGET_TOKENS": DEFAULT_CONTEXT_BUDGET,
        "AF_AGENT_CONTEXT_BUDGET_TOKENS": DEFAULT_AGENT_BUDGET,
        "AF_CONDITIONAL_BUDGET_TOKENS": DEFAULT_CONDITIONAL_BUDGET,
    }
    if conf_path.is_file():
        text = _read_text(conf_path)
        for key in budgets:
            match = re.search(rf"^{key}=(.*)$", text, re.MULTILINE)
            if not match:
                continue
            value = match.group(1).strip()
            if not value:
                continue
            if not value.isdigit() or int(value) <= 0:
                raise Blocked(f"{key} in af-env.conf is not a positive integer: {value!r}")
            budgets[key] = int(value)
    return (
        budgets["AF_CONTEXT_BUDGET_TOKENS"],
        budgets["AF_AGENT_CONTEXT_BUDGET_TOKENS"],
        budgets["AF_CONDITIONAL_BUDGET_TOKENS"],
    )


def _instruction_sets(
    github_dir: Path,
) -> tuple[list[tuple[str, int]], list[tuple[str, int, str]], list[str]]:
    """Split the instruction payload into what always loads and what may load.

    Parameters
    ----------
    github_dir : Path
        The ``.github`` directory to scan.

    Returns
    -------
    tuple[list[tuple[str, int]], list[tuple[str, int, str]], list[str]]
        Always-on entries ``(name, tokens)``, conditional entries
        ``(name, tokens, glob)``, and warnings about ambiguous files.
    """
    always_on: list[tuple[str, int]] = []
    conditional: list[tuple[str, int, str]] = []
    warnings: list[str] = []

    root_instructions = github_dir / "copilot-instructions.md"
    if not root_instructions.is_file():
        raise Blocked(f"copilot-instructions.md not found in {github_dir}")
    always_on.append((root_instructions.name, _tokens(root_instructions)))

    instructions_dir = github_dir / "instructions"
    if not instructions_dir.is_dir():
        raise Blocked(f"instructions/ directory not found in {github_dir}")

    for path in sorted(instructions_dir.glob("*.md")):
        raw, is_always_on = _apply_to(path)
        if is_always_on:
            if raw is None:
                warnings.append(f"{path.name} has no applyTo -- counted as always-on")
            always_on.append((path.name, _tokens(path)))
        else:
            conditional.append((path.name, _tokens(path), raw or ""))
    return always_on, conditional, warnings


def _agent_totals(
    github_dir: Path, always_on_total: int, conditional_total: int
) -> list[tuple[str, int, int, int]]:
    """Return per-agent ``(name, own, unconditional, worst_case)``, worst first.

    ``worst_case`` assumes every conditional file matches at once. It is an
    upper bound, not an estimate: co-occurrence depends on which files are in
    context during a turn, which cannot be known offline.
    """
    agents_dir = github_dir / "agents"
    if not agents_dir.is_dir():
        raise Blocked(f"agents/ directory not found in {github_dir}")
    totals = [
        (
            path.stem.replace(".agent", ""),
            _tokens(path),
            _tokens(path) + always_on_total,
            _tokens(path) + always_on_total + conditional_total,
        )
        for path in sorted(agents_dir.glob("*.agent.md"))
    ]
    if not totals:
        raise Blocked(f"no agent files found in {agents_dir}")
    return sorted(totals, key=lambda row: row[2], reverse=True)


def _print_breakdown(entries: list[tuple[str, int]], total: int, budget: int) -> None:
    print(f"{TAG} always-on set -- sent with every chat request:")
    for name, tokens in sorted(entries, key=lambda row: row[1], reverse=True):
        print(f"  {tokens:6,} tok  {name}")
    print(f"  {'-' * 6}")
    print(f"  {total:6,} tok  TOTAL (budget {budget:,})")


def _measured_files(github_dir: Path) -> list[Path]:
    """Every file the budgets are computed from, in report order."""
    paths = [github_dir / "copilot-instructions.md"]
    paths += sorted((github_dir / "instructions").glob("*.md"))
    paths += sorted((github_dir / "agents").glob("*.agent.md"))
    return [path for path in paths if path.is_file()]


def _verify_tokenizer(github_dir: Path) -> int:
    """Re-measure characters-per-token against a real tokenizer.

    A development aid, not part of the gate. It may import tiktoken; the gate
    itself must not, or it stops running wherever that package is absent.

    Returns 1 when the aggregate error exceeds 10%, because these figures are
    quoted to humans as "tokens" in plan documents and pull request bodies. A
    constant that has drifted that far is no longer describing the payload.
    """
    try:
        import tiktoken
    except ImportError as exc:
        # Not exit 0: an unrun verification is an unknown result, and the whole
        # point of this flag is to make the constant falsifiable.
        raise Blocked(
            "--verify-tokenizer needs tiktoken, which is not installed. Install it "
            "in a throwaway environment; the gate itself must stay dependency-free."
        ) from exc

    paths = _measured_files(github_dir)
    if not paths:
        raise Blocked(f"no measurable payload files under {github_dir}")

    encoding = tiktoken.get_encoding("o200k_base")
    print(f"{TAG} tokenizer verification -- o200k_base vs characters/{CHARS_PER_TOKEN}")
    print(f"  {'file':<44} {'chars':>8} {'est':>7} {'actual':>7} {'error':>7}")

    total_chars = 0
    total_actual = 0
    worst_error = 0.0
    worst_name = ""
    for path in paths:
        text = _read_text(path)
        actual = len(encoding.encode(text))
        if not actual:
            continue
        estimate = len(text) // CHARS_PER_TOKEN
        error = (estimate - actual) / actual * 100
        total_chars += len(text)
        total_actual += actual
        if abs(error) > abs(worst_error):
            worst_error, worst_name = error, path.name
        print(f"  {path.name:<44} {len(text):>8,} {estimate:>7,} {actual:>7,} {error:>+6.1f}%")

    if not total_actual:
        raise Blocked("tokenizer returned no tokens for the payload")

    ratio = total_chars / total_actual
    aggregate_error = (total_chars / CHARS_PER_TOKEN - total_actual) / total_actual * 100
    print(f"  {'-' * 44}")
    print(f"  {len(paths)} files: {total_chars:,} chars, {total_actual:,} real tokens")
    print(f"  measured ratio {ratio:.3f} chars/token (divisor in use: {CHARS_PER_TOKEN})")
    print(f"  aggregate error {aggregate_error:+.1f}%, worst file {worst_error:+.1f}% ({worst_name})")

    if abs(aggregate_error) > 10:
        print()
        print(
            f"{TAG} FAIL -- the divisor is {abs(aggregate_error):.1f}% off; "
            f"the payload now measures {ratio:.3f} chars/token."
        )
        print("Update CHARS_PER_TOKEN and the calibration note beside the budgets.")
        return 1

    print(f"{TAG} PASS -- divisor {CHARS_PER_TOKEN} is within 10% of the measured ratio.")
    return 0


def _print_conditional(entries: list[tuple[str, int, str]], total: int, budget: int) -> None:
    print(f"{TAG} conditional set -- loaded when a matching file is in context:")
    for name, tokens, glob in sorted(entries, key=lambda row: row[1], reverse=True):
        print(f"  {tokens:6,} tok  {name:<40} {glob}")
    print(f"  {'-' * 6}")
    print(f"  {total:6,} tok  TOTAL (budget {budget:,})")


def _print_agents(
    totals: list[tuple[str, int, int, int]], agent_budget: int, conditional_total: int
) -> None:
    print(f"{TAG} per-agent worst case (own + always-on + all {conditional_total:,} conditional):")
    for name, own, unconditional, worst in totals:
        print(f"  {worst:6,} tok  {name:<24} (own {own:,}, unconditional {unconditional:,})")
    over = [row for row in totals if row[3] > agent_budget]
    if over:
        # Marking each row instead would repeat one shared cause fifteen times.
        print(
            f"  worst case exceeds agent budget ({agent_budget:,}) for "
            f"{len(over)} of {len(totals)} agents -- the conditional set is in every row."
        )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Fail when the always-on instruction payload exceeds its budget.",
        epilog="Budgets: AF_CONTEXT_BUDGET_TOKENS, AF_AGENT_CONTEXT_BUDGET_TOKENS, "
               "AF_CONDITIONAL_BUDGET_TOKENS in .github/af-env.conf.",
    )
    parser.add_argument(
        "--github-dir", type=Path, default=None,
        help="Path to the .github directory (defaults to the one containing this script)",
    )
    parser.add_argument(
        "--verbose", action="store_true",
        help="Print the per-file breakdown even when the check passes",
    )
    parser.add_argument(
        "--verify-tokenizer", action="store_true",
        help="Re-measure characters-per-token with tiktoken and report the drift "
             "against the hardcoded divisor, instead of checking budgets "
             "(development aid; requires tiktoken)",
    )
    args = parser.parse_args(argv)

    # This script lives at <github-dir>/scripts/, which resolves correctly both
    # in the AF source tree and in a deployed project.
    github_dir = args.github_dir or Path(__file__).resolve().parents[1]

    try:
        if not github_dir.is_dir():
            raise Blocked(f"github directory not found: {github_dir}")
        if args.verify_tokenizer:
            return _verify_tokenizer(github_dir)
        context_budget, agent_budget, conditional_budget = _read_budgets(github_dir / "af-env.conf")
        entries, conditional_entries, warnings = _instruction_sets(github_dir)
        always_on_total = sum(tokens for _, tokens in entries)
        conditional_total = sum(tokens for _, tokens, _ in conditional_entries)
        agent_totals = _agent_totals(github_dir, always_on_total, conditional_total)
    except Blocked as exc:
        print(f"{TAG} BLOCKED -- {exc}", file=sys.stderr)
        print(f"{TAG} Result unknown, not passing. Fix the input and re-run.", file=sys.stderr)
        return 2

    for warning in warnings:
        print(f"{TAG} WARNING: {warning}")

    worst_agent, worst_agent_tokens, worst_total, _ = agent_totals[0]
    over_context = always_on_total > context_budget
    over_agent = worst_total > agent_budget
    over_conditional = conditional_total > conditional_budget

    if not (over_context or over_agent or over_conditional):
        if args.verbose:
            _print_breakdown(entries, always_on_total, context_budget)
            print()
            if conditional_entries:
                _print_conditional(conditional_entries, conditional_total, conditional_budget)
                print()
            _print_agents(agent_totals, agent_budget, conditional_total)
            print()
        print(
            f"{TAG} PASS -- always-on {always_on_total:,}/{context_budget:,} tok; "
            f"conditional {conditional_total:,}/{conditional_budget:,} tok; "
            f"largest agent {worst_agent} {worst_total:,}/{agent_budget:,} tok"
        )
        return 0

    if over_context:
        _print_breakdown(entries, always_on_total, context_budget)
        print()
        print(
            f"{TAG} FAIL -- always-on set is {always_on_total - context_budget:,} tok "
            f"over budget ({always_on_total:,} > {context_budget:,})."
        )
        print()
        print("To fix, in order of preference:")
        print("  - Narrow the applyTo glob so the file loads only when relevant.")
        print("  - Move depth into a skill (loaded on demand) or the owning agent file.")
        print("  - Delete duplication -- check whether the rule already exists elsewhere.")
        print("  - Raise AF_CONTEXT_BUDGET_TOKENS only as a deliberate, justified decision.")

    if over_conditional:
        if over_context:
            print()
        _print_conditional(conditional_entries, conditional_total, conditional_budget)
        print()
        print(
            f"{TAG} FAIL -- conditional set is {conditional_total - conditional_budget:,} tok "
            f"over budget ({conditional_total:,} > {conditional_budget:,})."
        )
        print()
        print("A narrow applyTo makes a file load less often, not cheaply: for the")
        print("agents whose job is to touch matching files it is effectively always-on.")
        print("  - Move reference depth into a skill; keep the contract in the instruction.")
        print("  - Check the glob is not broader than the rule it carries.")

    if over_agent:
        if over_context or over_conditional:
            print()
        print(f"{TAG} agent context totals (agent file + always-on set):")
        for name, own, total, worst in agent_totals:
            marker = "  <-- over budget" if total > agent_budget else ""
            print(f"  {total:6,} tok  {name} (own {own:,}, worst case {worst:,}){marker}")
        print()
        print(
            f"{TAG} FAIL -- {worst_agent} is {worst_total - agent_budget:,} tok over "
            f"budget ({worst_total:,} > {agent_budget:,}); own prompt {worst_agent_tokens:,} tok."
        )

    return 1


if __name__ == "__main__":
    sys.exit(main())
