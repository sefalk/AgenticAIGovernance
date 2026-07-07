# AAIG Deploy MCP Server — Proof of Concept

A **read-only** Model Context Protocol (MCP) server that exposes the AAIG
framework deploy as MCP tools, so an agent can inspect and preview a rollout
**without cloning the AAIG repository next to the target project**.

> This is a PoC for the design in
> [`../ideas/mcp-deploy-server.md`](../ideas/mcp-deploy-server.md). It implements
> the two read-only tools (`af_status`, `af_dry_run`) and a source resource.
> The write path (`af_apply`, `af_write_resolved`, `af_update_hashes`) is
> **specified but intentionally not implemented here**.

## What it does

| Primitive | Name | Purpose |
|---|---|---|
| Tool | `af_status(workspace_root)` | Bundled framework version vs. the version deployed in the target repo (`up-to-date` / `stale` / `not-deployed`). |
| Tool | `af_dry_run(workspace_root)` | Classify every deployable file (`UPDATE` / `CONFLICT` / `PRESERVE` / `PROTECT` / `UNCHANGED` / `CREATE`) — the same 3-way decisions as `deploy.ps1`, computed read-only. |
| Resource | `af://source/{path}` | Read a bundled source file, e.g. `af://source/agents/planner.agent.md`. |

The classification and hashing (SHA-256 uppercase; agent **model-tier
resolution**) mirror `deploy.ps1`, so `af_dry_run` agrees with the script.

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

- **Read-only.** No writes to the target — ever.
- **`.github/` only.** `[vscode]` files are skipped (Phase-1 item).
- **Payload parity.** Tier resolution and hashing match `deploy.ps1`; keys are
  normalized to forward slashes so a baseline written by `.ps1` or `.sh`
  compares consistently.
- The full trust/security model (why the deploy's safety must live *in the
  server* once writes are added, and the Windows no-sandbox caveat) is in the
  [specification](../ideas/mcp-deploy-server.md).
