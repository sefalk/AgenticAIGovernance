---
title: Glossary
type: concept
description: Terms and acronyms used across the AAIG framework and this wiki.
tags: [aaig, governance, glossary, reference]
updated: 2026-07-03
sources: [core/L1_Framework_Architecture.md, core/L1_Core_Principles.md, flavors/github-copilot/.github/af-env.conf]
---

# Glossary

| Term | Definition |
|---|---|
| **AAIG** | Agentic AI Governance — this framework. |
| **L0–L4** | The five governance levels: [Assimilation](04-assimilation.md), [Core Principles](03-core-principles.md), [Domain Rules](05-domains.md), [Workflows](06-workflows.md), Project Instantiation. See [Architecture](02-architecture.md). |
| **Core** | The generic, platform-agnostic framework in `core/` — the source of truth. |
| **Flavor** | A concrete adaptation of core to a specific agent engine (e.g. [`github-copilot`](09-flavor-github-copilot.md)). |
| **Derivation** | An artifact is *properly derived* when it references its parent level, passed review, has a version, and does not contradict ancestors. |
| **Primary Agent** | The agent producing a deliverable and proposing its quality gates. |
| **Reviewer** | The agent (or human) evaluating the Primary's output; must differ from the Primary in multi-agent setups. |
| **Quality-Owner** | Approves quality-gate definitions; defaults to the human User. |
| **Capability Worker** | A provider-scoped worker integrating one external platform capability, named `{provider}-{capability}-{role}`. |
| **Capability Cell** | A worker + reusable skill package + explicit availability/fallback/traceability gates. |
| **Maker-Checker** | The pattern where a *different* agent reviews each output. See [Agent Team](10-agents.md). |
| **Quality Gate** | A programmatically computed pass/fail check. Types: **HARD** (blocks), **SOFT** (reviewer judges), **ADVISORY** (informational). |
| **Complexity Tier** | Trivial / Standard / Deep — scales how many gates apply. |
| **Specialization Prompt** | The L0 step where the User activates a subset of domains/skills. |
| **Active / Dormant** | Deployed capabilities that are prioritized (Active) vs available on demand (Dormant). |
| **L4 Contract / Binding** | Project-specific bindings of generic workflows; in the flavor, [`af-env.conf`](13-configuration.md) + `copilot-instructions.md`. |
| **Fail-Safe** | The rule to halt and ask rather than guess under uncertainty. |
| **Graceful Degradation** | Continuing via a documented fallback when an *optional* integration is unavailable. |
| **ADR** | Architecture Decision Record — a documented design decision. |
| **Provenance Marker** | An in-code `copilot:generated` / `copilot:modified` comment marking AI-authored content. |
| **Hook** | A deterministic script enforcing a gate. See [Hooks & Autonomy](11-hooks-and-autonomy.md). |
| **Autonomy Tier** | `allow` / `ask` / `deny` classification of a terminal command. |
| **R-SD- / R-DE- / …** | Rule prefixes per [L2 domain](05-domains.md) (Software Dev, Data Engineering, …). |
| **Project wiki vs Code wiki** | ADO project-wide wiki (`ADO_WIKI_IDENTIFIER`) vs repo-versioned docs (`ADO_CODE_WIKI_PATH`, e.g. this wiki). |
| **MCP** | Model Context Protocol — how capability workers reach external providers (e.g. Azure DevOps). |

## See also

- [Index](index.md) · [Overview](01-overview.md) · [Architecture](02-architecture.md)
