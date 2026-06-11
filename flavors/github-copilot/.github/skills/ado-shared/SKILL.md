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

- Prefer clickable, verifiable URLs.
- Never fabricate links you cannot validate.
- Use `pending-sync` when remote references are not yet available.

## Gate Reminder

A capability run is incomplete unless it reports:

- probe result
- required/optional decision path
- execution mode (`platform` or `fallback`)
