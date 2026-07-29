---
title: Hooks & Autonomy
type: concept
description: The deterministic enforcement hooks and the three-tier terminal autonomy classifier.
tags: [aaig, flavor, hooks, config]
updated: 2026-07-29
sources: [flavors/github-copilot/.github/hooks, flavors/github-copilot/.github/af-env.conf]
---

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
| `test-writer-pretooluse` / `-stop` | Red-phase discipline — new tests must FAIL for the right reason before handoff |
| `implementer-stop` | Green-phase exit gates (tests, types, ignore-justification) |
| `refactorer-pretooluse` / `-stop` | No new files; linter as a HARD gate |
| `researcher-pretooluse` | Web-fetch allowlist enforcement |
| `documenter-stop` | Plan status, workflow log, retro snippet present |
| `coordinator-pretooluse` / `-posttooluse` / `-postmerge` | Branch/commit-message validation and post-action bookkeeping |

Hooks ship as **PowerShell `.ps1` + bash `.sh` pairs** with cross-platform
parity, wired via `hooks/agent-hooks.json`.

### Real git hooks (not agent hooks)

One guard is a *real git hook*, so it enforces whether a human or an agent runs
the commit:

| Path | Role |
|---|---|
| `hooks/git/pre-commit` + `hooks/scripts/check-large-files.py` | **Large-file commit guard** — blocks any staged blob over [`LARGE_FILE_MAX_BYTES`](13-configuration.md) (default 1 MB). Measures the staged index blob, not the working tree. Override per commit with `ALLOW_LARGE_FILES=1`; exempt paths via `LARGE_FILE_ALLOWLIST`; prefer **Git LFS** for genuinely large assets. |

It is wired by `git config core.hooksPath .github/hooks/git`, done automatically
by the bootstrap script. Existing clones must re-run bootstrap once —
`core.hooksPath` is not retroactive.

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
  `GIT_MERGE`, `TESTS`, `FS_READ`, `FS_WRITE`, `PKG_INSTALL`, `DATABRICKS`,
  `CLOUD_READ`.
- **`PROTECTED_BRANCHES`** (default `main,master,dev`) — never pushed/merged to
  directly.
- **`WEB_FETCH_ALLOWLIST`** — domains the researcher may fetch without a prompt.

The classifier enforces this boundary **independently of agent instructions** —
a safety net that holds even if an agent is prompted otherwise.

## See also

- [Agent Team](10-agents.md) · [Configuration](13-configuration.md) · [Core Principles (L1)](03-core-principles.md)
