---
title: "Flavor: GitHub Copilot"
type: architecture
description: The concrete, deployable AAIG implementation for VS Code + GitHub Copilot — layout and how it maps to core.
tags: [aaig, flavor, architecture, agents]
updated: 2026-07-29
sources: [flavors/github-copilot/README.md, flavors/github-copilot/VERSION, flavors/github-copilot/.github/MANIFEST.md, flavors/github-copilot/.github/.af-manifest]
---

# Flavor: GitHub Copilot

The **`github-copilot`** flavor is the reference implementation of AAIG: a
drop-in `.github/` package that turns VS Code + GitHub Copilot (agent mode) into
an **autonomous, quality-gated, multi-agent TDD team**. It compiles the
[generic core](02-architecture.md) into the host's native syntax — `.agent.md`
personas, `.instructions.md` rules, and deterministic shell hooks.

Current framework version: see `flavors/github-copilot/VERSION`.

## What it delivers

- A [specialized agent team](10-agents.md) of 15 personas driven by a **coordinator**.
- **Test-Driven Development** enforced as separate Red → Green → Refactor phases.
- **[Deterministic hooks](11-hooks-and-autonomy.md)** that run pytest, scan for
  secrets, and block destructive commands with real code, not suggestions.
- The **[maker-checker pattern](10-agents.md)** — every output is reviewed by a
  critic agent.
- **Escalation, not surprise** — the coordinator asks the human when it needs
  domain input.

## Repository layout of the flavor

| Path | Contents |
|---|---|
| `.github/` | The deployable framework package (detailed below) |
| `.vscode/` | Deployable editor payload: `tasks.json`, `settings.json`, `toolsets.jsonc` |
| `deploy.ps1` / `deploy.sh` | The script delivery path ([Deployment](12-deployment.md)) |
| `mcp-deploy/` | The experimental **MCP deploy server** (`af-deploy-mcp`) — delivers the payload without an AF clone |
| `templates/` | Plan / WIP / investigation templates used by agents |
| `VERSION`, `CHANGELOG.md` | Semantic version + Keep-a-Changelog release history |
| `agent-framework-map.v2.html` | Interactive map of the framework |

## `.github/` layout

| Path | Contents |
|---|---|
| `agents/` | The 15 agent personas (`.agent.md`) — coordinator, core workers, ADO capability workers |
| `instructions/` | `.instructions.md` rule files (architecture, git-workflow, quality-gates, provenance, testing, copilot-authoring) with `applyTo` globs |
| `skills/` | Activated skill set + `INDEX.md` + `_available/` staging (incl. `ado-*` capability skills) |
| `prompts/` | Slash-command prompts, all `af-*` prefixed (`/af-tdd-feature`, `/af-quick-fix`, `/af-setup-project`, …) |
| `hooks/` | `agent-hooks.json` + `scripts/` (agent hooks) + `git/` (real git hooks) — the deterministic enforcement layer |
| `templates/` | Plan / WIP / investigation templates |
| `scripts/` | Test runner, bootstrap, metrics, worktree and audit helpers |
| `logs/`, `retros/` | Workflow logs and retrospectives (traceability) |
| `af-env.conf` | The **L4 binding** — project config read by all hooks ([reference](13-configuration.md)) |
| `MANIFEST.md`, `GOVERNANCE.md`, `TOOLS.md`, `TROUBLESHOOTING.md` | Team manifest, governance summary, tool catalog, diagnostics |
| `.af-manifest`, `.af-version`, `.af-hashes` | Deploy metadata for three-way merge ([Deployment](12-deployment.md)) |

## How core maps to the flavor

| Core concept | Flavor realization |
|---|---|
| [L0 Assimilation](04-assimilation.md) | [Deploy](12-deployment.md) + `/af-onboard-project` + `/af-curate-skills` (chained by `/af-setup-project`) |
| [L1 Principles](03-core-principles.md) | Agent instructions, critics, hooks, provenance, escalation |
| [L2 Domains](05-domains.md) | `instructions/*.instructions.md` + activated skills |
| [L3 Workflows](06-workflows.md) | Coordinator pipeline + slash-command prompts |
| L4 Instantiation | [`af-env.conf`](13-configuration.md) + `copilot-instructions.md` |
| [Skills Toolbox](07-skills-toolbox.md) | `.github/skills/` (active) + `_available/` (dormant) |
| Capability cells | `ado-*` agents + `ado-*` skills, gated by `ADO_CAPABILITY_MODE` |

## Getting started

Deploy the package into a target repo and run `/af-setup-project` — it chains
deploy → `/af-onboard-project` → `/af-curate-skills` in one confirmation. Then
drive work with `@coordinator <task>` or a slash command. Full mechanics on the
[Deployment](12-deployment.md) page.

## See also

- [Agent Team](10-agents.md) · [Hooks & Autonomy](11-hooks-and-autonomy.md) · [Configuration](13-configuration.md)
