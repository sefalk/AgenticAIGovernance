# Agent Hooks

> **Status:** Both hook sources run — the `.json` files in this folder and the
> `hooks:` frontmatter of individual agents. Measured, not assumed; the
> evidence is under [How Hooks Work](#how-hooks-work).
>
> Hooks execute deterministic shell commands at lifecycle points during agent
> sessions. Unlike instructions that _guide_ behaviour, hooks _enforce_ it
> with code.

## Real Git Hooks vs. Agent Hooks

Everything below this section describes **agent hooks** — they only fire
during an active VS Code Copilot agent session (a preview feature).

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

Hooks come from two places and **both** are loaded: the `.json` files in this
folder, which VS Code picks up automatically, and the `hooks:` frontmatter of
individual `.agent.md` files. They compose — neither replaces the other.

Two measurements, recorded because this folder documented the opposite for
months:

- A workspace folder containing nothing but a `.github/hooks/agent-hooks.json`
  — no agents, no instructions — ran its `PreToolUse` hook 13 times in one
  session, with the working directory set to that folder. Nothing but the
  JSON could have registered it.
- Across a session log of 4,146 hook runs, one `PreToolUse` event shows
  `block-dangerous` followed by `test-writer-pretooluse`, 167 times.
  `test-writer.agent.md` declares the second and not the first, so the two
  sources fired into a single event.

**Declare a hook in one place.** A hook every agent needs goes into
`agent-hooks.json`; an agent's frontmatter holds only the hooks that agent
alone needs. The shipped agents used to re-declare global hooks, and this
section used to forbid removing the copies until the repeats seen in #166 were
explained. They are now: across 8 hook logs, all 4,951 repeats of a script
within one call came from a second declaration: global JSON plus a
frontmatter copy, or a second workspace root. None came from the same
declaration firing twice. Over all 6,415 retained invocations, every global
hook ran in every call of its event, so the copies guarded nothing (#345).

The concern behind the old rule still holds: a guard that quietly stops
running is a hole nobody sees. It is now a check rather than a duplicate:

- `test-hooks-integration.ps1` Check 10 **fails** when an invocation did not
  run a global hook registered for its event. Check 9 **warns** when a script
  runs twice in one call.
- `test-hook-declarations.ps1` **fails** when an agent re-declares a global
  hook for the same event.

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

**Per-agent:** Define hooks in agent frontmatter (`.agent.md` files) so they
fire only for that agent. Example:

```yaml
hooks:
  PreToolUse:
    - type: command
      command: 'bash .github/hooks/scripts/my-hook.sh'
      windows: 'powershell -ExecutionPolicy Bypass -File .github\hooks\scripts\my-hook.ps1'
```

**Folder-wide:** JSON format, loaded from this folder automatically:

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

## Writing a New Hook

A hook runs from wherever the agent process happens to sit — never reliably
from the repo root. Anything a hook derives from the current working directory
(`Join-Path (Get-Location) '.github/af-env.conf'`, `$(pwd)/.github/...`,
`git rev-parse --show-toplevel`) therefore resolves to nothing on the majority
of invocations, and an unread config is indistinguishable from an empty one:
the hook silently reads its own defaults and stops gating what it was written
to gate. The same shape applies to the interpreter — on Windows `python3` is
an App Execution Alias that sits on PATH, runs nothing and exits non-zero, so
a `command -v python3` hit hands the hook a corpse and it falls through to its
fail-open branch.

**Every new hook script must therefore source the shared preamble as its first
real statement**, and take root, config and interpreter from it:

```bash
# bash
_AF_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
. "$_AF_DIR/_common.sh"

SRC_DIR=$(af_conf_get SRC_DIR src)
[ -n "$AF_PYTHON" ] || { echo '{}'; exit 0; }
"$AF_PYTHON" "$AF_MAIN_ROOT/.github/scripts/some-checker.py"
```

```powershell
# PowerShell
. "$PSScriptRoot/_common.ps1"

$srcDir = Get-AfConfig -Key 'SRC_DIR' -Default 'src'
if ($AfPython) { & $AfPython (Join-Path $AfMainRoot '.github/scripts/some-checker.py') }
```

What the preamble provides:

| bash | PowerShell | Meaning |
|---|---|---|
| `AF_SCRIPT_DIR` | `$AfScriptDir` | Directory the hook scripts live in |
| `AF_MAIN_ROOT` | `$AfMainRoot` | Checkout where `.github/` is deployed |
| `AF_CODE_ROOT` | `$AfCodeRoot` | Active worktree if `.github/.active-worktree` points at one, else main root |
| `AF_CONF` / `AF_CONF_FOUND` | `$AfConfPath` / `$AfConfFound` | Path to the config (`AF_CONF_PATH` if set, else `af-env.conf`) and whether it exists |
| `AF_PYTHON` | `$AfPython` | An interpreter **proven to run**, or empty |
| `af_conf_get KEY [DEFAULT]` | `Get-AfConfig -Key <name> [-Default <value>]` | Config lookup that never fails the hook |

Use `AF_MAIN_ROOT` for framework assets (`.github/scripts/...`, logs, config)
and `AF_CODE_ROOT` for the code under review — they differ whenever the work
runs in a git worktree. Set `AF_PYTHON_OVERRIDE` to force a specific
interpreter; the preamble probes it like any other candidate, so an override
pointing at something broken is rejected rather than trusted.

Set `AF_CONF_PATH` to make a different file the config for one process. It
exists so a test can state the policy it asserts under instead of inheriting
whatever `af-env.conf` the checkout ships — `test-hooks.ps1` writes a config
holding a declared autonomy policy and points the hooks at it, which is why its
verdict no longer changes with a project's `AUTONOMY_CAT_*` settings. A path
that does not exist counts as **no config**, not as a fallback to the deployed
file: falling back would put those settings back in play behind a typo. The
variable configures the ask/auto boundary only — the deny tier is hardcoded and
resolved before any category is read, so no config can approve what it covers.

**The rule is enforced, not merely documented.**
`.github/scripts/check-hook-resolution.py` scans `hooks/` for cwd-relative
config reads, `git rev-parse --show-toplevel` root discovery, bare
`command -v python` / `Get-Command python` lookups and command-position
`python3`, and exits non-zero on a hit — `scripts/test-hooks.ps1` runs it over
the whole `hooks/` tree, so a regression fails the suite. For the rare line
where a finding is genuinely correct, append `af-resolution-ok` in a comment
on that line and say why.

### Gate logic goes in Python, not in the shell

A hook ships in two dialects because VS Code may invoke either one. That does
not mean the *gate* exists twice. **New gate logic goes into a `.py` core next
to the wrappers; the `.ps1` and `.sh` files are reduced to interpreter
resolution and stdin marshalling.**

This is not a style preference. Measured on 2026-09-22, the two `scan-secrets`
twins disagreed on three of four payloads, in both directions, in a gate whose
entire job is to catch secrets: the Bash side had neither the connection-string
rule nor the `apikey` alias, and the PowerShell side filtered by an extension
allowlist that excluded `.conf`. Nothing was broken — the two implementations
had simply been edited at different times. Writing the logic once removes the
thing that drifts.

`scan-secrets.{py,ps1,sh}` is the reference shape. A wrapper resolves
`$AfPython` / `$AF_PYTHON`, hands stdin to the core, and returns its exit code;
when no interpreter is available it says so instead of silently passing.

**Encoding (#341).** Read stdin with `Read-AfStdin` (bytes, UTF-8), never
`[Console]::In`, and never set `[Console]::InputEncoding`/`OutputEncoding`:
that calls `SetConsoleCP` and changes the *caller's* console. Measured: one hook
call flipped it from 437 to 65001, its pipes then carried a BOM, and every later
secret scan answered `{}`. A Python core reads `sys.stdin.buffer` as
`utf-8-sig`. `test-long-line-guard.ps1` L11/L12 hold both rules.

**The rule is enforced, not merely documented.**
`.github/scripts/check-dialect-wrappers.py` fails a build when a `.ps1`/`.sh`
pair carries logic instead of delegating (`DW001`), when a wrapper never names
its core (`DW002`), or when a **new** twin pair ships with no Python core at
all (`DW003`). `DW003` is the ratchet: the list of pairs that predate the rule
may only shrink, and `scripts/test-dialect-wrappers.ps1` holds the ceiling that
makes that binding. For a genuine exception, put `af-dialect-ok` plus a reason
in a comment in **both** wrappers.

## Running the Suites

`scripts/test-hooks.ps1` covers the PowerShell hooks, `scripts/test-hooks.sh`
the bash ones. `run-all-tests.ps1` sweeps `test-*.ps1` and therefore does not
include the bash suite; CI runs it as its own step.

On Windows there is a bash even when `bash` is not on `PATH`: Git for Windows
installs one at `C:\Program Files\Git\bin\bash.exe`. It inherits the current
directory, so this runs from the repository root:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' -c 'bash flavors/github-copilot/.github/scripts/test-hooks.sh'
```

Read the summary line, not only the exit code. The suite exits **0** when it
finds no usable Python interpreter — it prints `SKIP:` and asserts nothing,
which is a pass that means the opposite of one (#190).

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

#### PreToolUse: Work Item Owner Gate

**Scripts:** `scripts/block-dangerous.ps1` (Windows) / `scripts/block-dangerous.sh`
(Unix), both delegating to `scripts/work-item-owner.py`

Refuses any `*wit_work_item_write` call that would create an unowned ADO work
item (#36): `action=create` without a non-empty `System.AssignedTo`, and every
`action=add_child`, whose schema has no assignee field at all. The reason names
the fix — the `ADO_DEFAULT_ASSIGNED_TO` value to pass, or, when that key is
empty, that the agent must ask the human. Updates go to the field shrink guard
below.

A `create` is also refused when its body would be stored where no one reads it
(#289): a `Bug` whose body is in `System.Description` and not in
`Microsoft.VSTS.TCM.ReproSteps` (the stock Bug form renders only the latter), or
a long-text field holding Markdown without `"format": "Markdown"` (ADO stores it
as HTML, so `##` renders literally). An `update` carries no type, so it is not
judged for this.

**Blocking** — answers `hookSpecificOutput.permissionDecision: "deny"` at exit
0\. `PreToolUse` is the one event both VS Code Local and GitHub Copilot let a
hook refuse. It rides in the existing hook rather than registering its own:
Local ignores matchers, so a separate hook would start another shell on every
tool call. Without a Python interpreter it refuses the call (#251).

#### PreToolUse: Work Item Field Shrink Guard

**Scripts:** `scripts/work-item-owner.py` (judges, PreToolUse) and
`scripts/scan-secrets.py` (records reads, PostToolUse), both through
`scripts/_field_guard.py`

Stops an `update` / `update_batch` from silently shortening a long text field
(#197, which lost a third of a description that way). The PostToolUse side
caches, per session, the length and headings of every field a `wit_work_item`
`get`/`get_batch` or a write response returned, keyed by revision. The
PreToolUse side compares each field op against that cache:

| Situation | Verdict |
|---|---|
| Long field, item never read in this session | deny — read first |
| Guarded field (read value > `WI_FIELD_GUARD_MIN_CHARS`) without `test /rev` | deny |
| `test /rev` differs from the cached revision | deny — re-read |
| Shrink over `WI_FIELD_SHRINK_PCT` % and `WI_FIELD_SHRINK_CHARS`, or a lost heading | `WI_FIELD_SHRINK_POLICY` |

`WI_FIELD_SHRINK_POLICY`: `ask` (default) asks the human; `declared` allows a
shrink declared in the same call and asks otherwise; `declared-strict` allows a
declared shrink and denies otherwise; `deny` denies every shrink. The
declaration is a `System.History` line,
`af-shrink: <field>; remove: <heading>, ...; expect: <new length>`, checked
against the diff: the lost headings must equal the declared ones and the new
length must be within 10 % of `expect`. A declaration written after the hook
has judged that field at that revision does not count until the item has a new
revision — the verdict names the loss, and copying it back is not consent.

The read cache lives under the temp directory (`AF_FIELD_CACHE_DIR` overrides)
and expires after 24 hours. The `System.History` field itself is never judged.

#### PreToolUse: GitHub Body Shrink Guard

**Scripts:** `scripts/work-item-owner.py` (judges, PreToolUse) and
`scripts/scan-secrets.py` (records, PostToolUse), both through
`scripts/_body_guard.py`

The #197 guard for GitHub (#376). `issue_write update`, `update_pull_request`
and `update_issue_comment` replace the text. The PostToolUse side caches length,
headings and a hash of every body a read returned (any object with a `body` and
a github.com `html_url`: issue/PR `get`, `get_comments`, search and list
results). It also caches what a successful write or create stored, so the next
write is compared with the session's own last write.

| Situation | Verdict |
|---|---|
| `body` and `state` in one update | deny: comment first, then a state-only change |
| Target never read in this session | deny: read first |
| Read older than `WI_FIELD_READ_MAX_AGE_MIN` (10) | deny: re-read (GitHub has no `If-Match`) |
| Shrink over `WI_FIELD_SHRINK_PCT` % and `WI_FIELD_SHRINK_CHARS`, or a lost heading | `WI_FIELD_SHRINK_POLICY` |

The declaration is a comment posted before the write on the same issue or PR:
`af-shrink: body; remove: <heading>, ...; expect: <new body length>`, or
`af-shrink: comment <id>; ...` for a comment. It is checked against the diff
like the ADO declaration. It does not count once a verdict has named the loss
for that text, until the text changes. Issue and PR text from the last
`## Working state` heading on is not guarded: `work-item-state` sanctions that
block as the one replaceable part. Reads are taken as verbatim, which holds
from github-mcp-server 1.12.0 on.

#### PostToolUse: Secret Detection Scan

**Scripts:** `scripts/scan-secrets.ps1` (Windows) / `scripts/scan-secrets.sh` (Unix)

Scans files after file-editor tool calls for hardcoded secrets. Uses
**gitleaks** if installed, otherwise falls back to regex pattern matching.

**Blocking** — on a hit it emits `{"decision":"block","reason":…}` and exits
**0**. The decision, not the exit code, is what the harness acts on: any
non-zero exit other than 2 is a non-blocking warning and its stdout is
discarded, so exiting 1 would throw away the very verdict it was meant to
carry. From v1.7.1 to the fix for issue #339 this gate did exactly that —
documented as HARD, advisory in practice.

The `reason` names the offending file. VS Code Local enforces the block;
GitHub Copilot's `postToolUse` has no block at all, so there the same payload
surfaces as `additionalContext` — the model sees the finding, the write is not
reverted.

**Patterns detected (regex fallback):**

| Pattern | Example |
|---|---|
| AWS Access Key | `AKIA...` (20-char key) |
| Generic Secret | `password`, `secret`, `token`, `api_key` or `apikey`, then `=` or `:` and a quoted value of 8+ characters |
| Private Key | a PEM `BEGIN ... PRIVATE KEY` header line |
| Connection String | `Server=` or `Data Source=`, followed by a `User Id` or `Password` key |

#### PostToolUse: Long-Line Notice

**Scripts:** `scripts/scan-secrets.ps1` / `scripts/scan-secrets.sh`, via
`scripts/_long_lines.py`; limits in `scripts/tool-limits.json`

Advisory, never blocks. A text tool result over the spill threshold reaches the
model only as a file path, and `read_file` then cuts every line over 2,000
characters — an ADO HTML description is usually one line (#341). For a
non-write tool whose result will spill *and* carries such a line, the hook
answers with `additionalContext` naming the long fields and their lengths, and
writes a lossless copy to `%TEMP%/af-long-lines/` with those lines split into
1,000-character chunks ending ` <<AF-WRAP>>`. `read_file` itself cannot be
watched — its `tool_response` reaches hooks empty — so the check sits on the
tool that produced the result. It shares the secret scan's process rather than
starting a second interpreter on every call.

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
