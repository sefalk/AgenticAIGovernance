---
title: Hooks & Autonomy
type: concept
description: The deterministic enforcement hooks and the three-tier terminal autonomy classifier.
tags: [aaig, flavor, hooks, config]
updated: 2026-07-03
sources: [flavors/github-copilot/.github/hooks, flavors/github-copilot/.github/af-env.conf]
---
<!-- copilot:generated | documenter | 2026-07-03 -->

# Hooks & Autonomy

Hooks are the flavor's **deterministic enforcement layer**: real shell scripts
(PowerShell `.ps1` + bash `.sh`, cross-platform parity) wired via
`hooks/agent-hooks.json`. They turn AAIG principles from suggestions into
**code that runs**, satisfying [Verifiability](03-core-principles.md) and
[Safety](03-core-principles.md).

## Hook categories

| Hook (script) | Role |
|---|---|
| `block-dangerous` | Classifies every terminal command → allow / ask / deny (see below) |
| `scan-secrets` | Blocks commits/writes containing credential patterns |
| `session-context` | Injects project context at session start |
| `session-mcp-readiness` | Probes optional MCP/ADO capability availability |
| `stop-tests` | Runs the test suite at phase-stop gates |
| `{agent}-pretooluse` / `{agent}-stop` | Per-agent phase gates (test-writer, implementer, refactorer, researcher, documenter, coordinator) |
| `coordinator-postmerge` / `-posttooluse` | Post-action bookkeeping for the coordinator |

Per-agent hooks enforce phase discipline — e.g. the refactorer-stop hook runs
the linter as a HARD gate; the test-writer hooks verify new tests **fail** for
the right reason before handoff.

## The three-tier autonomy classifier

`block-dangerous` classifies each terminal command into one of three tiers:

| Tier | Meaning |
|---|---|
| **allow** | Auto-approved — runs with no prompt (safe / no durable change) |
| **ask** | Prompts the human for confirmation |
| **deny** | Hard-blocked — destructive/irreversible; **deny always wins** |

Classification is **segment-based**: a compound command is auto-approved only if
*every* segment (split on `;`, `&&`, `||`, `|`, newline) is individually safe.
Git handling is **branch-aware** — feature-branch work auto-approves while
pushes/merges to protected branches are denied.

**Always hard-denied** (run these yourself, outside the agent): force push, push
to a protected branch, `reset --hard`, `rebase`, force/protected branch deletion
(`-D`), `git add .` / `-A`, `--no-verify`, broad `rm -rf`, `dd`/`mkfs`/format,
`chmod 777`, pipe-to-shell (`| bash`/`iex`), `DROP`/`TRUNCATE`.

## Autonomy configuration

Behavior is tuned in [`af-env.conf`](13-configuration.md):

- **`AUTONOMY_LEVEL`** = `conservative` | `balanced` (default) | `autonomous`
  sets the per-category default tier.
- **`AUTONOMY_CAT_*`** overrides a single category: `GIT_READ`, `GIT_FEATURE`,
  `GIT_MERGE`, `TESTS`, `FS_READ`, `PKG_INSTALL`, `DATABRICKS`, `CLOUD_READ`.
- **`PROTECTED_BRANCHES`** (default `main,master,dev`) — never pushed/merged to
  directly.
- **`WEB_FETCH_ALLOWLIST`** — domains the researcher may fetch without a prompt.

The classifier enforces this boundary **independently of agent instructions** —
a safety net that holds even if an agent is prompted otherwise.

## See also

- [Agent Team](10-agents.md) · [Configuration](13-configuration.md) · [Core Principles (L1)](03-core-principles.md)
