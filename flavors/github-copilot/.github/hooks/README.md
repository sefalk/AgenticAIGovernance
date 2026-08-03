# Agent Hooks

> **Status:** Transitioning to per-agent frontmatter hooks (v1.18.4+)
>
> **Global `.json` hooks:** Currently orphaned — VS Code agent hooks are a
> preview feature and JSON loading is not yet fully implemented. We recommend
> defining hooks in agent frontmatter instead (per-agent `.agent.md` files).
> The `.json` files are maintained as legacy fallbacks for future use.
>
> Hooks execute deterministic shell commands at lifecycle points during agent
> sessions. Unlike instructions that _guide_ behaviour, hooks _enforce_ it
> with code.

## Real Git Hooks vs. Agent Hooks

Everything below this section describes **agent hooks** — they only fire
during an active VS Code Copilot agent session (preview, JSON loading not
yet fully implemented; see status note above).

For enforcement that must hold regardless of *who* runs `git commit` (agent
via terminal, or a human), the framework also ships a **real git hook**,
wired via `core.hooksPath`:

- **`.github/hooks/git/pre-commit`** — a POSIX shell shim, invoked directly by
  git on every commit (Git for Windows runs it via its bundled `sh`, so it
  works on Windows without a `.ps1` equivalent). It calls
  `.github/hooks/scripts/check-large-files.py` to reject staged files above
  `LARGE_FILE_MAX_BYTES` (see `.github/af-env.conf` — the large-file commit
  guard). See [git-workflow SKILL.md](../skills/git-workflow/SKILL.md) § 7
  for the threshold/override/allowlist design.
- Enabled per clone by `git config core.hooksPath .github/hooks/git` — done
  automatically by `scripts/bootstrap-python-env.ps1` / `.sh`. **Existing
  clones must re-run bootstrap (or run the `git config` command manually)**
  to pick up the guard.
- The shim lives under `hooks/git/` (not `hooks/scripts/`) so it deploys with
  the rest of `.github/` via the existing manifest `hooks/` entry, while
  staying clearly separate from the agent-session hooks in this folder. Add
  future real (commit-time) checks as scripts invoked from `hooks/git/pre-commit`.

## How Hooks Work

Hooks are configured in `.json` files in this folder. VS Code loads all
`*.json` files from `.github/hooks/` automatically.

Each hook:

1. Fires at a specific **lifecycle event** (see table below)
2. Receives structured **JSON input** via stdin
3. Returns **JSON output** via stdout to control agent behaviour
4. Uses **exit codes** to signal success (0), blocking error (2), or warning (other)

## Lifecycle Events

| Event | When It Fires | Use Cases |
|---|---|---|
| `SessionStart` | New agent session begins | Inject project context, log session |
| `UserPromptSubmit` | User submits a prompt | Audit requests, inject context |
| `PreToolUse` | Before agent invokes any tool | Block dangerous ops, require approval |
| `PostToolUse` | After tool completes | Auto-format, run linters, log results |
| `PreCompact` | Before context is compacted | Save state before truncation |
| `SubagentStart` | Subagent is spawned | Track subagent usage |
| `SubagentStop` | Subagent completes | Aggregate results, cleanup |
| `Stop` | Agent session ends | Enforce test runs, generate reports |

## Configuration Format

**Recommended:** Define hooks in agent frontmatter (`.agent.md` files) for
per-agent enforcement. Example:

```yaml
hooks:
  PreToolUse:
    - type: command
      command: 'bash .github/hooks/scripts/my-hook.sh'
      windows: 'powershell -ExecutionPolicy Bypass -File .github\hooks\scripts\my-hook.ps1'
```

**Legacy:** JSON format (not currently auto-loaded by VS Code):

```json
{
  "hooks": {
    "EventName": [
      {
        "type": "command",
        "command": "./scripts/my-hook.sh",
        "windows": "powershell -File scripts\\my-hook.ps1",
        "timeout": 15
      }
    ]
  }
}
```

### Command Properties

| Property | Type | Description |
|---|---|---|
| `type` | string | Must be `"command"` |
| `command` | string | Default command (cross-platform) |
| `windows` | string | Windows-specific override |
| `linux` | string | Linux-specific override |
| `osx` | string | macOS-specific override |
| `cwd` | string | Working directory (relative to repo root) |
| `env` | object | Additional environment variables |
| `timeout` | number | Seconds before timeout (default: 30) |

## Output Format

All hooks can return JSON via stdout:

```json
{
  "continue": true,
  "stopReason": "Reason for stopping (when continue=false)",
  "systemMessage": "Warning displayed to user"
}
```

### PreToolUse-Specific Output

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow | deny | ask",
    "permissionDecisionReason": "Why",
    "additionalContext": "Extra context for the model"
  }
}
```

### Stop-Specific Output

```json
{
  "hookSpecificOutput": {
    "hookEventName": "Stop",
    "decision": "block",
    "reason": "Run the test suite before finishing"
  }
}
```

## Included Hooks

### `agent-hooks.json` — Active Hooks (ready to use)

Five hooks are **active** out of the box:

#### SessionStart: Session Context Injection

**Scripts:** `scripts/session-context.ps1` (Windows) / `scripts/session-context.sh` (Unix)

Automatically injects project context into every agent session:

```
Project: my-app | Branch: feat/new-widget | Last commit: a1b2c3d Add widget | Python 3.11.5
```

The agent receives this as `additionalContext`, giving it awareness of the
current git state without needing to be told.

**What it gathers:**
- Git branch name
- Last commit hash + message
- Python version
- Project directory name

#### SessionStart: ADO MCP Readiness

**Scripts:** `scripts/session-mcp-readiness.ps1` (Windows) / `scripts/session-mcp-readiness.sh` (Unix)

Checks whether Azure DevOps provider capabilities are ready for use.
The hook reports `READY`, `DEGRADED`, or `BLOCKED` based on
`ADO_CAPABILITY_MODE` and the presence of required defaults in
`.github/af-env.conf`.

**What it checks:**
- `ADO_CAPABILITY_MODE`
- `ADO_PROJECT` availability
- Optional wiki/linking hints such as `ADO_WIKI_IDENTIFIER`, `ADO_REPOSITORY_ID`, and `ADO_REPOSITORY_NAME`
- ADO agent naming guardrail (`ado-` prefix)

#### PreToolUse: Terminal Command Autonomy Classifier

**Scripts:** `scripts/block-dangerous.ps1` (Windows) / `scripts/block-dangerous.sh` (Unix)

Classifies every terminal command into one of three tiers to reduce approval
friction while keeping destructive actions blocked:

| Tier | Decision | Behaviour |
|---|---|---|
| **deny** | `permissionDecision=deny` | Hard-blocked outright + agent notice on how to override. |
| **allow** | `permissionDecision=allow` | Auto-approved (no prompt). Gated by autonomy config. |
| **ask** | `permissionDecision=ask` | Prompts for confirmation (durable change). |
| _default_ | `{}` | Defers to the user's VS Code approval settings. |

**Configuration** lives in `.github/af-env.conf`:

- `AUTONOMY_LEVEL` — `conservative` \| `balanced` (default) \| `autonomous`.
  Sets category defaults.
- `AUTONOMY_CAT_*` — per-category overrides (`auto` \| `ask` \| `deny`) that
  win over the level default. Categories: `GIT_READ`, `GIT_FEATURE`,
  `GIT_MERGE`, `TESTS`, `FS_READ`, `PKG_INSTALL`, `DATABRICKS`, `CLOUD_READ`.
- `PROTECTED_BRANCHES` — branches that may never be pushed to / merged into
  directly (default `main,master,dev`). Feature-branch (`agent/*`) git ops
  are branch-aware and auto-approve; protected-branch pushes hard-deny.

**Level → category defaults:**

| Category | conservative | balanced | autonomous |
|---|---|---|---|
| Git read (`status`/`diff`/`log`/…) | auto | auto | auto |
| Filesystem read (`ls`/`cat`/`grep`/…) | auto | auto | auto |
| Tests/lint (`pytest`/`ruff check`/`mypy`) | ask | auto | auto |
| Git feature branch (`commit`/`add <files>`/push `agent/*`/`branch -d` merged) | ask | auto | auto |
| Reversible git (`pull`/`merge`/`cherry-pick`/`revert`) | ask | auto | auto |
| Package install (`pip`/`conda install`) | ask | ask | **auto** |
| Databricks CLI (mutating) | ask | ask | ask |
| Cloud read (`databricks list/get`, `az show/list`) | ask | **auto** | **auto** |

**deny tier (level-independent):** force push, push to a protected branch,
`git reset --hard`, `git rebase`, **force** branch deletion (`-D`/`--force`)
and deleting a protected branch, `git add .`/`-A`/`--force`, `--no-verify`,
broad `rm -rf`, recursive force delete, `dd`/`mkfs`/drive format,
`chmod -R 777`, pipe-to-shell (`| bash`/`| iex`), `DROP`/`TRUNCATE`.
When a command is denied, the agent will not run it — it can instead prepare
the exact command for you to paste and run yourself, or you can relax the
relevant `AUTONOMY_CAT_*` setting.

**ask tier:** `git tag <name>` (create), `pip install/uninstall` (unless
`pkg=auto`), `ruff format` (writes), mutating `databricks`/`az`, single-file
`Remove-Item`/`rm`, `mv`/`cp`/`mkdir`. (`git merge`/`pull`, `git switch`, and
`git branch -d` of a merged non-protected branch auto-approve at `balanced`.)

**Segment-based auto-allow:** the command is split on `;`, `&&`, `||`, `|`,
and newlines, and auto-approved only when **every** segment is individually
safe. This lets common composites through — e.g. `cd … ; pytest … 2>&1 |
Select-Object -Last 30` — while still refusing anything with an unknown or
mutating segment (`pytest ; ./deploy.sh` → prompt). `2>&1`-style fd
duplication is treated as safe; file-write redirects (`> file`, `>> file`),
background/inline `&`, command substitution (`$(…)`), backticks, and grouping
/ subshell / scriptblock metacharacters **outside quotes** (`(…)`, `{…}`) are
never auto-allowed — because `Write-Host (Remove-Item x)` or bash `(rm x)`
would execute the inner command. Quotes are stripped before that check, so
conventional-commit messages like `"fix(scope): …"` still auto-allow.

Read-only helpers that also auto-allow: `pip list/show/freeze/check`,
`whoami`, `hostname`, `Get-Date`, `Get-Process`, `Get-Service`, switching
to an existing `agent/*` branch (`git checkout agent/…`), and — from the
`balanced` level — read-only cloud calls (`databricks <group> list/get`,
`az … show/list`). Cloud reads that touch secrets/credentials/tokens
(`az keyvault secret show`, `databricks secrets get`, `az … get-access-token`)
are **excluded** and still prompt, so credentials are never auto-printed.

**Fail-safe:** DENY is scanned across the whole command string first, so a
hidden dangerous segment (`… ; rm -rf /`, `Write-Host (git push --force)`) is
blocked even inside a composite. On any parse ambiguity the hook returns `{}`
(prompt) — it never accidentally auto-approves.

#### PostToolUse: Secret Detection Scan

**Scripts:** `scripts/scan-secrets.ps1` (Windows) / `scripts/scan-secrets.sh` (Unix)

Scans files after file-editor tool calls for hardcoded secrets. Uses
**gitleaks** if installed, otherwise falls back to regex pattern matching.

**Blocking** — exits with code 1 when secrets are detected (HARD gate).
Previously advisory-only; hardened in v1.7.1 per governance audit finding G-07.

**Patterns detected (regex fallback):**

| Pattern | Example |
|---|---|
| AWS Access Key | `AKIA...` (20-char key) |
| Generic Secret | `password = "mysecret123"` |
| Private Key | `-----BEGIN RSA PRIVATE KEY-----` |
| Connection String | `Server=...;Password=...` |

#### Stop: Test Suite Gate

**Scripts:** `scripts/stop-tests.ps1` (Windows) / `scripts/stop-tests.sh` (Unix)

Runs `pytest tests/ -q --tb=line` when the agent session ends. Provides a
pass/fail gate with summary output.

**Graceful fallback:** If pytest is not installed or `tests/` doesn't exist,
reports "skipped" instead of failing.

### `quality-gates.json.template` — Example Hooks (reference)

Template showing example hook patterns. The PostToolUse and Stop hooks are
now active in `agent-hooks.json` with real implementations. Keep this file
as a reference for additional hook customisation.

## Security

- Hooks execute with the same permissions as VS Code — review scripts carefully
- Never hardcode secrets; use environment variables
- Validate all input from stdin to prevent injection
- Use `chat.tools.edits.autoApprove` to prevent agents editing hook scripts

## Managing Hooks

- `/hooks` in chat → interactive configuration UI
- `/create-hook` in chat → AI-generated hook from description
- Command Palette → `Chat: Configure Hooks`

## Related

- [Official hooks docs](https://code.visualstudio.com/docs/copilot/customization/hooks)
- [Agent Team Manifest](../MANIFEST.md) — §9 Agent Hooks
