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

The **catalogue** set is the third payload, and until issue #206 it was gated by
nothing. Every skill, agent and instruction file is announced to the model by
name and description before anything is invoked -- the discovery level of VS
Code's three-level loading -- and those announcements ship on every request
whether or not the thing they describe is ever loaded. It is the same accretion
problem as the always-on set with none of the friction: adding a skill feels
free precisely because its body is not sent, and the description that *is* sent
never appeared on any ledger. Note that an always-on instruction file is paid
twice -- once for its catalogue entry, once for the full attachment.

Budgets come from ``.github/af-env.conf``, and there are two sets of them,
because there are two authors. The framework controls the files it ships; the
project controls its own ``copilot-instructions.md``, its own architecture
instructions, and anything it adds. Charging both to one ceiling meant the
project's allowance was whatever the framework had not spent -- so every
consumer failed on arrival and the available responses were to raise the
ceiling until it passed, or to shrink the project's own self-description to fit
(issue #107). Ownership is read from ``.af-manifest`` (``[customizable]``) and
``.af-hashes`` (what AF actually deployed here).

  AF_CONTEXT_BUDGET_TOKENS                -- AF's always-on set
  AF_AGENT_CONTEXT_BUDGET_TOKENS          -- agent file + AF's always-on set
  AF_CONDITIONAL_BUDGET_TOKENS            -- AF's narrowly-scoped files
  AF_CATALOGUE_BUDGET_TOKENS              -- AF's skill/agent/instruction listings
  AF_PROJECT_CONTEXT_BUDGET_TOKENS        -- the project's always-on set
  AF_PROJECT_CONDITIONAL_BUDGET_TOKENS    -- the project's narrowly-scoped files
  AF_PROJECT_CATALOGUE_BUDGET_TOKENS      -- the project's own listings

The project set has no default. Unset, the project share is measured, printed
and left ungated: a project that never stated a baseline has not drifted from
one. ``--seed-project-budget`` records that baseline; deploy runs it on a fresh
install.

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
from datetime import datetime, timezone
from pathlib import Path
from typing import NamedTuple

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

# The XML envelope VS Code wraps each catalogue entry in. Transcribed from a
# delivered system prompt rather than estimated -- the envelope is roughly a
# quarter of a short entry, so leaving it out would understate the payload most
# for exactly the entries an author thinks are free.
#
# The `<file>` path is deliberately NOT modelled. VS Code emits an absolute
# path, so the same repository measures differently depending on how deep it is
# checked out. This gate exists to detect drift in what the repository controls;
# a number that moves when someone clones to a different directory would detect
# the directory instead. The omission errs low by roughly len(path)/4 tokens per
# entry -- documented here rather than papered over with a fudge factor.
SKILL_ENTRY_TAGS = len("<skill>\n<name></name>\n<description></description>\n<file></file>\n</skill>\n")
AGENT_ENTRY_TAGS = len("<agent>\n<name></name>\n<description></description>\n</agent>\n")
AGENT_HINT_TAGS = len("<argumentHint></argumentHint>\n")
INSTRUCTION_ENTRY_TAGS = len(
    "<instruction>\n<file></file>\n<description></description>\n<applyTo></applyTo>\n</instruction>\n"
)

# Skill directories whose name starts with this are dormant: present in the
# repository, deliberately not deployed, and therefore not announced to anyone.
# They cost nothing here, which is precisely the problem issue #222 tracks --
# invisible costs nothing and is also indistinguishable from absent.
DORMANT_PREFIX = "_"

# The three AF ceilings cover only the files the framework controls -- the
# payload minus everything the manifest marks [customizable]. A consumer's own
# instructions are charged to AF_PROJECT_* instead (issue #107); before the
# split, AF's own three always-on files took 3,461 of a 4,950 ceiling and left
# 1,489 for the project's copilot-instructions.md, which AF's own template
# invites it to fill. That is not a budget, it is a leftover.
DEFAULT_CONTEXT_BUDGET = 3500
DEFAULT_AGENT_BUDGET = 9450
DEFAULT_CONDITIONAL_BUDGET = 3850
# Calibrated 2026-08-26 against the AF payload: 29 skills 1,906 tok, 17 agents
# 1,040 tok, 7 instruction entries 376 tok = 3,322 tok, plus ~2.3% headroom.
#
# Cross-checked against the delivered payload measured by the entity collector
# (issue #214, session 053fc66d), which is how the omitted `<file>` path was
# confirmed rather than assumed:
#
#   agents        model 1,040 (17)  delivered 1,129 (18, one editor built-in)
#   instructions  model   422 ( 7)  delivered   651 ( 7)
#
# Agent entries carry no path and agree to within one entry. Instruction entries
# do carry one, and the 229-token gap is 7 absolute Windows paths at ~130 chars
# -- the model's stated blind spot, arriving at the size the model predicts.
# Skills differ more (model 1,906, delivered 3,631) because the delivered block
# also announces the editor's own built-in skills, which no repository owns.
DEFAULT_CATALOGUE_BUDGET = 3400

# Headroom applied by --seed-project-budget over what a project measures today.
PROJECT_SEED_HEADROOM = 0.10

TAG = "[context-budget]"


class Budgets(NamedTuple):
    """The ceilings. The project entries are ``None`` when never seeded."""

    af_context: int
    af_agent: int
    af_conditional: int
    af_catalogue: int
    project_context: int | None
    project_conditional: int | None
    project_catalogue: int | None


class CatalogueEntry(NamedTuple):
    """One name/description announcement in the always-on catalogue payload."""

    kind: str
    name: str
    tokens: int
    is_project: bool


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


def _frontmatter_value(text: str, key: str) -> str:
    """Return a scalar frontmatter value, following YAML block scalars.

    ``description: >-`` followed by an indented body is valid YAML and would
    otherwise measure as two characters -- a silent undercount in the one
    payload this function exists to size, and worst for the longest
    descriptions, which are the ones most likely to be written that way.
    """
    front = _frontmatter(text)
    if front is None:
        return ""
    lines = front.splitlines()
    for index, line in enumerate(lines):
        match = re.match(rf"^{re.escape(key)}:\s*(.*)$", line)
        if not match:
            continue
        value = match.group(1).strip()
        if value and value[0] not in "|>":
            return value.strip("'\"")
        body: list[str] = []
        for continuation in lines[index + 1 :]:
            if continuation.strip() and not continuation.startswith((" ", "\t")):
                break
            body.append(continuation.strip())
        return " ".join(part for part in body if part)
    return ""


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


def _customizable(github_dir: Path) -> set[str]:
    """Relative paths the manifest marks ``[customizable]``.

    That annotation means "project may modify; protected on update" -- which is
    precisely the set whose size the framework does not control.
    """
    manifest = github_dir / ".af-manifest"
    if not manifest.is_file():
        # Guessing would put project prose on the framework's ceiling or the
        # reverse; either way the verdict would name the wrong owner.
        raise Blocked(
            f".af-manifest not found in {github_dir}: cannot tell framework files "
            "from project files, so neither budget can be attributed."
        )
    paths: set[str] = set()
    for line in _read_text(manifest).splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "[" not in line:
            continue
        path, _, rest = line.partition("[")
        if "customizable" in {item.strip() for item in rest.rstrip("]").split(",")}:
            paths.add(path.strip())
    return paths


def _deployed(github_dir: Path) -> set[str] | None:
    """Relative paths AF deployed here, or None when there is no record.

    ``.af-hashes`` is written by deploy into a consumer. The AF source tree has
    none -- there, everything measured is by definition AF's own payload.
    """
    hashes = github_dir / ".af-hashes"
    if not hashes.is_file():
        return None
    return {
        line.split("=", 1)[0].strip()
        for line in _read_text(hashes).splitlines()
        if "=" in line and not line.lstrip().startswith("#")
    }


class Ownership:
    """Decides whether a measured file counts against AF or against the project.

    Two signals, because one is not enough. ``[customizable]`` catches files AF
    ships as templates and invites the project to rewrite. ``.af-hashes``
    catches files AF never shipped at all -- a project's own instruction file
    sits in the same directory as AF's and is otherwise indistinguishable.
    """

    def __init__(self, github_dir: Path) -> None:
        self.customizable = _customizable(github_dir)
        self.deployed = _deployed(github_dir)

    def is_project(self, relative: str) -> bool:
        if relative in self.customizable:
            return True
        # No deployment record means the AF source tree, where an unlisted file
        # is AF's own. In a consumer that lost the record this errs towards
        # charging AF -- a false failure, never a false pass.
        return self.deployed is not None and relative not in self.deployed


def _read_budgets(conf_path: Path) -> Budgets:
    """Read the five ceilings from ``af-env.conf``.

    The two project ceilings default to ``None`` -- unbudgeted, not zero. An
    upgraded consumer never receives them (``af-env.conf`` is customizable and
    protected on update), and a project share silently charged against zero
    would fail every one of them on arrival, which is the defect this split
    exists to remove.
    """
    values: dict[str, int] = {
        "AF_CONTEXT_BUDGET_TOKENS": DEFAULT_CONTEXT_BUDGET,
        "AF_AGENT_CONTEXT_BUDGET_TOKENS": DEFAULT_AGENT_BUDGET,
        "AF_CONDITIONAL_BUDGET_TOKENS": DEFAULT_CONDITIONAL_BUDGET,
        "AF_CATALOGUE_BUDGET_TOKENS": DEFAULT_CATALOGUE_BUDGET,
    }
    project: dict[str, int | None] = {
        "AF_PROJECT_CONTEXT_BUDGET_TOKENS": None,
        "AF_PROJECT_CONDITIONAL_BUDGET_TOKENS": None,
        "AF_PROJECT_CATALOGUE_BUDGET_TOKENS": None,
    }
    if conf_path.is_file():
        text = _read_text(conf_path)
        for key in list(values) + list(project):
            match = re.search(rf"^{key}=(.*)$", text, re.MULTILINE)
            if not match:
                continue
            value = match.group(1).strip()
            if not value:
                continue
            if not value.isdigit() or int(value) <= 0:
                raise Blocked(f"{key} in af-env.conf is not a positive integer: {value!r}")
            if key in values:
                values[key] = int(value)
            else:
                project[key] = int(value)
    return Budgets(
        af_context=values["AF_CONTEXT_BUDGET_TOKENS"],
        af_agent=values["AF_AGENT_CONTEXT_BUDGET_TOKENS"],
        af_conditional=values["AF_CONDITIONAL_BUDGET_TOKENS"],
        af_catalogue=values["AF_CATALOGUE_BUDGET_TOKENS"],
        project_context=project["AF_PROJECT_CONTEXT_BUDGET_TOKENS"],
        project_conditional=project["AF_PROJECT_CONDITIONAL_BUDGET_TOKENS"],
        project_catalogue=project["AF_PROJECT_CATALOGUE_BUDGET_TOKENS"],
    )


def _instruction_sets(
    github_dir: Path, ownership: Ownership
) -> tuple[list[tuple[str, int, bool]], list[tuple[str, int, str, bool]], list[str]]:
    """Split the instruction payload into what always loads and what may load.

    Parameters
    ----------
    github_dir : Path
        The ``.github`` directory to scan.
    ownership : Ownership
        Decides, per file, whether it counts against AF or against the project.

    Returns
    -------
    tuple[list[tuple[str, int, bool]], list[tuple[str, int, str, bool]], list[str]]
        Always-on entries ``(name, tokens, is_project)``, conditional entries
        ``(name, tokens, glob, is_project)``, and warnings about ambiguous files.
    """
    always_on: list[tuple[str, int, bool]] = []
    conditional: list[tuple[str, int, str, bool]] = []
    warnings: list[str] = []

    root_instructions = github_dir / "copilot-instructions.md"
    if not root_instructions.is_file():
        raise Blocked(f"copilot-instructions.md not found in {github_dir}")
    always_on.append((root_instructions.name, _tokens(root_instructions), ownership.is_project(root_instructions.name)))

    instructions_dir = github_dir / "instructions"
    if not instructions_dir.is_dir():
        raise Blocked(f"instructions/ directory not found in {github_dir}")

    for path in sorted(instructions_dir.glob("*.md")):
        raw, is_always_on = _apply_to(path)
        is_project = ownership.is_project(f"instructions/{path.name}")
        if is_always_on:
            if raw is None:
                warnings.append(f"{path.name} has no applyTo -- counted as always-on")
            always_on.append((path.name, _tokens(path), is_project))
        else:
            conditional.append((path.name, _tokens(path), raw or "", is_project))
    return always_on, conditional, warnings


def _catalogue(github_dir: Path, ownership: Ownership) -> tuple[list[CatalogueEntry], list[str]]:
    """Measure the discovery-level announcements sent with every request.

    Parameters
    ----------
    github_dir : Path
        The ``.github`` directory to scan.
    ownership : Ownership
        Decides, per file, whether it counts against AF or against the project.

    Returns
    -------
    tuple[list[CatalogueEntry], list[str]]
        One entry per announced skill, agent and instruction file, and warnings
        about entries that are announced without a description.

    Notes
    -----
    This measures what the repository ships. The catalogue a given agent
    actually receives may be larger -- VS Code adds its own built-in skills and
    the editor's agent list -- but those are not the framework's to budget, and
    a ceiling that moved with the editor's release notes would gate nothing.
    """
    entries: list[CatalogueEntry] = []
    warnings: list[str] = []

    def describe(path: Path, relative: str, kind: str, tags: int, extra: str = "") -> None:
        text = _read_text(path)
        description = _frontmatter_value(text, "description")
        name = _frontmatter_value(text, "name") or path.stem
        if not description:
            # Costs less and is worth less: an entry with no description is
            # announced to the model as a name it cannot judge the relevance of.
            warnings.append(f"{relative} has no description -- announced but not discoverable")
        chars = tags + len(name) + len(description) + len(extra)
        entries.append(CatalogueEntry(kind, name, chars // CHARS_PER_TOKEN, ownership.is_project(relative)))

    skills_dir = github_dir / "skills"
    if skills_dir.is_dir():
        for skill in sorted(skills_dir.iterdir()):
            if not skill.is_dir() or skill.name.startswith(DORMANT_PREFIX):
                continue
            path = skill / "SKILL.md"
            if path.is_file():
                describe(path, f"skills/{skill.name}/SKILL.md", "skill", SKILL_ENTRY_TAGS)

    agents_dir = github_dir / "agents"
    if agents_dir.is_dir():
        for path in sorted(agents_dir.glob("*.agent.md")):
            hint = _frontmatter_value(_read_text(path), "argument-hint")
            tags = AGENT_ENTRY_TAGS + (AGENT_HINT_TAGS if hint else 0)
            describe(path, f"agents/{path.name}", "agent", tags, hint)

    instructions_dir = github_dir / "instructions"
    if instructions_dir.is_dir():
        for path in sorted(instructions_dir.glob("*.md")):
            raw, _ = _apply_to(path)
            describe(path, f"instructions/{path.name}", "instruction", INSTRUCTION_ENTRY_TAGS, raw or "")

    return entries, warnings


def _agent_totals(
    github_dir: Path, af_always_on: int, project_always_on: int, conditional_total: int
) -> list[tuple[str, int, int, int]]:
    """Return per-agent ``(name, own, af_total, worst_case)``, worst first.

    ``af_total`` is the gated figure: the agent file plus the framework's own
    always-on set. The project's always-on set is real cost but not AF's to
    budget, so it appears only in ``worst_case``.

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
            _tokens(path) + af_always_on,
            _tokens(path) + af_always_on + project_always_on + conditional_total,
        )
        for path in sorted(agents_dir.glob("*.agent.md"))
    ]
    if not totals:
        raise Blocked(f"no agent files found in {agents_dir}")
    return sorted(totals, key=lambda row: row[2], reverse=True)


def _owner_label(is_project: bool) -> str:
    return "project" if is_project else "AF"


def _print_split(af_total: int, af_budget: int, project_total: int, project_budget: int | None) -> None:
    print(f"  {'-' * 6}")
    print(f"  {af_total:6,} tok  AF-owned      (budget {af_budget:,})")
    ceiling = f"budget {project_budget:,}" if project_budget is not None else "UNBUDGETED"
    print(f"  {project_total:6,} tok  project-owned ({ceiling})")
    print(f"  {af_total + project_total:6,} tok  TOTAL")


def _print_breakdown(
    entries: list[tuple[str, int, bool]],
    af_total: int,
    af_budget: int,
    project_total: int,
    project_budget: int | None,
) -> None:
    print(f"{TAG} always-on set -- sent with every chat request:")
    for name, tokens, is_project in sorted(entries, key=lambda row: row[1], reverse=True):
        print(f"  {tokens:6,} tok  {_owner_label(is_project):<8} {name}")
    _print_split(af_total, af_budget, project_total, project_budget)


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


def _print_conditional(
    entries: list[tuple[str, int, str, bool]],
    af_total: int,
    af_budget: int,
    project_total: int,
    project_budget: int | None,
) -> None:
    print(f"{TAG} conditional set -- loaded when a matching file is in context:")
    for name, tokens, glob, is_project in sorted(entries, key=lambda row: row[1], reverse=True):
        print(f"  {tokens:6,} tok  {_owner_label(is_project):<8} {name:<40} {glob}")
    _print_split(af_total, af_budget, project_total, project_budget)


def _print_catalogue(
    entries: list[CatalogueEntry],
    af_total: int,
    af_budget: int,
    project_total: int,
    project_budget: int | None,
) -> None:
    print(f"{TAG} catalogue set -- name and description, announced on every chat request:")
    for kind in ("skill", "agent", "instruction"):
        rows = [entry for entry in entries if entry.kind == kind]
        if not rows:
            continue
        af_kind = sum(row.tokens for row in rows if not row.is_project)
        project_kind = sum(row.tokens for row in rows if row.is_project)
        print(
            f"  {af_kind + project_kind:6,} tok  {kind + 's':<14} {len(rows):>3} entries  "
            f"(AF {af_kind:,}, project {project_kind:,})"
        )
    widest = sorted(entries, key=lambda row: row.tokens, reverse=True)[:5]
    for entry in widest:
        print(f"         {entry.tokens:4,} tok  {_owner_label(entry.is_project):<8} {entry.kind:<12} {entry.name}")
    _print_split(af_total, af_budget, project_total, project_budget)


def _print_agents(totals: list[tuple[str, int, int, int]], agent_budget: int, af_always_on: int) -> None:
    print(f"{TAG} per-agent context (own + AF always-on {af_always_on:,}, gated):")
    for name, own, af_total, worst in totals:
        print(f"  {af_total:6,} tok  {name:<24} (own {own:,}, worst case {worst:,})")
    over = [row for row in totals if row[3] > agent_budget]
    if over:
        # Marking each row instead would repeat one shared cause fifteen times.
        print(
            f"  worst case -- everything conditional and the project's own always-on set "
            f"loaded at once -- exceeds {agent_budget:,} for {len(over)} of {len(totals)} agents."
        )


def _seed_value(measured: int) -> int:
    """The ceiling to record for a project share measured at ``measured``."""
    return max(50, ((int(measured * (1 + PROJECT_SEED_HEADROOM)) + 49) // 50) * 50)


def _seed_project_budget(
    conf_path: Path,
    budgets: Budgets,
    always_on: int,
    conditional: int,
    catalogue: int,
    force: bool,
) -> int:
    """Record this project's own ceilings in ``af-env.conf``.

    Seeded from what the project has today plus stated headroom, so the gate
    detects drift from the project's own baseline rather than from a number the
    framework invented for someone else's repository.
    """
    if not conf_path.is_file():
        raise Blocked(f"af-env.conf not found at {conf_path}")
    measured = {
        "AF_PROJECT_CONTEXT_BUDGET_TOKENS": (budgets.project_context, always_on),
        "AF_PROJECT_CONDITIONAL_BUDGET_TOKENS": (budgets.project_conditional, conditional),
        "AF_PROJECT_CATALOGUE_BUDGET_TOKENS": (budgets.project_catalogue, catalogue),
    }
    already = [key for key, (current, _) in measured.items() if current is not None]
    if already and not force:
        # Seed only what has never been set. An upgrade that adds a ceiling must
        # not force a project to choose between re-baselining the two it already
        # tuned and leaving the new one ungated forever.
        pending = {key: value for key, (current, value) in measured.items() if current is None}
        if not pending:
            print(f"{TAG} refusing to overwrite: {', '.join(already)} already set in {conf_path}.")
            print("A seeded budget is a baseline someone chose. Re-run with --force to replace it.")
            return 1
        print(f"{TAG} keeping the ceilings already set: {', '.join(already)}.")
        seeded = {key: _seed_value(value) for key, value in pending.items()}
    else:
        seeded = {key: _seed_value(value) for key, (_, value) in measured.items()}
    text = _read_text(conf_path)
    for key, value in seeded.items():
        pattern = rf"^{key}=.*$"
        if re.search(pattern, text, re.MULTILINE):
            text = re.sub(pattern, f"{key}={value}", text, count=1, flags=re.MULTILINE)
        else:
            if not text.endswith("\n"):
                text += "\n"
            text += f"{key}={value}\n"
    seeded_on = datetime.now(timezone.utc).date().isoformat()
    header = (
        f"\n# Project context budgets seeded {seeded_on} from this repository:\n"
        f"# always-on {always_on:,} tok, conditional {conditional:,} tok, "
        f"catalogue {catalogue:,} tok, "
        f"+{int(PROJECT_SEED_HEADROOM * 100)}% headroom, rounded up to the nearest 50.\n"
        "# These cover the project's own instruction files. The AF_* ceilings above\n"
        "# cover the framework's, and are calibrated in the framework repository.\n"
    )
    if "# Project context budgets seeded" not in text:
        text = text.rstrip("\n") + "\n" + header
    conf_path.write_text(text, encoding="utf-8")
    for key, value in seeded.items():
        print(f"{TAG} {key}={value}")
    print(f"{TAG} seeded into {conf_path}. Commit it -- it is this project's baseline.")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Fail when the always-on instruction payload exceeds its budget.",
        epilog="Framework budgets: AF_CONTEXT_BUDGET_TOKENS, AF_AGENT_CONTEXT_BUDGET_TOKENS, "
        "AF_CONDITIONAL_BUDGET_TOKENS, AF_CATALOGUE_BUDGET_TOKENS. Project budgets: "
        "AF_PROJECT_CONTEXT_BUDGET_TOKENS, AF_PROJECT_CONDITIONAL_BUDGET_TOKENS, "
        "AF_PROJECT_CATALOGUE_BUDGET_TOKENS "
        "(seed them with --seed-project-budget). All in .github/af-env.conf.",
    )
    parser.add_argument(
        "--github-dir",
        type=Path,
        default=None,
        help="Path to the .github directory (defaults to the one containing this script)",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print the per-file breakdown even when the check passes",
    )
    parser.add_argument(
        "--verify-tokenizer",
        action="store_true",
        help="Re-measure characters-per-token with tiktoken and report the drift "
        "against the hardcoded divisor, instead of checking budgets "
        "(development aid; requires tiktoken)",
    )
    parser.add_argument(
        "--seed-project-budget",
        action="store_true",
        help="Record this project's own always-on and conditional ceilings in "
        "af-env.conf, measured from what it has today plus headroom",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="With --seed-project-budget, replace ceilings that are already set",
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
        conf_path = github_dir / "af-env.conf"
        budgets = _read_budgets(conf_path)
        ownership = Ownership(github_dir)
        entries, conditional_entries, warnings = _instruction_sets(github_dir, ownership)
        catalogue_entries, catalogue_warnings = _catalogue(github_dir, ownership)
        warnings.extend(catalogue_warnings)

        af_always_on = sum(tok for _, tok, is_project in entries if not is_project)
        project_always_on = sum(tok for _, tok, is_project in entries if is_project)
        af_conditional = sum(tok for _, tok, _, is_project in conditional_entries if not is_project)
        project_conditional = sum(tok for _, tok, _, is_project in conditional_entries if is_project)
        conditional_total = af_conditional + project_conditional
        af_catalogue = sum(entry.tokens for entry in catalogue_entries if not entry.is_project)
        project_catalogue = sum(entry.tokens for entry in catalogue_entries if entry.is_project)

        if args.seed_project_budget:
            return _seed_project_budget(
                conf_path, budgets, project_always_on, project_conditional, project_catalogue, args.force
            )

        agent_totals = _agent_totals(github_dir, af_always_on, project_always_on, conditional_total)
    except Blocked as exc:
        print(f"{TAG} BLOCKED -- {exc}", file=sys.stderr)
        print(f"{TAG} Result unknown, not passing. Fix the input and re-run.", file=sys.stderr)
        return 2

    for warning in warnings:
        print(f"{TAG} WARNING: {warning}")

    worst_agent, worst_agent_tokens, worst_af_total, _ = agent_totals[0]
    over_context = af_always_on > budgets.af_context
    over_agent = worst_af_total > budgets.af_agent
    over_conditional = af_conditional > budgets.af_conditional
    over_catalogue = af_catalogue > budgets.af_catalogue
    over_project_context = budgets.project_context is not None and project_always_on > budgets.project_context
    over_project_conditional = (
        budgets.project_conditional is not None and project_conditional > budgets.project_conditional
    )
    over_project_catalogue = budgets.project_catalogue is not None and project_catalogue > budgets.project_catalogue

    unbudgeted = (
        budgets.project_context is None or budgets.project_conditional is None or budgets.project_catalogue is None
    )
    if unbudgeted and (project_always_on or project_conditional or project_catalogue):
        # Not a failure. A project that has never stated a baseline has not
        # drifted from one, and inventing a ceiling on its behalf would fail it
        # for existing -- the arrival failure this split exists to remove.
        print(
            f"{TAG} UNBUDGETED -- project files measure {project_always_on:,} tok always-on, "
            f"{project_conditional:,} tok conditional, {project_catalogue:,} tok catalogue, "
            "against no stated ceiling."
        )
        print(f"  Record this project's baseline: python {Path(__file__).name} --seed-project-budget")

    failures = (
        over_context
        or over_agent
        or over_conditional
        or over_catalogue
        or over_project_context
        or over_project_conditional
        or over_project_catalogue
    )
    if not failures:
        if args.verbose:
            _print_breakdown(entries, af_always_on, budgets.af_context, project_always_on, budgets.project_context)
            print()
            if conditional_entries:
                _print_conditional(
                    conditional_entries,
                    af_conditional,
                    budgets.af_conditional,
                    project_conditional,
                    budgets.project_conditional,
                )
                print()
            if catalogue_entries:
                _print_catalogue(
                    catalogue_entries,
                    af_catalogue,
                    budgets.af_catalogue,
                    project_catalogue,
                    budgets.project_catalogue,
                )
                print()
            _print_agents(agent_totals, budgets.af_agent, af_always_on)
            print()
        print(
            f"{TAG} PASS -- AF always-on {af_always_on:,}/{budgets.af_context:,} tok; "
            f"AF conditional {af_conditional:,}/{budgets.af_conditional:,} tok; "
            f"AF catalogue {af_catalogue:,}/{budgets.af_catalogue:,} tok; "
            f"largest agent {worst_agent} {worst_af_total:,}/{budgets.af_agent:,} tok"
        )
        return 0

    if over_context or over_project_context:
        _print_breakdown(entries, af_always_on, budgets.af_context, project_always_on, budgets.project_context)
        print()

    if over_context:
        print(
            f"{TAG} FAIL -- AF always-on set is {af_always_on - budgets.af_context:,} tok "
            f"over budget ({af_always_on:,} > {budgets.af_context:,})."
        )
        print()
        print("To fix, in order of preference:")
        print("  - Narrow the applyTo glob so the file loads only when relevant.")
        print("  - Move depth into a skill (loaded on demand) or the owning agent file.")
        print("  - Delete duplication -- check whether the rule already exists elsewhere.")
        print("  - Raise AF_CONTEXT_BUDGET_TOKENS only as a deliberate, justified decision.")

    if over_project_context:
        if over_context:
            print()
        assert budgets.project_context is not None
        print(
            f"{TAG} FAIL -- project always-on set is "
            f"{project_always_on - budgets.project_context:,} tok over its own budget "
            f"({project_always_on:,} > {budgets.project_context:,})."
        )
        print()
        print("This budget is the project's own baseline, not a framework limit.")
        print("  - Trim the project's copilot-instructions.md, or")
        print("  - Raise AF_PROJECT_CONTEXT_BUDGET_TOKENS deliberately and say why.")

    if over_conditional or over_project_conditional:
        if over_context or over_project_context:
            print()
        _print_conditional(
            conditional_entries,
            af_conditional,
            budgets.af_conditional,
            project_conditional,
            budgets.project_conditional,
        )
        print()

    if over_conditional:
        print(
            f"{TAG} FAIL -- AF conditional set is "
            f"{af_conditional - budgets.af_conditional:,} tok over budget "
            f"({af_conditional:,} > {budgets.af_conditional:,})."
        )
        print()
        print("A narrow applyTo makes a file load less often, not cheaply: for the")
        print("agents whose job is to touch matching files it is effectively always-on.")
        print("  - Move reference depth into a skill; keep the contract in the instruction.")
        print("  - Check the glob is not broader than the rule it carries.")

    if over_project_conditional:
        if over_conditional:
            print()
        assert budgets.project_conditional is not None
        print(
            f"{TAG} FAIL -- project conditional set is "
            f"{project_conditional - budgets.project_conditional:,} tok over its own budget "
            f"({project_conditional:,} > {budgets.project_conditional:,})."
        )

    if over_catalogue or over_project_catalogue:
        if over_context or over_project_context or over_conditional or over_project_conditional:
            print()
        _print_catalogue(
            catalogue_entries,
            af_catalogue,
            budgets.af_catalogue,
            project_catalogue,
            budgets.project_catalogue,
        )
        print()

    if over_catalogue:
        print(
            f"{TAG} FAIL -- AF catalogue set is "
            f"{af_catalogue - budgets.af_catalogue:,} tok over budget "
            f"({af_catalogue:,} > {budgets.af_catalogue:,})."
        )
        print()
        print("Every skill and agent announces itself on every request, whether or not")
        print("it is ever loaded. Adding one is not free just because its body is not sent.")
        print("  - Shorten descriptions: they are for deciding relevance, not for teaching.")
        print("  - Merge skills that a reader cannot tell apart from their descriptions.")
        print("  - Move a rarely-needed skill to skills/_available/ -- and register it, so")
        print("    deactivating it does not make it unfindable (issue #222).")

    if over_project_catalogue:
        if over_catalogue:
            print()
        assert budgets.project_catalogue is not None
        print(
            f"{TAG} FAIL -- project catalogue set is "
            f"{project_catalogue - budgets.project_catalogue:,} tok over its own budget "
            f"({project_catalogue:,} > {budgets.project_catalogue:,})."
        )

    if over_agent:
        if over_context or over_conditional or over_project_context or over_project_conditional:
            print()
        print(f"{TAG} agent context totals (agent file + AF always-on set):")
        for name, own, af_total, worst in agent_totals:
            marker = "  <-- over budget" if af_total > budgets.af_agent else ""
            print(f"  {af_total:6,} tok  {name} (own {own:,}, worst case {worst:,}){marker}")
        print()
        print(
            f"{TAG} FAIL -- {worst_agent} is {worst_af_total - budgets.af_agent:,} tok over "
            f"budget ({worst_af_total:,} > {budgets.af_agent:,}); "
            f"own prompt {worst_agent_tokens:,} tok."
        )

    return 1


if __name__ == "__main__":
    sys.exit(main())
