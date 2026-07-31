---
name: ado-pr
description: Azure DevOps pull request lifecycle — branch publication precondition, PR create/update, work-item/plan linking, and the branch-scoped autocomplete policy (integration branch autonomous, protected branch human-only).
disable-model-invocation: true
---

# Azure DevOps Pull Request Skill

## Purpose

Provider-specific guidance for the Azure DevOps pull request lifecycle:
creating and updating PRs, linking work items and plans, and applying the
branch-scoped completion policy. Used by the optional `ado-pr-manager` to
implement request-based integration. Implements the provider-agnostic
`pr_integration_management` contract for Azure DevOps.

## When to Use

- A workflow has finished its local commits on an `agent/*` branch and the
  project enables ADO request-based integration.
- A PR needs creation, update, reviewer assignment, or completion handling.

## Core Rules

1. Read project and repository defaults from `.github/af-env.conf` first.
2. The coordinator pushes the feature branch (`agent/*`); the PR manager has
   no terminal access and never pushes — verify the branch exists on the
   remote before creating the PR.
3. Resolve the target branch before creating a PR (default `dev`).
4. Reuse an existing active PR for the source branch instead of duplicating.
5. Always link the related work item and the implementation plan to the PR.

## Work Item Linking

- Preferred: pass the work item id(s) via the `workItems` parameter of
  `repo_pull_request_write` (action `create`) at creation.
- Fallback: if the work item is not attached, return `NEEDS_WORKITEM_LINK`
  with the PR id so the `ado-work-item-manager` adds the PR artifact link
  (`wit_work_item_link_write` action `add_artifact_link`, or action
  `link_to_pull_request`) afterward.
- Always report which linkage path was used.
- **Autocomplete depends on the link:** with a `linked work items = Required`
  policy, do not set autocomplete until the work item is linked. If the link
  is deferred, return `NEEDS_WORKITEM_LINK` first; set autocomplete only after
  the link is confirmed.

## Plan Reference Verification

- Before posting a clickable plan URL, verify the file exists on the target
  branch/ref via repository content lookup (`repo_file` action `get_content`).
- If the plan is not yet on the remote, mark the reference as `pending push`
  rather than posting a URL that 404s.

## Traceability Thread

- After create/update, post a single concise thread via
  `repo_pull_request_thread_write` (action `create`) **with a resolved status**
  (`status: Closed`) summarizing the linked work item, plan reference, and
  completion mode. The resolved status is mandatory: a
  `comment resolution = Required` branch policy blocks autocomplete while any
  thread is active. Do not duplicate it on re-runs.

## Branch-Scoped Completion Policy

The completion behavior is determined by the PR **target branch**:

- **Autocomplete branches** (`ADO_PR_AUTOCOMPLETE_BRANCHES`, default `dev`):
  autonomous mode (A2). Call `repo_pull_request_write` (action `update`) with
  `autoComplete: true`, `mergeStrategy` from `ADO_PR_MERGE_STRATEGY`
  (default `noFastForward`), `deleteSourceBranch: true`, and
  `transitionWorkItems: false` (the MCP default is `true` — always set it
  explicitly in the same call) so the platform merges it once branch policies
  pass without auto-transitioning linked work items.
- **Merge strategy (Mandatory):** always pass `mergeStrategy` from
  `ADO_PR_MERGE_STRATEGY` (default `noFastForward`). Never use `squash` for
  `agent/*` branches: squash creates a new commit that does not contain the
  feature-branch tip, so the coordinator's post-merge `git branch -d agent/*`
  fails as "not fully merged" and the only cleanup left is a policy-denied
  force-delete. `noFastForward` keeps the branch tip reachable and lets safe
  deletion succeed.
- **Human-only branches** (`ADO_PR_HUMAN_ONLY_BRANCHES`, default `main`):
  human mode (A1). Create/update the PR only; never set `autoComplete`/`status`.
- **Unresolved / other targets:** safe default is human-only.

Promotion from the integration branch to a protected branch is therefore
always a human-completed PR.

## Branch Publication

- The PR manager has no terminal access and never pushes.
- The coordinator pushes the feature branch (`agent/*`) before the PR manager
  is invoked, from the active work location (main checkout or worktree,
  depending on `WORKTREE_ENABLED`).
- Verify the source branch exists on the remote before creating the PR; if it
  is absent, return `BLOCKED (branch not published)` so the coordinator pushes.

## Safety Note

Branch-scoped autocomplete is only a real control when backed by **server-side
branch policies** and **permission scoping** (no policy-bypass on the agent
identity). Agent prompts are conventions, not the security boundary.

## Failure Taxonomy

- `BLOCKED_AUTH`: credentials/session unavailable.
- `BLOCKED_CONFIG`: required defaults missing (project/repository).
- `BLOCKED_BRANCH_NOT_PUBLISHED`: source branch absent on the remote.
- `NEEDS_HUMAN_COMPLETION`: PR targets a human-only branch.
- `DEGRADED`: PR created but autocomplete unavailable (policy not configured).

## Output Requirements

- Return machine-readable status labels and the resolved completion mode.
- Include the PR id/URL (or a `pending` marker) for traceability.
- Include a Gate Summary with a `Skills Read` line.
