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
| A whole family is absent (all wiki tools, all pipeline tools) | **Tool filtering** — `-d` args (local) or `X-MCP-Toolsets` / `X-MCP-Tools` headers (remote) exclude that group | Add the group to the filter; keep `core` enabled |
| Reads work, every write is rejected | `X-MCP-Readonly` is set (remote only) | Remove the header for workflows that create or update artifacts |
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
See *Remote vs Local Server* below.

## Remote vs Local Server

The remote server would remove the version-drift surface entirely: it is
versioned server-side, and there is no `npx` package to pin or update.

**The tool ids are the same consolidated names on both servers.** A switch is
therefore a configuration change, not an agent rewrite — the migration this
framework already performed is the prerequisite either way, and the
`check-mcp-tool-ids.py` guard stays valid.

Two things do change:

- **Authentication:** remote is Microsoft Entra ID (OAuth) only. The `azcli`
  and PAT paths above do **not** apply; VS Code prompts for an Entra account,
  and the organization must be Entra-connected.
- **Organization:** baked into the URL. It may be omitted from the URL, but
  then every tool call must carry it as context — which is what
  `ADO_ORGANIZATION` is for.

**Current recommendation: stay on the local server.** Evaluated 2026-07 against
the remote server documentation; the blockers are concrete, not stylistic:

| Blocker | Impact |
|---|---|
| Public preview, rolling out gradually | Availability is not guaranteed per organization |
| WIQL is Insiders-only (`X-MCP-Insiders`) | `wit_query` offers only `get` / `get_results` remotely; the work-item worker's WIQL matching degrades |
| `wiki` exposes no `get_page_content` action | Folded into `get_page`; the wiki worker's read path needs adjusting |
| VS Code and Visual Studio only | Other MCP clients need OAuth client registration in Entra and cannot connect |

Re-evaluate at general availability, or earlier if WIQL leaves Insiders. The
first two rows would force agent changes; the rest are environmental.

## Reference Hygiene

Whenever you mention an ADO artifact (work item, pull request, wiki page,
build/pipeline run, repository, or branch) in your output, render it as a
clickable Markdown link -- `[<label>](<web-url>)` -- never a bare id or a raw
API URL. This applies to the worker's returned summary so the coordinator
surfaces the clickable reference to the user in chat.

- **URL source:** use the web URL from the MCP response
  (`webUrl` / `remoteUrl` / `_links.html.href`). Only if the response carries
  no web URL, construct it from the canonical pattern using
  `ADO_ORGANIZATION` + `ADO_PROJECT`:
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

## Coordinator Workflow Sequences

For the **coordinator only**, and only when `ADO_CAPABILITY_MODE != off`
(the default is `off`). `coordinator.agent.md` names these workflows and the
work-item-first rule; the sequences and their contracts live here.

### ADO Sync Workflow

```
ado-work-item-manager(resolve + set Active)   # WIT-first, BEFORE the branch
   -> [create branch agent/{wit-id}-{slug}]
   -> compliance-checker(pre)
   -> ado-wiki-manager (optional, task-dependent)
   -> ado-work-item-manager(finalize: AC->evidence map, no Close)
   -> compliance-checker(post)
   -> [push feature branch] -> ado-pr-manager (autocomplete, transitionWorkItems:false)
   -> [merge confirmed] -> ado-work-item-manager(reconcile: delivered state w/ evidence)
```

Use this only when the project contract defines Azure DevOps capability as
required or optional. If optional and unavailable, require degraded fallback
output and continue with local traceability artifacts.

### Step 0a: Work-Item First

Establish the work item before any branch exists, so code and tracker stay
aligned from the start (this prevents reactive, mis-attributed, or WIT-less work):

1. Invoke **ado-work-item-manager** (`mode=resolve`) to find or create the work
   item for **this specific task**. One unit of work → one work item; do not
   reuse an unrelated open item — infra/dependency bumps, tooling fixes, and
   analysis tasks each get their own item. If the task spans several concerns,
   split them.
2. Ensure the item is set to **Active** at work start.
3. Use its id in the branch slug: `agent/{work-item-id}-{workflow-id}`.
4. **No branch without a resolved work item.** If resolution is impossible
   (capability required but unavailable), halt and escalate (Fail-Safe).

The **planner** may propose the work item title/scope; the **coordinator**
confirms the item and its id before branch creation. This id is the single
source of truth for the branch slug, the PR link, and post-merge reconciliation.

#### Work-item type selection (on create)

Type follows **structural role**, not how large the task feels. The choice is
effectively irreversible — a retype can drop type-specific data — and it
decides which fields and which *states* exist at all.

| The item… | Type |
|---|---|
| may acquire children, or spans phases | **Feature** |
| is one shippable increment with its own acceptance criteria | **User Story** |
| is a defect in behaviour that already shipped | **Bug** |
| is leaf work under an existing parent, closed by that parent's verification | **Task** |

**The Task constraint (measured, Agile template).** `Task` has the states
New / Active / Closed / Removed — **no `Resolved`**. An item whose delivery has
to be reconciled post-merge therefore cannot be a Task: the reconciliation
target does not exist on the type, and the item strands in Active. Default to
**User Story** whenever the item *is* the thing being delivered; use Task only
for leaf work whose closure rides on a parent. Reported but not measured here:
ADO also rejects Task-under-Task parenting, so a Task cannot be promoted into
a container later.

The `ado-work-item-manager`'s State-Applicability Guard catches a bad type at
transition time — choosing correctly here is what keeps it from firing.

### ADO Pipeline Workflow

```
compliance-checker(pre)
        -> [implementer: pipeline YAML + gate script]
        -> code-critic -> documenter
        -> ado-pipeline-manager (register + run + verify)  [optional]
        -> compliance-checker(post)
        -> [push feature branch] -> ado-pr-manager (optional)
```

Use this when the deliverable is establishing or operating an Azure DevOps
pipeline (e.g., a PR quality-gate / build-validation pipeline). The
**implementer** authors the pipeline YAML and any gate script; the
**ado-pipeline-manager** registers the definition, runs it to verify
(cross-checking agent-pool availability), and emits the exact Build Validation
branch-policy settings. **Attaching the branch policy is human-guided** — no
MCP tool exists for policy creation; the coordinator relays the emitted
settings to the human. When `ADO_CAPABILITY_MODE=off`, do not run
`ado-pipeline-manager`.

### Request-Based Integration Path

Applies once an ADO PR capability is enabled. (The pure-git default — never
run `ado-pr-manager`, push and merge stay human-controlled — is stated in
`coordinator.agent.md`.)

After a clean post-flight, the coordinator pushes the feature branch
`agent/{id}` from the active work location (main checkout or worktree, per
`WORKTREE_ENABLED`) with `git push -u origin agent/{id}` — never a protected
branch, never force. Then it invokes `ado-pr-manager` to open/update the PR and
apply the branch-scoped completion policy: an integration branch autocompletes,
a protected branch is human-only.

If the PR manager returns `BLOCKED_BRANCH_NOT_PUBLISHED` or
`BLOCKED_BRANCH_PROBE_INDETERMINATE`, **verify with
`git ls-remote --heads origin agent/{id}` before pushing again** — the probe
is the agent's, the ref is the remote's, and only one of them is authoritative.
Push only when `ls-remote` returns nothing. Re-pushing a branch that is already
published, or already merged and deleted, recreates it as an orphan with no PR,
leaving that commit outside the integration branch unnoticed.

### Post-Merge Reconciliation (mandatory, request-based)

The PR carries `transitionWorkItems: false`, so it never changes work-item
status. (ADO's own auto-transition fires only for PRs targeting the
**default** branch, so against an integration branch such as `dev` it would
never fire anyway — the reconciliation below is the only thing that moves
status.) Once the merge into the integration branch is **confirmed**, invoke
**ado-work-item-manager** to transition the linked work item into the state
its **type** defines as delivered-pending-verification, with an AC→evidence
map. The target is resolved from `wit_work_item` (action `get_type`), never
hard-coded: `Resolved` exists on a User Story or Bug but not on a Task, and
the worker's **State-Applicability Guard** decides what happens when the type
has none. A `Completed`-category state comes only later, at verification /
promotion.

This is the single point where the code and work-item state machines reconnect
— status follows merged evidence, never the PR's auto-transition.

See `skills/git-workflow/SKILL.md` § 2 for the full two-path integration contract.
