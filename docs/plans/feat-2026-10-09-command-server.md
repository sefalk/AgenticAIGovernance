# Implementation Plan

<!-- copilot:generated | coordinator | 2026-10-19 -->

**Workflow:** Feature Development
**Branch:** `agent/60-command-server`
**Status:** IN_PROGRESS
**AF Version:** 1.24.37

## Context

Agents need to run reviewed scripts **and** scripts they write themselves, with arguments, without a prompt per call and without `tasks.json` churn (#396: MP holds 228 tasks, 197 agent-minted; `createAndRunTask` hard-codes `allowAutoConfirm: false`). This plan adds a local stdio MCP server, `af-command-mcp`, as a second console script of the existing `af-deploy-mcp` wheel.

> The coordinator wrote this plan itself, with the owner's permission. In the MP+AF multi-root window, the MP-deployed `planner-pretooluse` confines the planner to the MP repo, which is correct for MP.

> Walltime is an **upper bound, never a duration**: the call returns when the process exits. Measured 2026-10-09: VS Code imposes no client timeout up to 1800 s silent, so synchronous calls suffice.

## References

- #60 decision comments of 2026-10-09: timeout measurement, owner decisions on agent scripts, pre-absence decisions.
- #396 decision comment 6078513527; PR #398 (duplicate-task deny, `prune-tasks.py`).
- `mcp-deploy/af_deploy_mcp/server.py` (mcp SDK 2.2.0, `MCPServer`).

## Scope Assessment

- **Files affected:** about 14
  - **New:** `command_core.py`, `command_trust.py`, `command_server.py`, three test modules, `.github/scripts/agent/README.md`.
  - **Changed:** `pyproject.toml`, `af-env.conf`, `block-dangerous.ps1`/`.sh` (trust-store guard), `test-hooks.ps1`/`.sh`, four agent files, `mcp-deploy/README.md`, CHANGELOG.
- **Layers touched:**
  - Domain core: walltime resolution, mode resolution, config parse.
  - Adapters: subprocess, git, trust-store file, MCP transport.
- **Complexity tier:** Deep
- **Estimated size:** medium (4 subtasks)
- **Not in scope:**
  - Per-script argument schemas. v1 passes args as an argv list with no shell.
  - Sandboxing (not available on Windows).
  - Removing `createAndRunTask` or `runTask`.
  - Live end-to-end start: this needs an owner trust click.
- **Risks:**
  - **Self-approval.** An agent could write to the trust store. The store lives outside the workspace and a hook denies edit tools on it. A terminal write remains a residual.
  - **Bypass via `reviewed` mode.** An agent could commit a script under `.github/scripts` so that it reads as `reviewed`. Residual: PR review before `dev`.
  - **Content scan misses obfuscated code.** The scan is defence in depth; the approval mode is the gate.
  - **Elicitation unmeasured.** `ask` modes fail closed.
  - **Orphaned grandchildren on Windows.** Use `taskkill /T /F`, proven by a grandchild test.
- **Rollback plan:** The server is opt-in through the user `mcp.json`. Revert the PR; no data migration.

## Subtasks

### 1. Core runner

- **Action:** `command_core.py` provides:
  - config parse: `AF_SCRIPT_DIRS` with `dir:mode`, `AF_SCRIPT_APPROVAL`, `AF_SCRIPT_WALLTIME_DEFAULT=600`, `AF_SCRIPT_WALLTIME_MAX=3600`, and the implicit `AF_TASK_SCRIPT_DIRS` folder in mode `reviewed`;
  - path resolution: real path, containment, deepest folder wins;
  - interpreter by extension: `.ps1` with `powershell -NoProfile -ExecutionPolicy Bypass -File` (`pwsh` off Windows), `.py` with the project venv or else `sys.executable`, `.sh` with `bash`;
  - walltime resolution: explicit value capped at max; else max of the last 5 PASS durations × 2 with a 30 s floor; else the `suite-budgets.json` entry; else the default;
  - the run itself: tree kill on timeout, full log under `.github/logs/command-runs/`, a tail of 60 lines / 6000 chars, and one JSONL run log line.
- **Files:** `mcp-deploy/af_deploy_mcp/command_core.py`, `mcp-deploy/tests/test_command_core.py`
- **Layer:** Domain Core + Adapter (subprocess)
- **Acceptance criteria:**
  - A script that exits after 0 s returns PASS in under 5 s with a 600 s walltime.
  - A script sleeping 60 s with `walltime_s=2` returns TIMEOUT within 10 s; its grandchild is dead.
  - Exit code ≠ 0 gives FAIL; the tail and log path are present.
  - `..` escape, a path outside every folder, and an unknown extension each give REFUSED, and nothing runs.
  - The history of PASS runs sets the next default walltime; an explicit value above max is capped and the source is reported.
- **Exit criterion:** `test_command_core.py` green on Windows.
- **Tests needed:** pytest with real subprocesses on tiny `.py` fixtures (portable); `.ps1` interpreter case on Windows only.
- **Dependencies:** none
- **Status:** DONE

### 2. Approval and trust

- **Action:** `command_trust.py` provides:
  - mode resolution per path: `off`, `reviewed`, `ask`, `ask-always`, `autonomous`. `reviewed` runs only if the file is tracked and byte-equal to `HEAD`; otherwise it falls back to `AF_SCRIPT_APPROVAL`.
  - a trust store at `%LOCALAPPDATA%\af-command-mcp\trust\<sha256(repo)>.json`, or under XDG state elsewhere;
  - a content scan through the project's `block-dangerous` hook, fed a synthetic `run_in_terminal` payload, with the verdict cached per hash; a missing hook means refuse;
  - an elicitation callback that fails closed.
- **Files:** `command_trust.py`, `tests/test_command_trust.py`
- **Layer:** Domain Core (mode logic) + Adapter (git, store, hook)
- **Acceptance criteria:**
  - Each mode is tested against a new, an accepted and an edited hash.
  - A declined or unavailable elicitation gives REFUSED with the reason.
  - A hook `deny` refuses even in `autonomous`.
  - `reviewed` with a dirty or untracked file falls back.
  - The store path lies outside `workspace_root`.
- **Exit criterion:** `test_command_trust.py` green.
- **Tests needed:** pytest. The hook is a fixture script printing allow/deny JSON. Git uses a temp repo. The store root is injected.
- **Dependencies:** 1
- **Status:** DONE

### 3. MCP server

- **Action:** `command_server.py` with the tools `run_script(workspace_root, path, args, walltime_s)` (no annotations) and `list_scripts(workspace_root)` (`readOnlyHint`).
  - It is wired to `ctx.elicit` and `ctx.report_progress` (every 15 s).
  - Console script `af-command-mcp` in `pyproject.toml`.
- **Files:** `command_server.py`, `pyproject.toml`, `tests/test_command_server.py`
- **Layer:** Adapter (transport)
- **Acceptance criteria:**
  - In-process `call_tool` returns the documented shape: `verdict`, `exit_code`, `duration_s`, `walltime_s`, `walltime_source`, `tail`, `log_path`, `reason`.
  - `list_scripts` lists each folder with its mode.
  - The entry point resolves.
- **Exit criterion:** `test_command_server.py` green; full mcp-deploy suite green.
- **Tests needed:** pytest with in-process tool calls.
- **Dependencies:** 1, 2
- **Status:** DONE

### 4. Configuration, guard, grants, docs

- **Action:**
  - Add the new keys to `af-env.conf`.
  - Add `.github/scripts/agent/README.md`.
  - Add a trust-store edit deny in `block-dangerous` (both dialects, with tests).
  - Grant the tool to the coordinator, test-writer, implementer and refactorer.
  - Add the `mcp-deploy/README` registration snippet and a CHANGELOG entry.
- **Files:** as listed in the Scope Assessment.
- **Layer:** Adapter (hooks, config), docs
- **Acceptance criteria:**
  - `test-hooks.ps1` and `.sh` deny an edit tool targeting the store directory and allow a control path.
  - Context budgets, `check-cli-callers` and `run-all-tests -Changed` are green.
- **Exit criterion:** All suites green; PR open.
- **Tests needed:** cases in `test-hooks.ps1` and `test-hooks.sh`.
- **Dependencies:** 3
- **Status:** DONE

## Implementation Sequence

1. Core runner → Approval and trust → MCP server → Configuration, guard, grants, docs

## Quality Gates

| Gate | Target | Type |
|---|---|---|
| Line coverage | `command_core`/`command_trust` ≥ 90%, `command_server` ≥ 60% | HARD |
| No shell string construction | `subprocess` with argv lists only, `shell=False` | HARD |
| Hook suites | `test-hooks.ps1`/`.sh` 0 failures | HARD |
| Architecture compliance | mode and walltime logic free of I/O | SOFT |

- **Suggested workflow:** Full TDD
- **Skills consulted:** secure-coding, python-dev, test-execution

## Plan Approval

**Approved by:** human (owner decisions on #60, 2026-10-09)
**Verdict:** APPROVED-WITH-FINDINGS

### Open Findings

- Live check after the owner's return: register the server, run `list_scripts` and `run_script`, and measure the elicitation prompt in `ask` mode.
- Owner to decide whether per-script argument schemas use a header block or a manifest.
- Owner to decide whether `createAndRunTask` is denied for agents once the server is live.

## Change Log

| Date | Agent | Change |
|---|---|---|
| 2026-10-19 | coordinator | Initial plan created (template format) |
| 2026-10-19 | coordinator | Subtasks 1-3 done: core 94%, trust 92%, server 89% coverage; full mcp-deploy suite 207 passed |
| 2026-10-19 | coordinator | Subtask 4 done: trust-store guard in both dialects, config keys, grants, docs |
