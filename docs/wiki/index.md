---
title: AAIG Wiki — Index
type: overview
description: Routing catalog and entry point for the Agentic AI Governance (AAIG) code wiki.
tags: [aaig, governance, index, reference]
updated: 2026-07-03
sources: [README.md, core/L1_Framework_Architecture.md]
---
<!-- copilot:generated | documenter | 2026-07-03 -->

# AAIG Wiki — Index

Welcome to the **Agentic AI Governance (AAIG)** wiki. AAIG is a framework of
governance constraints, quality gates, and organizational architecture for
autonomous AI agents. Start with the [Overview](01-overview.md), then drill
into any area below.

> **How to read this wiki.** Top-down: the [Overview](01-overview.md) covers
> every aspect at high altitude; each page below is a self-contained deep dive.
> Pages cite their source files so you can go from synthesis to the source of
> truth in one hop.

## Catalog

### Start here

| Page | What it covers |
|---|---|
| [01 · Overview](01-overview.md) | What AAIG is, the problem it solves, the whole picture at a glance |
| [02 · Architecture](02-architecture.md) | Monorepo (core vs flavors), the five levels L0–L4, roles |

### The generic framework (`core/`)

| Page | What it covers |
|---|---|
| [03 · Core Principles (L1)](03-core-principles.md) | The universal, binding principles all agents obey |
| [04 · Assimilation (L0)](04-assimilation.md) | How an agent boots into a governed repository |
| [05 · Domains (L2)](05-domains.md) | Per-domain `SHALL / SHALL NOT` rule sets |
| [06 · Workflows (L3)](06-workflows.md) | Step-by-step procedures with entry/exit gates |
| [07 · Skills Toolbox](07-skills-toolbox.md) | Expert-knowledge templates agents invoke on demand |
| [08 · Benchmark](08-benchmark.md) | How agent compliance is measured and graded |

### The concrete implementation (`flavors/github-copilot/`)

| Page | What it covers |
|---|---|
| [09 · Flavor: GitHub Copilot](09-flavor-github-copilot.md) | The deployable agent framework built on core |
| [10 · Agent Team](10-agents.md) | The agents, the maker-checker pattern, TDD phases |
| [11 · Hooks & Autonomy](11-hooks-and-autonomy.md) | Deterministic enforcement + the three-tier autonomy classifier |
| [12 · Deployment & Versioning](12-deployment.md) | `deploy.ps1/.sh`, three-way merge, auto-versioning |
| [13 · Configuration](13-configuration.md) | `af-env.conf` reference |

### Operations & reference

| Page | What it covers |
|---|---|
| [14 · Governance Change](14-governance-change.md) | The high-risk change protocol and contribution flow |
| [15 · Glossary](15-glossary.md) | Terms and acronyms |

## Conventions

This wiki follows the `ado-wiki` skill: every page declares a **type** and YAML
frontmatter, reuses a controlled tag vocabulary, cites its **sources**, and
prefers synthesis over duplication. It is a **code wiki** — versioned in the
repository under `docs/wiki/`, reviewed alongside the code.
