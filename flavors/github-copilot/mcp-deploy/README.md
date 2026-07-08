# AAIG Deploy MCP Server — Proof of Concept

A Model Context Protocol (MCP) server that exposes the AAIG framework deploy as
MCP tools, so an agent can inspect, preview **and apply** a rollout **without
cloning the AAIG repository next to the target project**.

> PoC for the design in
> [`../ideas/mcp-deploy-server.md`](../ideas/mcp-deploy-server.md).
> **Phase 0** (read-only status/dry-run) and **Phase 1** (guarded write path)
> are implemented. Write tools require `confirm=true` (a production server would
> use MCP *elicitation*); all writes stay under the target `.github/`, back up
> before overwrite, and never touch CONFLICT / PROTECT / PRESERVE /
> `[customizable]` files.

## What it does

| Primitive | Name | Purpose |
|---|---|---|
| Tool (R) | `af_status(workspace_root)` | Bundled framework version vs. the version deployed in the target repo. |
| Tool (R) | `af_dry_run(workspace_root)` | Classify every deployable file (3-way), read-only. |
| Tool (R) | `af_conflict_diff(workspace_root, path)` | Unified diff between a deployed file and the resolved source. |
| Tool (W) | `af_apply(workspace_root, confirm)` | Apply CREATE/UPDATE files; back up first; skip conflicts/customizable. |
| Tool (W) | `af_write_resolved(workspace_root, path, content, confirm)` | Write an agent-merged file (conflict resolution). |
| Tool (W) | `af_update_hashes(workspace_root, confirm)` | Re-baseline `.af-hashes` after resolving conflicts. |
| Tool (W) | `af_prune_backups(workspace_root, days, confirm)` | Remove stale `.af-backup-*` dirs. |
| Resource | `af://source/{path}` | Read a bundled source file, e.g. `af://source/agents/planner.agent.md`. |

Write tools (**W**) do nothing unless `confirm=true`; otherwise they return a
preview. Classification and hashing (SHA-256 uppercase; agent **model-tier
resolution**) mirror `deploy.ps1`, so `af_dry_run`/`af_apply` agree with it.

## Run it

```bash
pip install -e ".[dev]"        # or: uv pip install -e ".[dev]"
aaig-deploy-mcp                # stdio server
```

The framework payload is resolved from `AF_SOURCE_ROOT` if set, else the in-repo
flavor directory (dev mode). A packaged build bundles the payload as package
data (see the spec).

## Use in VS Code (`.vscode/mcp.json`)

```jsonc
{
  "servers": {
    "aaig-deploy": {
      "type": "stdio",
      "command": "aaig-deploy-mcp",
      // Windows note: MCP filesystem sandboxing is macOS/Linux only. On macOS/Linux
      // you can add "sandboxEnabled": true with a workspace-scoped allowWrite.
    }
  }
}
```

Then in chat: *"Use af_status for `${workspaceFolder}`"* and *"Run af_dry_run for
`${workspaceFolder}` and summarize the conflicts."* The agent passes the
workspace path; the server only reads.

## Test

```bash
pytest            # unit tests for the read-only deploy logic (no MCP needed)
```

## Scope & safety (PoC)

- **Guarded writes.** Write tools require `confirm=true`; all writes stay under
  the target `.github/` (or `.vscode/`); existing files are backed up before
  overwrite; CONFLICT / PROTECT / PRESERVE / `[customizable]` files are never
  written by `af_apply`. The terminal `block-dangerous` hook does **not** see MCP
  tool calls, so these guards *are* the safety boundary (see the spec).
- **Full payload.** Both the `.github/` tree and manifest `[vscode]` files
  (deployed to `.vscode/`) are covered.
- **Payload parity.** Tier resolution and hashing match `deploy.ps1`; keys are
  normalized to forward slashes so a baseline written by `.ps1` or `.sh`
  compares consistently.
- The full trust/security model (and the Windows no-sandbox caveat) is in the
  [specification](../ideas/mcp-deploy-server.md).
