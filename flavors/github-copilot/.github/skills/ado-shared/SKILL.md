---
name: ado-shared
description: Shared Azure DevOps integration patterns — defaults resolution, required-vs-optional availability checks, fallback behavior, and reference hygiene.
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
