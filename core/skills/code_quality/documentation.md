---
category: code_quality
applies_to: [all]
complexity: foundational
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [code_review, api_design, stakeholder_communication]
---
# Documentation

## Purpose

Documentation makes code, systems, and decisions understandable to current and future team members (including AI agents). Good documentation reduces onboarding time, prevents repeated mistakes, and serves as a verifiable reference. Invoke this skill when defining documentation standards, Level-3 documentation workflows, or Level-4 project conventions.

## Principles

- **Transparency/Traceability (AAIG L1):** Each workflow phase must produce documented deliverables. Documentation is not optional overhead -- it's a core output.
- **Audience-aware:** Every document has a reader. Write for them, not for yourself.
- **Living documents:** Documentation that isn't maintained becomes misleading -- worse than no documentation.
- **Efficiency (AAIG L1):** Document what matters. Don't document what the code already says clearly.

## Techniques & Patterns

### Documentation Types

| Type | Audience | Purpose | Format |
|------|----------|---------|--------|
| **Code comments** | Developers reading the code | Explain *why*, not *what* | Inline in source |
| **Docstrings / JSDoc** | Developers using the API | Function signatures, params, returns, examples | In-code annotations |
| **README** | New team members, users | Project overview, setup, usage | Markdown in repo root |
| **ADR (Architecture Decision Record)** | Future architects, reviewers | Capture *why* a decision was made and what alternatives were rejected | Markdown in `docs/adr/` |
| **API documentation** | API consumers (internal/external) | Endpoints, schemas, auth, examples | OpenAPI/Swagger, GraphQL schema |
| **Runbook / Ops guide** | On-call engineers | How to deploy, monitor, troubleshoot | Markdown in `docs/ops/` |
| **Changelog** | Users, downstream consumers | What changed between versions | `CHANGELOG.md` (Keep a Changelog format) |

### Code Comments Best Practices

**Comment on *why*, not *what*:**
```python
# BAD: Increment counter by 1
counter += 1

# GOOD: Compensate for off-by-one in the API's pagination (returns N-1 items)
counter += 1
```

**When to comment:**
- Non-obvious business rules or domain logic.
- Workarounds for external bugs (link to the bug/issue).
- Performance-critical code where the approach is non-obvious.
- Regular expressions (always explain what they match).
- TODO/FIXME with ticket reference: `# TODO(PROJ-123): Replace with streaming API`.

**When NOT to comment:**
- The code is self-explanatory.
- The comment restates the variable/function name.
- The comment is outdated (delete or update it).

### Docstrings / API Documentation

#### Python (Google style)
```python
def calculate_interest(principal: float, rate: float, years: int) -> float:
    """Calculate compound interest on a principal amount.

    Args:
        principal: The initial investment amount in currency units.
        rate: Annual interest rate as a decimal (e.g., 0.05 for 5%).
        years: Number of years to compound.

    Returns:
        The total amount after compounding.

    Raises:
        ValueError: If rate is negative or years is non-positive.

    Example:
        >>> calculate_interest(1000, 0.05, 10)
        1628.89
    """
```

#### TypeScript (TSDoc / JSDoc)
```typescript
/**
 * Calculate compound interest on a principal amount.
 *
 * @param principal - Initial investment amount
 * @param rate - Annual interest rate as decimal (e.g., 0.05 for 5%)
 * @param years - Number of years to compound
 * @returns Total amount after compounding
 * @throws {RangeError} If rate is negative or years is non-positive
 *
 * @example
 * ```
 * calculateInterest(1000, 0.05, 10) // => 1628.89
 * ```
 */
```

#### Java (Javadoc)
```java
/**
 * Calculate compound interest on a principal amount.
 *
 * @param principal the initial investment amount
 * @param rate annual interest rate as decimal (e.g., 0.05 for 5%)
 * @param years number of years to compound
 * @return the total amount after compounding
 * @throws IllegalArgumentException if rate is negative or years is non-positive
 */
```

### README Template

```markdown
# Project Name

One-line description of what this project does.

## Quick Start
Steps to get running locally (< 5 commands).

## Prerequisites
Required software, versions, accounts.

## Installation
Detailed setup instructions.

## Usage
Common use cases with examples.

## Architecture
High-level overview, diagrams, key design decisions.
Link to detailed docs (ADRs, API docs, etc.).

## Contributing
How to contribute, branch conventions, PR process.

## License
License information.
```

### Architecture Decision Records (ADRs)

ADRs capture the *context*, *decision*, and *consequences* of architectural choices.

**Template (Michael Nygard format):**
```markdown
# ADR-NNN: [Title]

**Status:** Proposed | Accepted | Deprecated | Superseded by ADR-XXX
**Date:** YYYY-MM-DD

## Context
What is the issue? What forces are at play?

## Decision
What have we decided to do?

## Consequences
What are the positive and negative results of this decision?

## Alternatives Considered
What other options were evaluated and why were they rejected?
```

**Rules:**
- ADRs are immutable once accepted. If the decision changes, create a new ADR that supersedes the old one.
- Number ADRs sequentially: `ADR-001`, `ADR-002`, etc.
- Store in `docs/adr/` or `docs/decisions/`.

### Doc-as-Code

Treat documentation like code:
- Store in version control alongside the code.
- Review documentation changes in PRs.
- Automate doc generation (Sphinx, TypeDoc, Javadoc, Godoc, rustdoc).
- Lint documentation (markdownlint, vale).
- Test code examples in docs (doctest, mdx-js).

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Public API documented** | 100% | Every public function/class/endpoint has docstring/JSDoc. |
| **README exists and is current** | Yes | Must reflect the current state of the project. |
| **ADR for each architectural decision** | All major decisions | Architectural choices without ADRs are undocumented debt. |
| **No outdated documentation** | Reviewed quarterly | Stale docs are worse than no docs. |
| **Changelog maintained** | Updated with each release | Every user-facing change must be recorded. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Book-writing** | 50-page design docs nobody reads. | Keep docs concise. Use diagrams. Link to code. |
| **Commenting the obvious** | `i += 1 // increment i` pollutes the codebase. | Comment only on *why*. |
| **Orphaned docs** | Docs in a wiki that nobody updates when code changes. | Docs live in the repo, reviewed in PRs. |
| **No ADRs** | "Why did we choose X?" becomes unanswerable after the original author leaves. | Write ADRs at decision time. 15 minutes saves hours later. |
| **Missing examples** | API docs list parameters but show no usage. | Every public API gets at least one usage example. |


## See Also

- [Code Review](../code_quality/code_review.md)
- [API Design](../architecture/api_design.md)

## References

- Tom Preston-Werner, ["Readme Driven Development"](https://tom.preston-werner.com/2010/08/23/readme-driven-development.html)
- Michael Nygard, ["Documenting Architecture Decisions"](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)
- Keep a Changelog: https://keepachangelog.com/
- Divio Documentation System: https://documentation.divio.com/ -- four types: tutorials, how-to guides, reference, explanation.
