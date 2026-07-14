---
name: documentation
description: Documentation standards — code comments, docstrings, READMEs, ADRs, changelogs. Use when creating or reviewing documentation artifacts.
argument-hint: '[doc type: docstring|readme|adr|changelog|comment] [module or file]'
disable-model-invocation: true
---

# Documentation Skill

Standards for code documentation, architecture decision records, and
project-level documentation artifacts.

## When to Use

- Writing docstrings for new functions/classes
- Creating or updating README files
- Writing Architecture Decision Records (ADRs)
- Reviewing documentation quality in code review
- End-of-workflow documentation (documenter agent)

## Principles

- **Document *why*, not *what*** — code shows what; documentation explains why
- **Audience-aware** — every document has a reader; write for them
- **Living documents** — unmaintained docs are worse than no docs
- **Efficiency** — don't document what the code already says clearly

## Code Comments

**When to comment:**
- Non-obvious business rules or domain logic
- Workarounds for external bugs (link to the issue)
- Performance-critical non-obvious approaches
- Regular expressions (always explain what they match)
- TODO/FIXME with ticket reference: `# TODO(PROJ-123): Replace with streaming`

**When NOT to comment:**
- Code is self-explanatory
- Comment restates the variable/function name
- Comment is outdated (delete or update it)

```python
# BAD: Increment counter by 1
counter += 1

# GOOD: Compensate for off-by-one in API pagination (returns N-1 items)
counter += 1
```

## Docstrings (NumPy Style)

All public functions must have docstrings using **NumPy-style** format:

```python
def compute_movements(df: DataFrame, threshold: float = 0.5) -> DataFrame:
    """Compute movement windows from parameter transitions.

    Parameters
    ----------
    df : DataFrame
        Input with aligned parameters.
    threshold : float, optional
        Minimum change to count as movement, by default 0.5.

    Returns
    -------
    DataFrame
        DataFrame with movement columns added.

    Raises
    ------
    ValidationError
        If required columns are missing from df.

    Examples
    --------
    >>> result = compute_movements(sample_df)
    >>> assert "movement_id" in result.columns
    """
```

**Rules:**
- All public functions: Parameters, Returns, Raises
- Examples section for non-trivial functions
- Notes section for AI provenance markers (`copilot:modified`)

## README Template

```markdown
# Project Name

One-line description.

## Quick Start
Steps to get running locally (< 5 commands).

## Prerequisites
Required software, versions, accounts.

## Installation
Detailed setup instructions.

## Usage
Common use cases with examples.

## Architecture
High-level overview, link to ARCHITECTURE.md and ADRs.

## Contributing
Branch conventions, PR process, agent workflow.

## License
License information.
```

## Architecture Decision Records (ADRs)

ADRs capture the *context*, *decision*, and *consequences* of architectural
choices. Use the Michael Nygard format:

```markdown
# ADR-NNN: [Title]

**Status:** Proposed | Accepted | Deprecated | Superseded by ADR-XXX
**Date:** YYYY-MM-DD

## Context
What is the issue? What forces are at play?

## Decision
What have we decided to do?

## Consequences
What are the positive and negative results?

## Alternatives Considered
What options were evaluated and why were they rejected?
```

**Rules:**
- ADRs are immutable once accepted — supersede with a new ADR
- Number sequentially: `ADR-001`, `ADR-002`
- Store in `docs/adr/` or `docs/adrs/`

## Handoff Logs

The documenter agent produces structured YAML handoff logs at end-of-workflow:

```yaml
workflow_id: "feat-add-bucketing-v2"
timestamp: "2026-02-13T14:30:00Z"
status: COMPLETED
agents_involved:
  - planner
  - test-writer
  - implementer
  - code-critic
files_changed:
  - path: "src/domain/bucketing.py"
    action: modified
    summary: "Added time-window bucketing logic"
tests_added: 12
coverage_delta: "+3.2%"
```

## AI Provenance Markers

All AI-generated or AI-modified code must carry parseable provenance markers.
See `provenance.instructions.md` for the full specification.

```python
```

## Quality Gates

| Gate | Threshold |
|---|---|
| Public API documented | 100% of public functions have docstrings |
| README current | Reflects current project state |
| ADR for each major decision | All structural/dependency decisions |
| No outdated docs | Reviewed when related code changes |
| Provenance markers | All AI-created files marked |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Book-writing** | 50-page docs nobody reads | Concise, link to code |
| **Commenting the obvious** | `i += 1 # increment i` | Comment only on *why* |
| **Orphaned docs** | Wiki nobody updates | Docs in repo, reviewed in PRs |
| **No ADRs** | "Why did we choose X?" unanswerable | Write at decision time |
| **Missing examples** | API params listed but no usage | At least one example per public API |
