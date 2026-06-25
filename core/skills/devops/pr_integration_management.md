# Pull / Merge Request Integration

**Type:** DevOps & Deployment skill (provider-agnostic)
**Applies to:** projects that integrate changes through pull/merge requests

## Purpose

Describe how an agent team integrates committed work into shared branches
through **pull/merge requests** instead of local merges, in a
provider-neutral way. This is an **optional** capability layered on top of
the default pure-git workflow (local commits; remote push and merge are
human-controlled). When a project enables a request-based integration
provider, this skill defines the shared contract.

> Concrete providers implement this contract through a capability worker
> (for example an Azure DevOps PR worker). The same model applies to GitHub
> pull requests or GitLab merge requests with provider-specific workers.

## Path Separation (Mandatory)

A project runs exactly one of two integration paths:

1. **Default — pure git.** No request provider configured. The orchestrator
   commits locally; pushing and merging remain human-controlled. No
   integration worker participates.
2. **Optional — request-based integration.** A provider capability is
   enabled. The orchestrator publishes (pushes) the feature branch; an
   integration worker opens/updates the request and applies the
   branch-scoped completion policy.

The path is selected by configuration, not hard-coded. Pure git is the
safe default.

## Branch-Scoped Completion Policy

Completion (merge) behavior is determined by the **target branch class**:

| Target branch class | Mode | Completion |
|---|---|---|
| Integration branch (e.g. `dev`) | Autonomous | Worker may enable auto-complete; the platform merges once branch policies pass |
| Protected/release branch (e.g. `main`) | Human-only | Worker creates/updates the request only; a human completes it |
| Unresolved / other | Safe default | Treated as human-only |

Promotion from the integration branch to a protected branch is therefore
always a human-completed request.

## Responsibility Split

- **Orchestrator** owns local git, including the **single** push of the
  feature branch (`agent/*`) from the active work location. It never pushes
  to protected branches and never force-pushes.
- **Integration worker** has no terminal/git access. It verifies the branch
  is published on the remote, then manages the request through the provider
  API only.

## Required Behavior

1. Verify the feature branch exists on the remote before creating a request;
   otherwise return a blocked status so the orchestrator pushes first.
2. Reuse an existing open request for the source branch instead of creating
   a duplicate.
3. Link the tracked work item and the implementation plan to the request.
4. Apply the branch-scoped completion policy for the resolved target.
5. Post a concise, idempotent traceability summary on the request.

## Safety Invariants

- Auto-complete is only ever set for autonomous integration branches.
- Protected/release completion is never automated.
- The completion control is a server-side branch policy plus permission
  scoping — agent prompts are conventions, not the security boundary.

## Output Requirements

- Machine-readable status (created/updated/auto-complete-set/needs-human/
  degraded/blocked).
- Resolved target branch and completion mode.
- Request id/URL or an explicit pending marker for traceability.

## Known Limitation

This contract is provider-agnostic **by design**, but only **Azure DevOps**
has a concrete worker (`ado-pr-manager`) today. GitHub pull requests and
GitLab merge requests are contract-compatible but **not yet implemented** —
they would require their own workers and skills. Treat provider neutrality as
a design goal, not a delivered capability.
