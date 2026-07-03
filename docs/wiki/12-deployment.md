---
title: Deployment & Versioning
type: ops-note
description: How the flavor is deployed and updated — deploy scripts, three-way merge, conflict handling, and versioning.
tags: [aaig, flavor, deploy, ops]
updated: 2026-07-03
sources: [flavors/github-copilot/deploy.ps1, flavors/github-copilot/README.md, flavors/github-copilot/.githooks/pre-commit]
---
<!-- copilot:generated | documenter | 2026-07-03 -->

# Deployment & Versioning

The flavor is deployed and updated with `deploy.ps1` (Windows) / `deploy.sh`
(macOS/Linux), which copy the framework's `.github/` package into a target repo
and reconcile updates with a **three-way merge**.

## Basic usage

```powershell
# Preview first (no changes), then apply
.\deploy.ps1 -TargetDir "<path-to-project>" -DryRun
.\deploy.ps1 -TargetDir "<path-to-project>"
```

The deploy classifies each file as **UPDATE** (framework file changed),
**PRESERVE** (project customization kept), **CONFLICT** (both sides changed), or
**UNCHANGED**, and prints a summary.

## Three-way merge & customization

Deploy tracks a baseline in `.github/.af-hashes` and a version marker in
`.github/.af-version`. Comparing *baseline vs framework-source vs deployed file*
yields the classification:

- **`[customizable]` files** (e.g. `af-env.conf`, `copilot-instructions.md`,
  `architecture.instructions.md`) are protected — never overwritten.
- **CONFLICT files are skipped**, never clobbered — the project copy is kept and
  flagged for a human/agent to merge.
- A timestamped **backup** (`.af-backup-*`) is written when conflicts occur;
  stale backups auto-prune after `BACKUP_PRUNE_DAYS` (default 14).

### Resolving conflicts

1. Decide per file: **take-framework** (adopt the new canonical version) or
   **keep-project** (an intentional local specialization).
2. Apply that decision to the file.
3. Re-baseline with `-UpdateHashes` so the resolved files stop flagging:
   ```powershell
   .\deploy.ps1 -TargetDir "<path>" -UpdateHashes
   ```
4. A final `-DryRun` should report `conflict: 0`.

## Versioning

The framework version lives in `flavors/github-copilot/VERSION` (semantic
versioning). An **auto-version pre-commit hook** (`.githooks/pre-commit`,
enabled via `git config core.hooksPath .githooks`) bumps the **patch** version
automatically whenever `flavors/github-copilot/**` or `core/**` is staged and
`VERSION` is not — so incidental changes are versioned without manual effort. A
deliberate release cut stages `VERSION` itself (minor/major), which makes the
hook skip.

## Code-wiki routing note

Per the `ado-wiki` skill and [`ADO_CODE_WIKI_PATH`](13-configuration.md),
repo-specific documentation (like *this wiki*) is versioned in the code at
`docs/wiki/` and reviewed with it, while general/project-wide notes go to the
Azure DevOps **project wiki**.

## See also

- [Flavor: GitHub Copilot](09-flavor-github-copilot.md) · [Configuration](13-configuration.md) · [Governance Change](14-governance-change.md)
