# AAIG Deploy MCP Server — Proof of Concept

A Model Context Protocol (MCP) server that exposes the AAIG framework deploy as
MCP tools, so an agent can inspect, preview **and apply** a rollout **without
cloning the AAIG repository next to the target project**.

> PoC for the design in
> [`../ideas/mcp-deploy-server.md`](../ideas/mcp-deploy-server.md).
> **Phase 0** (read-only status/dry-run), **Phase 1** (guarded write path) and
> **Phase 2** (`[vscode]` file coverage) are implemented. Write tools require
> `confirm=true` (a production server would use MCP *elicitation*); all writes
> stay under the target `.github/` or `.vscode/`, back up before overwrite, and
> never touch CONFLICT / PROTECT / PRESERVE / `[customizable]` files.

> **Status: experimental — runs in parallel to `deploy.ps1` / `deploy.sh` for
> now, not yet a replacement.** The scripts remain the supported, CI-integrated
> path while this path matures; the server is opt-in and does not deprecate them.
>
> The MCP path is *designed to eventually supersede* the script-based deploy: it
> delivers the full payload by writing the `.github/` / `.vscode/` files to disk,
> exactly like the scripts, so the AAIG repo need not sit next to the target.
> What MCP does **not** change: VS Code still consumes agents / instructions /
> prompts / skills as files on disk — MCP *delivers* those files, it does not turn
> them into MCP-native primitives (and it need not). Remaining blockers before it
> can retire the scripts: cross-platform hardening (Windows has no MCP filesystem
> sandbox), packaged payload distribution, and the fact that a *remote-hosted*
> server still needs a local component to write to disk (run stdio locally, pull
> the payload from a bundled/remote source).

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
| Prompt | `af_deploy(workspace_root)` | Slash-command workflow: status → dry-run → conflict routing → guarded apply. |
| Prompt | `af_resolve_conflicts(workspace_root)` | Slash-command workflow: diff → merge → write → re-baseline for CONFLICT files. |

Write tools (**W**) do nothing unless `confirm=true`; otherwise they return a
preview. Classification and hashing (SHA-256 uppercase; agent **model-tier
resolution**) mirror `deploy.ps1`, so `af_dry_run`/`af_apply` agree with it.

The two **prompts** surface as `/mcp.aaig-deploy.af-deploy` and
`/mcp.aaig-deploy.af-resolve-conflicts` slash commands. They inject a step-by-step
instruction that drives the tools in the right order and pauses for a human
confirmation before any write — this is the “agent handles the non-programmatic
aspects” entry point (tier choice, conflict merges, skill activation).

## Run it

```bash
pip install -e ".[dev]"        # or: uv pip install -e ".[dev]"
aaig-deploy-mcp                # stdio server
```

The framework **payload** is resolved in this order:

1. `AF_SOURCE_ROOT` env var, if set (dev / tests / explicit override);
2. a hash-pinned **remote payload** (`AF_PAYLOAD_URL` + `AF_PAYLOAD_SHA256`) —
   governance mode, see below;
3. a `payload/` directory **bundled inside the installed wheel** (see
   `force-include` in `pyproject.toml`) — this is what lets an installed server
   run **without an AAIG clone** next to the target project;
4. the in-repo flavor directory, when running from a source checkout (dev mode).

### Governance mode (remote payload)

An operator can pin every install to a centrally published payload without a
hosted compute server (no project data leaves the machine — the fetch is a
one-way, outbound download of the framework payload only):

| Env var | Meaning |
|---|---|
| `AF_PAYLOAD_URL` | `https://` (or `file://`) URL of a `.zip` / `.tar.gz` payload archive |
| `AF_PAYLOAD_SHA256` | expected SHA-256 (hex) of the archive — **mandatory** (unpinned URL is refused) |
| `AF_PAYLOAD_CACHE` | optional cache dir (default `~/.cache/aaig-deploy-mcp`) |

The archive is verified **before** extraction, extraction is path-traversal-safe
(zip-slip / tar-escape / links refused), and results are cached by hash so
integrity is inherent and re-fetch is skipped. Only `https`/`file` schemes are
allowed (no plain `http`).

Build a self-contained wheel (payload bundled, nothing extra committed to git):

```bash
python -m build --wheel        # produces dist/aaig_deploy_mcp-*.whl
```

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

No AAIG clone is required — VS Code launches the packaged server locally (stdio)
and the payload is read from the bundled wheel. For a zero-install run straight
from a published/registry build, point `command`/`args` at a runner, e.g.:

```jsonc
{ "servers": { "aaig-deploy": { "type": "stdio", "command": "uvx", "args": ["aaig-deploy-mcp"] } } }
```

(`uvx` / `pipx run` fetch and run the package on demand — the same local-process
model as other VS Code MCP servers; “remote” only ever refers to *where the
package/payload is published*, never to where files are written.)

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
