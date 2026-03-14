# Agent Hooks

> **Status:** Preview feature (VS Code 1.106+)
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

Four hooks are **active** out of the box:

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
