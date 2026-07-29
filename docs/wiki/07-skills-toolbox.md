---
title: Skills Toolbox
type: concept
description: The library of expert-knowledge skill templates agents invoke during L2–L4 derivation.
tags: [aaig, governance, skills, reference]
updated: 2026-07-29
sources: [core/skills/_index.md, flavors/github-copilot/.github/skills/INDEX.md]
---

# Skills Toolbox

The **Skills Toolbox** (`core/skills/`) is a library of optional, detailed
skill templates providing state-of-the-art guidance for a specific practice
area (unit testing, secure coding, refactoring, data modeling, …). Skills are
invoked as **expert knowledge** while deriving [L2 rules](05-domains.md),
[L3 workflows](06-workflows.md), or L4 bindings.

## Categories

Skills are organized by category directory:

`testing/` · `code_quality/` · `architecture/` · `data_engineering/` ·
`data_science/` · `devops/` · `embedded/` · `project_management/` · `security/`

## How agents use skills

1. **Full-spectrum deployment** — during [assimilation](04-assimilation.md) the
   entire toolbox is deployed.
2. **Active specializations** — the User activates a subset via the
   Specialization Prompt; these load into the agent's active context.
3. **On-demand activation** — dormant skills activate later without
   re-assimilation.
4. **Partial reading** — you can read just one section of a dormant skill (e.g.
   *Quality Gates* for thresholds, *Anti-Patterns* for review) without fully
   activating it.

> **When to skip skills.** Skills add value for design decisions and quality-
> critical work — **not** for single-file bug fixes, config changes, doc-only
> edits, version bumps, or well-known refactors. Trivial work should not carry
> skill overhead (Efficiency principle).

## Skill metadata

Each skill carries YAML frontmatter with a controlled `applies_to` taxonomy
(`all`, `web`, `api`, `data`, `ml`, `cli`, `library`, `microservice`, `cloud`,
`mobile`, `desktop`), a `complexity` (foundational / intermediate / advanced),
and a `maturity`:

| Maturity | Meaning |
|---|---|
| **draft** | New, not peer-reviewed — verify independently |
| **reviewed** | Passed review — reliable for general use |
| **proven** | Applied successfully in real projects — high confidence |

Promotion `draft → reviewed` needs a review pass; `reviewed → proven` needs
documented evidence of successful real-world use.

## Selection aids

The toolbox index provides a **Skill Selection Heuristic** (project type →
starter skills) and named **bundles** (e.g. *New Service Setup*, *Quality
Hardening*, *Security Audit*, *Data Platform*, *Production Readiness*, *ML
Platform*) that load a coherent multi-skill set for a scenario.

## Traceability

Every skill links at least one of its principles back to an
[L1 principle](03-core-principles.md) using `**PrincipleName (AAIG L1):** …`,
keeping the toolbox anchored to the governing framework. A `related` frontmatter
field is the source of truth for cross-references rendered under *See Also*.

## In the Copilot flavor

The flavor ships its own activated skill set under `.github/skills/` (with an
`INDEX.md` and an `_available/` staging area), including capability-worker
skills such as `ado-wiki/`, `ado-pr/`, `ado-workitem/`, and `ado-shared/`. See
[Flavor: GitHub Copilot](09-flavor-github-copilot.md).

Activation is not manual guesswork: `/af-curate-skills` matches the toolbox
against the stack detected during onboarding, keeps the matching skills in
`skills/`, and **moves** the rest to `skills/_available/`. Deploy recognizes
that move as [DEACTIVATED](12-deployment.md) and never re-creates them — so a
project's curation survives every framework update.

## See also

- [Domains (L2)](05-domains.md) · [Workflows (L3)](06-workflows.md) · [Agent Team](10-agents.md)
