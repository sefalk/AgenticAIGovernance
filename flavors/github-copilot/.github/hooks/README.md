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

#### PreToolUse: Dangerous Command Safety Gate

**Scripts:** `scripts/block-dangerous.ps1` (Windows) / `scripts/block-dangerous.sh` (Unix)

Intercepts terminal commands and **prompts for user confirmation** when a
command matches a destructive pattern. Does **not** block outright — lets
the user approve if the action is intentional.

**Patterns caught:**

| Pattern | Example |
|---|---|
| `rm -rf` | `rm -rf /important-data` |
| `Remove-Item -Recurse` | `Remove-Item C:\ -Recurse -Force` |
| `DROP TABLE/DATABASE` | `DROP TABLE production.users` |
| `TRUNCATE TABLE` | `TRUNCATE TABLE logs` |
| `git push --force` | `git push origin main --force` |
| `git reset --hard` | `git reset --hard HEAD~5` |
| `--no-verify` | `git commit --no-verify` |
| `chmod -R 777` | `chmod -R 777 /var/www` |
| `mkfs.` / `dd` / `format` | Disk formatting commands |

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
