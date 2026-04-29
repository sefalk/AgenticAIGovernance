#!/usr/bin/env python3
"""Validate AAIG skill structure, frontmatter, and INDEX.md consistency.

Checks:
1. Every skill directory has a SKILL.md file
2. SKILL.md has valid YAML frontmatter:
   - name: required, ≤64 chars, lowercase-hyphenated, no XML tags
   - description: required, non-empty, ≤1024 chars, no XML tags
   - argument-hint: optional, ≤128 chars if present
3. Directory name matches frontmatter name
4. INDEX.md lists all active and available skills
5. No orphan directories (skill dir exists but not in INDEX.md)
6. No phantom entries (INDEX.md lists skill that doesn't exist)

Usage:
    python validate-skills.py                    # validate .github/skills/
    python validate-skills.py --root <path>      # validate custom root

Exit codes:
    0 — all checks passed
    1 — validation errors found
    2 — fatal error (missing directories, bad arguments)

Adapted from ai-dev-kit validate_skills.py for AAIG conventions.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SKILLS_DIR_NAME = "skills"
AVAILABLE_DIR_NAME = "_available"
INDEX_FILENAME = "INDEX.md"

NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
XML_TAG_RE = re.compile(r"<[^>]+>")
FRONTMATTER_RE = re.compile(r"^---\n(.+?)\n---", re.DOTALL)

# Directories that are not skills
SKIP_DIRS = {AVAILABLE_DIR_NAME, "__pycache__", ".git", "node_modules"}

MAX_NAME_LEN = 64
MAX_DESC_LEN = 1024
MAX_HINT_LEN = 128

# Activation metadata
VALID_PRIORITIES = {"required", "recommended", "optional"}
VALID_SIGNAL_KEYS = {"python_packages", "js_packages", "file_patterns", "af_config", "imports"}


# ---------------------------------------------------------------------------
# YAML parsing (minimal — avoid external dependency)
# ---------------------------------------------------------------------------

def parse_frontmatter(content: str) -> dict | None:
    """Extract YAML frontmatter from markdown content.

    Uses a minimal parser that handles the three fields we care about
    (name, description, argument-hint) without requiring PyYAML.
    Falls back to PyYAML if available.
    """
    match = FRONTMATTER_RE.match(content)
    if not match:
        return None
    raw = match.group(1)

    # Try PyYAML first
    try:
        import yaml  # noqa: PLC0415
        return yaml.safe_load(raw)
    except ImportError:
        pass

    # Minimal fallback: key: value pairs (single-line values only)
    result: dict[str, str] = {}
    for line in raw.splitlines():
        if ":" in line:
            key, _, value = line.partition(":")
            key = key.strip()
            value = value.strip().strip("'\"")
            if key and value:
                result[key] = value
    return result if result else None


# ---------------------------------------------------------------------------
# Validators
# ---------------------------------------------------------------------------

def validate_name(name: str, dir_name: str) -> list[str]:
    """Validate the name field."""
    errors: list[str] = []
    if len(name) > MAX_NAME_LEN:
        errors.append(f"name '{name}' exceeds {MAX_NAME_LEN} chars ({len(name)})")
    if not NAME_RE.match(name):
        errors.append(
            f"name '{name}' must be lowercase letters, numbers, and hyphens"
        )
    if XML_TAG_RE.search(name):
        errors.append(f"name '{name}' must not contain XML tags")
    if name != dir_name:
        errors.append(
            f"name '{name}' does not match directory name '{dir_name}'"
        )
    return errors


def validate_description(description: str) -> list[str]:
    """Validate the description field."""
    errors: list[str] = []
    if not description or not description.strip():
        errors.append("description must not be empty")
    if len(description) > MAX_DESC_LEN:
        errors.append(
            f"description exceeds {MAX_DESC_LEN} chars ({len(description)})"
        )
    if XML_TAG_RE.search(description):
        errors.append("description must not contain XML tags")
    return errors


def validate_argument_hint(hint: str) -> list[str]:
    """Validate the optional argument-hint field."""
    errors: list[str] = []
    if len(hint) > MAX_HINT_LEN:
        errors.append(
            f"argument-hint exceeds {MAX_HINT_LEN} chars ({len(hint)})"
        )
    return errors


def validate_activation(
    activation: dict,
    known_agents: set[str] | None = None,
) -> tuple[list[str], list[str]]:
    """Validate the optional activation metadata block.

    Returns (errors, warnings).
    """
    errors: list[str] = []
    warnings: list[str] = []

    # priority
    priority = activation.get("priority")
    if priority is None:
        errors.append("activation: missing 'priority' field")
    elif str(priority) not in VALID_PRIORITIES:
        errors.append(
            f"activation.priority '{priority}' must be one of: "
            + ", ".join(sorted(VALID_PRIORITIES))
        )

    # agents
    agents = activation.get("agents")
    if agents is None:
        errors.append("activation: missing 'agents' field")
    elif isinstance(agents, list):
        for agent in agents:
            agent_str = str(agent)
            if known_agents is not None and agent_str not in known_agents:
                errors.append(
                    f"activation.agents: '{agent_str}' does not match "
                    "any .agent.md file"
                )
    else:
        errors.append("activation.agents must be a list")

    # signals (optional)
    signals = activation.get("signals")
    if signals is not None:
        if isinstance(signals, dict):
            unknown_keys = set(signals.keys()) - VALID_SIGNAL_KEYS
            for key in sorted(unknown_keys):
                errors.append(
                    f"activation.signals: unknown key '{key}' "
                    f"(valid: {', '.join(sorted(VALID_SIGNAL_KEYS))})"
                )
        else:
            errors.append("activation.signals must be a mapping")

    # Unusual combo warning: required + non-empty signals
    if (
        priority is not None
        and str(priority) == "required"
        and signals
        and isinstance(signals, dict)
        and any(signals.values())
    ):
        warnings.append(
            "activation: priority=required with signals is unusual "
            "(required skills are typically framework invariants with no signals)"
        )

    return errors, warnings


def validate_skill_dir(
    skill_dir: Path,
    *,
    deep: bool = True,
    known_agents: set[str] | None = None,
) -> tuple[list[str], list[str]]:
    """Validate a single skill directory.

    Parameters
    ----------
    skill_dir : Path
        Path to the skill directory.
    deep : bool
        If True, validate frontmatter contents. If False, only check
        that SKILL.md exists (used for _available/ light scan).
    known_agents : set[str] | None
        Set of known agent names (from .agent.md filenames). Used to
        validate activation.agents references.

    Returns
    -------
    tuple[list[str], list[str]]
        (errors, warnings)
    """
    errors: list[str] = []
    warnings: list[str] = []
    prefix = skill_dir.name

    skill_md = skill_dir / "SKILL.md"
    if not skill_md.exists():
        errors.append(f"{prefix}: missing SKILL.md")
        return errors, warnings

    content = skill_md.read_text(encoding="utf-8")

    # Always check frontmatter can be parsed
    fm = parse_frontmatter(content)
    if fm is None:
        errors.append(f"{prefix}: invalid or missing YAML frontmatter")
        return errors, warnings

    if not deep:
        # Light scan: just verify name field exists and matches dir
        if "name" in fm and str(fm["name"]) != skill_dir.name:
            errors.append(
                f"{prefix}: name '{fm['name']}' does not match directory"
            )
        return errors, warnings

    # --- Deep validation ---

    # name
    if "name" not in fm:
        errors.append(f"{prefix}: missing 'name' in frontmatter")
    else:
        for err in validate_name(str(fm["name"]), skill_dir.name):
            errors.append(f"{prefix}: {err}")

    # description
    if "description" not in fm:
        errors.append(f"{prefix}: missing 'description' in frontmatter")
    else:
        for err in validate_description(str(fm["description"])):
            errors.append(f"{prefix}: {err}")

    # argument-hint (optional)
    if "argument-hint" in fm:
        for err in validate_argument_hint(str(fm["argument-hint"])):
            errors.append(f"{prefix}: {err}")

    # activation (optional)
    if "activation" in fm:
        activation = fm["activation"]
        if isinstance(activation, dict):
            act_errors, act_warnings = validate_activation(
                activation, known_agents=known_agents
            )
            for err in act_errors:
                errors.append(f"{prefix}: {err}")
            for warn in act_warnings:
                warnings.append(f"{prefix}: {warn}")
        else:
            errors.append(f"{prefix}: activation must be a mapping")

    # Verify SKILL.md has a top-level heading
    if not re.search(r"^# .+", content, re.MULTILINE):
        errors.append(f"{prefix}: SKILL.md missing top-level '# ' heading")

    return errors, warnings


# ---------------------------------------------------------------------------
# INDEX.md cross-reference
# ---------------------------------------------------------------------------

def parse_index_skills(index_path: Path) -> tuple[set[str], set[str]]:
    """Parse INDEX.md and return (active_skills, available_skills).

    Active skills are extracted from the markdown table rows.
    Available skills are extracted from the comma-separated list
    in the "Available for Activation" section.
    """
    active: set[str] = set()
    available: set[str] = set()

    if not index_path.exists():
        return active, available

    content = index_path.read_text(encoding="utf-8")

    # Active: rows like | 1 | `skill-name` | description | agents |
    for m in re.finditer(
        r"\|\s*\d+\s*\|\s*`([^`]+)`\s*\|", content
    ):
        active.add(m.group(1))

    # Available: comma-separated list after "Available for Activation"
    # The list is a block of comma-separated skill names (lowercase-hyphenated).
    # We identify it by finding lines where most tokens are valid skill names.
    avail_section = re.search(
        r"Available for Activation.*?\n([\s\S]+?)$", content
    )
    if avail_section:
        # Find the comma-separated block: lines with ≥2 comma-separated
        # tokens that all look like skill names
        block_lines: list[str] = []
        in_block = False
        for line in avail_section.group(1).splitlines():
            stripped = line.strip()
            if not stripped:
                if in_block:
                    break  # blank line ends the skills block
                continue
            # A skill-list line has comma-separated tokens that match NAME_RE
            tokens = [t.strip() for t in stripped.rstrip(",").split(",") if t.strip()]
            if tokens and all(NAME_RE.match(t) for t in tokens):
                in_block = True
                block_lines.append(stripped)
            elif in_block:
                break  # non-matching line ends the block

        for line in block_lines:
            for token in line.rstrip(",").split(","):
                token = token.strip()
                if NAME_RE.match(token):
                    available.add(token)

    return active, available


def validate_index_consistency(
    skills_root: Path,
    active_dirs: set[str],
    available_dirs: set[str],
) -> list[str]:
    """Cross-reference INDEX.md against actual directories."""
    errors: list[str] = []

    index_path = skills_root / INDEX_FILENAME
    if not index_path.exists():
        errors.append(f"INDEX.md not found at {index_path}")
        return errors

    idx_active, idx_available = parse_index_skills(index_path)

    # Active: orphan directories (exist on disk, not in INDEX)
    orphan_active = active_dirs - idx_active
    for name in sorted(orphan_active):
        errors.append(f"INDEX orphan: active skill '{name}' not listed")

    # Active: phantom entries (in INDEX but no directory)
    phantom_active = idx_active - active_dirs
    for name in sorted(phantom_active):
        errors.append(f"INDEX phantom: '{name}' listed as active but no directory")

    # Available: orphan directories (skip skills that are already active —
    # when a skill is activated by copying to the active dir, it may remain
    # in _available/ without being listed there in INDEX.md)
    orphan_avail = available_dirs - idx_available - idx_active
    for name in sorted(orphan_avail):
        errors.append(f"INDEX orphan: available skill '{name}' not listed")

    # Available: phantom entries
    phantom_avail = idx_available - available_dirs
    for name in sorted(phantom_avail):
        errors.append(
            f"INDEX phantom: '{name}' listed as available but no directory"
        )

    return errors


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def discover_skill_dirs(path: Path) -> set[str]:
    """Return set of skill directory names under a path."""
    return {
        d.name
        for d in path.iterdir()
        if d.is_dir() and d.name not in SKIP_DIRS and not d.name.startswith(".")
    }


def discover_agent_names(github_dir: Path) -> set[str]:
    """Return set of agent names from .agent.md files in agents/."""
    agents_dir = github_dir / "agents"
    if not agents_dir.is_dir():
        return set()
    return {
        f.stem.removesuffix(".agent")
        for f in agents_dir.iterdir()
        if f.is_file() and f.name.endswith(".agent.md")
    }


def main(argv: list[str] | None = None) -> int:
    """Run validation and return exit code."""
    parser = argparse.ArgumentParser(
        description="Validate AAIG skill structure and INDEX.md consistency.",
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=None,
        help="Root .github/ directory (auto-detected if not specified).",
    )
    parser.add_argument(
        "--deep-available",
        action="store_true",
        help="Run deep validation on _available/ skills too (default: light scan).",
    )
    parser.add_argument(
        "--ci",
        action="store_true",
        help="Output GitHub Actions ::error:: annotations.",
    )
    args = parser.parse_args(argv)

    # --- Resolve paths ---
    if args.root:
        github_dir = args.root
    else:
        # Auto-detect: walk up from script location
        script_dir = Path(__file__).resolve().parent
        if script_dir.name == "scripts" and script_dir.parent.name == ".github":
            github_dir = script_dir.parent
        else:
            github_dir = Path(".github")

    skills_root = github_dir / SKILLS_DIR_NAME
    available_root = skills_root / AVAILABLE_DIR_NAME

    if not skills_root.is_dir():
        print(f"FATAL: skills directory not found: {skills_root}", file=sys.stderr)
        return 2

    # --- Discover directories ---
    active_dirs = discover_skill_dirs(skills_root)
    available_dirs = (
        discover_skill_dirs(available_root) if available_root.is_dir() else set()
    )

    # --- Discover agent names (for activation.agents validation) ---
    known_agents = discover_agent_names(github_dir)

    errors: list[str] = []
    warnings: list[str] = []

    # --- Validate active skills (deep) ---
    for name in sorted(active_dirs):
        skill_dir = skills_root / name
        errs, warns = validate_skill_dir(
            skill_dir, deep=True, known_agents=known_agents
        )
        errors.extend(errs)
        warnings.extend(warns)

    # --- Validate _available/ skills ---
    deep_avail = args.deep_available
    for name in sorted(available_dirs):
        skill_dir = available_root / name
        errs, warns = validate_skill_dir(
            skill_dir, deep=deep_avail, known_agents=known_agents
        )
        if deep_avail:
            errors.extend(errs)
            warnings.extend(warns)
        else:
            # Light scan: missing SKILL.md is an error, everything else is a warning
            for e in errs:
                if "missing SKILL.md" in e:
                    errors.extend([e])
                else:
                    warnings.append(e)
            warnings.extend(warns)

    # --- INDEX.md cross-reference ---
    errors.extend(
        validate_index_consistency(skills_root, active_dirs, available_dirs)
    )

    # --- Report ---
    total_skills = len(active_dirs) + len(available_dirs)
    prefix = "::error::" if args.ci else "  ERROR: "
    warn_prefix = "::warning::" if args.ci else "  WARN:  "

    print(f"Skills validated: {len(active_dirs)} active, {len(available_dirs)} available")
    print()

    if warnings:
        print(f"Warnings ({len(warnings)}):")
        for w in warnings:
            print(f"{warn_prefix}{w}")
        print()

    if errors:
        print(f"Errors ({len(errors)}):")
        for e in errors:
            print(f"{prefix}{e}")
        print()
        print(f"FAIL — {len(errors)} error(s), {len(warnings)} warning(s)")
        return 1

    if warnings:
        print(f"PASS with {len(warnings)} warning(s) — {total_skills} skills OK")
    else:
        print(f"PASS — all {total_skills} skills validated successfully")
    return 0


if __name__ == "__main__":
    sys.exit(main())
