**Version: 1.1 | Date: 2026-06-25**
**Level: 3 | Domain: Cross-Domain Integration**
**Derived from:** [L1_Core_Principles.md](../L1_Core_Principles.md), [L1_Framework_Architecture.md](../L1_Framework_Architecture.md)

---

# Level 3 — Platform Capability Integration Workflow

## Operationalizes

- L1 Platform Optionality & Graceful Degradation
- L1 Identity & Least Privilege
- L1 Fail-Safe & Ask First
- L1 Transparency/Traceability

## Purpose

This workflow standardizes integration of external platform capabilities
(for example issue tracking, wiki lifecycle, artifact services, CI control
planes) in a provider-agnostic, auditable way.

## Entry Criteria

1. A task requires interaction with an external platform capability.
2. Level-4 contract defines capability classification (`required` or `optional`).
3. The primary workflow has identified a capability worker or equivalent role.

## Phase 1 — Resolve Capability Contract

### Actions

1. Identify `provider`, `capability`, and operation intent.
2. Read L4 capability contract values:
   - required/optional
   - availability probe command
   - fallback strategy
3. Verify least-privilege scope for credentials/tools.

### Exit Criteria

- Capability contract is explicit and logged.

## Phase 2 — Probe Availability

### Actions

1. Execute the configured probe.
2. Capture status as one of:
   - `READY`
   - `DEGRADED`
   - `BLOCKED`

### Decision

- If capability is **required** and probe != READY: halt and escalate.
- If capability is **optional** and probe != READY: continue with fallback path.

### Exit Criteria

- Probe result and decision path are recorded.

## Phase 3 — Execute Integration or Fallback

### Actions (READY)

1. Execute capability operation.
2. Validate operation result.
3. Emit traceable reference (URL/id/path) when available.

### Actions (DEGRADED optional path)

1. Produce fallback artifact (local log/page/queue item).
2. Mark operation as deferred synchronization.
3. Emit explicit `pending-sync` marker.

### Exit Criteria

- Either platform operation completed or fallback artifact recorded.

## Phase 4 — Verify & Log

### Actions

1. Run configured quality gates for this capability.
2. Record outputs in workflow log:
   - probe outcome
   - execution mode (platform/fallback)
   - references and deferred items

### Exit Criteria

- Quality gates passed or escalated with actionable context.

## Minimal Quality Gates

| Gate | Type | Condition |
|---|---|---|
| Availability probe executed | HARD | Probe result recorded |
| Required capability unavailable => halt | HARD | Escalation performed |
| Optional capability unavailable => fallback used | HARD | Fallback artifact exists |
| Least-privilege credentials confirmed | SOFT | Reviewer confirms scope |
| Traceability record complete | HARD | Log includes references or pending-sync marker |

## Specialization — Pull / Merge Request Integration

Request-based integration (pull/merge requests) is a specialization of this
workflow for the **code integration** capability. It is **optional**: the
default is the pure-git path (local commits; push and merge human-controlled).
When a project enables a request provider, the following applies.

### Path Selection

- **Pure git (default):** no request provider configured; the orchestrator
  commits locally and push/merge stay human-controlled. No integration
  worker runs.
- **Request-based (optional):** a provider capability is enabled; the
  orchestrator publishes the feature branch and an integration worker manages
  the request.

### Branch-Scoped Completion Policy

| Target branch class | Mode | Completion |
|---|---|---|
| Integration branch | Autonomous | Worker may set auto-complete; platform merges once policies pass |
| Protected/release branch | Human-only | Worker creates/updates only; human completes |
| Unresolved / other | Safe default | Treated as human-only |

### Responsibility Split

- The **orchestrator** owns local git including the single push of the
  feature branch from the active work location; never pushes protected
  branches and never force-pushes.
- The **integration worker** has no terminal/git access; it verifies the
  branch is published, then manages the request through the provider API.

### Provider Neutrality

The contract is provider-agnostic. The first concrete provider is Azure
DevOps (an `ado-pr-manager` worker). GitHub pull requests and GitLab merge
requests can implement the same contract through analogous workers without
changing this workflow.

> **Known limitation:** only the Azure DevOps worker exists today. GitHub and
> GitLab workers are contract-compatible but **not yet implemented** —
> provider neutrality is a design goal, not a delivered capability.

See the `pr_integration_management` skill for the detailed behavior contract.
