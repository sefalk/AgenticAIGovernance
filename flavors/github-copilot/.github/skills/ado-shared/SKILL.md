---
name: ado-shared
description: Shared Azure DevOps integration patterns — defaults resolution, required-vs-optional availability checks, fallback behavior, authentication and toolset-drift recovery, and reference hygiene.
argument-hint: '[capability: work-item|wiki|repo] [mode: required|optional]'
disable-model-invocation: true
---

# ADO Shared Skill

Reusable guidance for Azure DevOps provider integrations.

## When to Use

- Any ADO capability worker (`ado-*`) before invoking platform APIs
- Workflows that need required/optional integration behavior
- Situations where ADO credentials or connectivity might be unavailable

## Core Rules

1. Read project defaults from `.github/af-env.conf` when present.
2. Classify capability as `required` or `optional`.
3. Run a lightweight availability probe before write operations.
4. If `required` and unavailable: halt and escalate.
5. If `optional` and unavailable: continue with fallback artifact + pending-sync marker.

## Fallback Contract

When degraded mode is used, always emit:

- explicit `status=DEGRADED`
- what was skipped
- local fallback artifact path
- synchronization recommendation

## Authentication

The MCP server authenticates as **you**, not as the agent. Agents never handle
credentials and must never write a token into a config file or a prompt.

**Decision tree:**

| Situation | Mode | Setup |
|---|---|---|
| Single-tenant dev machine | Interactive browser login (implicit default) | Nothing — the first tool call opens a login prompt |
| Multiple tenants, or wrong identity gets picked | **`azcli` (preferred fallback)** | `--authentication azcli` in the server args + `az login --tenant <tenantId>` |
| Azure Pipelines / CI | Token from the environment | `SYSTEM_ACCESSTOKEN` (or a PAT env var); never interactive |

Prefer `azcli` whenever the identity is ambiguous. Its advantage is not
convenience but **inspectability**: `az account show` tells you exactly which
account and tenant the server will use, whereas the browser flow silently
reuses whatever session the browser already had.

**Tenant handling.** Guest accounts that exist in several tenants are the
common failure: login succeeds, but against the wrong tenant, so the
organization appears empty or every call returns 401/403. Pin it explicitly:

```
az login --tenant <tenantId>
az account show          # verify tenantId and user before blaming the toolset
```

**Never** place a PAT in `.vscode/mcp.json` — that file is committed. Use an
environment variable or an `inputs` prompt.

## Toolset Drift Recovery

Three different faults present the identical symptom — *the agent behaves as if
a tool does not exist*. Diagnose in this order before changing anything:

| Symptom | Cause | Fix |
|---|---|---|
| One tool name rejected; agent silently drops it | **Toolset consolidation upstream** — the tool was merged into a grouped tool with an `action` parameter | Run `.github/scripts/check-mcp-tool-ids.py`; migrate the ids it reports |
| A whole family is absent (all `wiki_*`, all `pipelines_*`) | **Domain filter** — the server's `-d` args exclude that domain | Add the domain to `-d` in `mcp.json`; `core` should always be present |
| Tools are listed, but every call returns 401/403 | **Identity/tenant**, not the toolset | See *Authentication* above |

The first case is the dangerous one: an unknown tool id fails prompt validation
and is dropped **without an error**, so the agent runs with a silently reduced
toolset and reports plausible-looking failures instead of a configuration fault.

**Recovery:**

1. Restart the MCP server and inspect the actual tool list it advertises.
2. Compare against `docs/TOOLSET.md` for the installed server version.
3. Run `.github/scripts/check-mcp-tool-ids.py` — it maps every known legacy id
   to its replacement plus the required `action`.
4. Update the agent frontmatter *and* the prose. Prose references matter: the
   agents instruct each other by tool name, so a stale name in prose sends the
   worker after a tool it does not have.

**Version policy.** This framework targets `@azure-devops/mcp@latest`
deliberately: drift risk is accepted in exchange for current features, on the
condition that recovery is fast. The checker plus this runbook are what make
that trade defensible — without them the risk is not "quickly fixable", it is
merely undetected. Pin to a known-good version only if drift recurs often
enough to outweigh the feature lag. (`@next` is nightly and drifts more.)

Microsoft now recommends the **remote** server (`https://mcp.dev.azure.com/{org}`,
transport `http`) over the local `npx` server and is focusing new work there.
Migrating removes the version-drift surface entirely.

## Reference Hygiene

Whenever you mention an ADO artifact (work item, pull request, wiki page,
build/pipeline run, repository, or branch) in your output, render it as a
clickable Markdown link -- `[<label>](<web-url>)` -- never a bare id or a raw
API URL. This applies to the worker's returned summary so the coordinator
surfaces the clickable reference to the user in chat.

- **URL source:** use the web URL from the MCP response
  (`webUrl` / `remoteUrl` / `_links.html.href`). Only if the response carries
  no web URL, construct it from the canonical pattern using the resolved
  organization + `ADO_PROJECT`:
  - Work item:    `https://dev.azure.com/{org}/{project}/_workitems/edit/{id}`
  - Pull request: `https://dev.azure.com/{org}/{project}/_git/{repo}/pullrequest/{prId}`
  - Wiki page:    the page's `remoteUrl` from the wiki MCP response
  - Build run:    the run's `_links.web.href` from the pipeline response
- **Labels** are human-readable: `[#1234 -- <title>](url)`,
  `[PR !78 -- <title>](url)`, `[Wiki: <page path>](url)`.
- Never fabricate an id or link you cannot validate against a real MCP response.
- Use `pending-sync` (no link) only when the artifact does not exist remotely
  yet (e.g., a PR before its branch is pushed).

## Gate Reminder

A capability run is incomplete unless it reports:

- probe result
- required/optional decision path
- execution mode (`platform` or `fallback`)

## Canonical Boilerplate (DRY)

This skill is the **single source** for behavior shared by all `ado-*`
workers, so the individual agents reference it instead of restating it:

- **Execution defaults:** read `.github/af-env.conf`; pass `ADO_PROJECT`
  explicitly on every project-aware MCP call; never rely on interactive
  project prompts.
- **Repository resolution order:** `ADO_REPOSITORY_ID` -> `ADO_REPOSITORY_NAME`
  -> list-and-match.
- **Gate summary format:** every worker ends with the standard Gate Summary
  block including the `Skills Read` line.

When these rules change, update them here once; workers should not duplicate
the detail.
