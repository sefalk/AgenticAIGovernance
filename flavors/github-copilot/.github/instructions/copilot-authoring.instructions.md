---
name: 'Copilot Authoring Rules'
description: 'Gotchas, link conventions, and pre-save checklist for authoring .agent.md, .prompt.md, and .instructions.md files.'
applyTo: '**/*.agent.md,**/*.prompt.md,**/*.instructions.md'
---

# Copilot File Authoring Rules

These rules prevent common errors when creating or editing VS Code Copilot
customisation files. Every gotcha below was discovered through real trial
and error.

## 1. Markdown Link Resolution

**Links resolve relative to the file's own directory, NOT the workspace root.**

From `.github/copilot-instructions.md`:
- → `.github/MANIFEST.md` → use `MANIFEST.md` (same directory)
- → `.github/instructions/arch.md` → use `instructions/arch.md`

From `.github/agents/planner.agent.md`:
- → `.github/MANIFEST.md` → use `../MANIFEST.md` (up one level)
- → `.github/instructions/arch.md` → use `../instructions/arch.md`

**Rule:** Always count directory levels from the file you're editing.

## 2. Coordinator-Worker Pattern (Subagents)

### Key YAML Fields for Autonomous Workflows

| Field | Where | Purpose |
|---|---|---|
| `agents:` | Coordinator | List of worker agent names available as subagents |
| `user-invocable: false` | Workers | Hides agent from dropdown (subagent-only) |
| `disable-model-invocation: true` | Special | Prevents agent from being used as subagent |

### How Subagents Work

1. The coordinator lists workers in its `agents:` array
2. The coordinator must have `agent` in its `tools:` list
3. The coordinator invokes workers by prompting "Use the {name} agent as a subagent"
4. Each subagent gets its own isolated context window
5. Subagents return a summary to the coordinator

### Example: Coordinator

```yaml
---
name: coordinator
tools: ['agent', 'todo', 'search/codebase', 'read/readFile']
agents: ['planner', 'implementer', 'reviewer']
---
```

### Example: Worker (subagent-only)

```yaml
---
name: implementer
user-invocable: false
tools: ['edit/editFiles', 'execute/runTests']
---
```

### Restricting Subagent Access

- `agents: ['*']` — all agents available as subagents (default)
- `agents: ['planner', 'implementer']` — only named agents
- `agents: []` — no subagent access
- Listing an agent in `agents:` overrides its `disable-model-invocation: true`

### Model Assignment (Tier Placeholders)

Subagents pin their model via a **tier placeholder** that the deploy resolves to
a concrete model list. The **coordinator stays unpinned** (no `model:` field) so
it inherits the user's model picker.

```yaml
---
name: implementer
model: __AF_TIER_BALANCED__
---
```

- Tokens: `__AF_TIER_PREMIUM__`, `__AF_TIER_BALANCED__`, `__AF_TIER_EFFICIENT__`.
- The deploy replaces the token with the list from the target `af-env.conf`
  (`AF_MODEL_TIER_*`) or the curated defaults in `deploy.ps1` / `deploy.sh`.
  A multi-entry list becomes a prioritized YAML array — VS Code tries each until
  one is available (drift-resilient).
- **Curating drift:** when the model line-up changes, update the tier arrays in
  `af-env.conf` (or the deploy defaults) and re-deploy — never edit each agent.
- Tiers: PREMIUM = deep reasoning (arbiter, code-critic); BALANCED = planner,
  implementer, test-critic; EFFICIENT = concrete tasks (test-writer, refactorer,
  documenter, researcher, compliance-checker, ado-* workers).

### Managed Regions (Project-Owned Content)

A **managed region** carves out a project-owned span inside a framework file that
the deploy treats specially: its content is **ignored for change classification**
(the deploy hashes the region-*stripped* file) and **preserved on write** (the
target's region body is transplanted onto the incoming framework base). This lets
a project fill the region locally without ever producing a CONFLICT on redeploy,
while framework changes *outside* the region still update normally.

Syntax — a matched marker pair, one region per name, name in `[A-Za-z0-9_.-]`:

```markdown
<!-- AF:MANAGED:curated-skills:START -->
<!-- AF:MANAGED:curated-skills:END -->
```

- Markers ride on their own line; any comment wrapper works (`<!-- -->`, `#`,
  `//`). The body between them is project territory; the deploy never overwrites
  it once populated.
- The framework ships regions **empty** (START/END on adjacent lines). Empty
  regions strip to themselves, so never-populated projects stay UNCHANGED.
- The only current consumer is agent `## Skills` (`AF:MANAGED:curated-skills`,
  written by `/af-curate-skills`). Byte-identical strip/merge is implemented in
  `deploy_core.py`, `deploy.ps1`, and `deploy.sh`.

**Use sparingly.** A managed region is the tool of last resort for content that
is *genuinely per-project and unpredictable*. For everything configurable, prefer
`af-env.conf` + a deploy-resolved placeholder (see Tier Placeholders): config
keys are visible, validated, and curated in one place, whereas regions hide
divergence inside deployed files. Add a new region only when there is no sensible
`af-env.conf` representation.

## 3. Known Gotchas

### 3.1 Handoff Prompts: No Block Scalars

VS Code's agent parser does **NOT** support YAML block scalars (`>`, `|`,
`>-`, `|-`) inside handoff objects. Use single-line quoted strings only.

```yaml
# ✅ CORRECT
handoffs:
  - label: Implement this plan
    agent: implementer
    prompt: 'Implement the plan outlined above. Follow architecture and testing instructions.'
    send: false

# ❌ WRONG — will parse incorrectly
handoffs:
  - label: Implement this plan
    agent: implementer
    prompt: >
      Implement the plan outlined above.
    send: false
```

### 3.2 Renamed / Deprecated Fields

| Old Name | Current Name | Notes |
|---|---|---|
| `todos` | **`todo`** | "Tool 'todos' has been renamed, use 'todo' instead." |
| `user-invokable` | **`user-invocable`** | Dropped the "k" in latest VS Code |
| `infer` | **`user-invocable` + `disable-model-invocation`** | `infer` is deprecated; use the two new fields for independent control |

### 3.3 Extension Tool Prefix Required

Extension / MCP tools must use their server prefix:

```yaml
# ✅ CORRECT
tools:
  - pylance-mcp-server/pylanceImports

# ❌ WRONG — will not resolve
tools:
  - pylanceImports
```

For all tools from one server: `pylance-mcp-server/*`

## 4. Supported Tool Names (Built-in)

### Search Tools
- `search/codebase` — semantic search across workspace
- `search/textSearch` — exact/regex text search
- `search/fileSearch` — glob file search
- `search/listDirectory` — list directory contents
- `search/usages` — find references/definitions
- `search/changes` — git diffs

### Read Tools
- `read/readFile` — read file contents
- `read/problems` — compiler/lint errors

### Edit Tools
- `edit/editFiles` — modify existing files
- `edit/createFile` — create new files
- `edit/createDirectory` — create directories

### Execute Tools
- `execute/runInTerminal` — run terminal commands
- `execute/getTerminalOutput` — get terminal output
- `execute/runTests` — run test suite
- `execute/testFailure` — get test failure details

### Orchestration Tools
- `todo` — manage task todo list
- `agent` — invoke subagents (requires `agents:` field for control)

### Web Tools
- `web` — web search
- `web/fetch` — fetch webpage content

## 5. Pre-Save Checklist

Before saving any `.agent.md`, `.prompt.md`, or `.instructions.md` file:

- [ ] Markdown links resolve from the file's own directory
- [ ] YAML uses only supported attributes
- [ ] Coordinator has both `agent` in `tools:` and `agents:` list
- [ ] Workers have `user-invocable: false` if subagent-only
- [ ] Handoff `prompt:` values are single-line quoted strings (no `>` or `|`)
- [ ] Planning tool is `todo` (not `todos`)
- [ ] Extension tools use full `<server>/<toolName>` format
- [ ] `applyTo` globs use forward slashes and `**` patterns
- [ ] `infer` not used (deprecated — use `user-invocable` + `disable-model-invocation`)
- [ ] Model arrays use exact model names with vendor suffix: `Model Name (copilot)`
- [ ] Context budget still holds: `pwsh .github/scripts/check-context-budget.py`

### Before widening an `applyTo` to `**`

`applyTo: '**'` puts the file into the **always-on set** — prepended to every
chat request, in every workflow, forever. Its cost is the file size multiplied
by every turn the project will ever run, which makes it the most expensive
decision available in this directory.

Prefer, in order:

1. **A narrower glob.** Most rules are about a file type, not about everything.
2. **A skill.** Depth belongs in `skills/` and loads on demand.
3. **The owning agent file.** A rule only one agent needs is not a global rule.
4. **`applyTo: '**'`** — only for rules every agent needs on every turn.

`check-context-budget.py` enforces the ceiling (`AF_CONTEXT_BUDGET_TOKENS`).
The headroom is deliberately small: adding an always-on rule should mean
removing something else, not raising the budget.

## 6. Agent Hooks Authoring

Hook configurations live in `.github/hooks/*.json`. Key rules:

### File Format

```json
{
  "hooks": {
    "EventName": [
      {
        "type": "command",
        "command": "default-command",
        "windows": "windows-specific-command",
        "timeout": 15
      }
    ]
  }
}
```

### Supported Event Names

`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`,
`PreCompact`, `SubagentStart`, `SubagentStop`, `Stop`

### Hook Output

- Exit code `0` → success (parse stdout as JSON)
- Exit code `2` → blocking error (stop processing)
- Other exit codes → non-blocking warning

### Security Rules

- Never hardcode secrets in hook commands — use `env` or environment variables
- Always validate stdin input in hook scripts
- Use `chat.tools.edits.autoApprove` to prevent agents editing hook scripts

## 7. Model Prioritization

Workers can specify a **model array** — VS Code tries each in order:

```yaml
model:
  - Claude Sonnet 4 (copilot)
  - GPT-4.1 (copilot)
```

### Naming Format

Model names use the format `Model Name (vendor)`:
- `Claude Sonnet 4 (copilot)`
- `GPT-4.1 (copilot)`
- `Claude Haiku 4.5 (copilot)`
- `Gemini 3 Flash (Preview) (copilot)`

### Strategy

| Worker Type | Model Strategy |
|---|---|
| Read-only (planner, critics, arbiter) | Fast/efficient first |
| Editing (test-writer, implementer, refactorer) | Most capable (or user-selected) |
| Documenter | Efficient (structured output) |

If no `model:` is specified, the user's currently selected model is used.

## 8. Prompt File Features

### Agent Field

Prompt files can specify which agent to use:

```yaml
agent: coordinator  # routes to the coordinator agent
```

Valid values: `ask`, `agent`, `plan`, or any custom agent name.

### Input Variables

```yaml
${input:variableName}             # basic input
${input:variableName:placeholder} # input with placeholder text
```

### Built-in Variables

- `${workspaceFolder}`, `${workspaceFolderBasename}`
- `${selection}`, `${selectedText}`
- `${file}`, `${fileBasename}`, `${fileDirname}`

## 9. Skills Visibility Controls

Skills now support the same visibility fields as agents:

| Field | Default | Purpose |
|---|---|---|
| `user-invocable` | `true` | Show/hide from `/` slash command menu |
| `disable-model-invocation` | `false` | Allow/prevent automatic loading by AI |

| Configuration | In `/` Menu | Auto-Loaded | Use Case |
|---|---|---|---|
| Both defaults | Yes | Yes | General-purpose skills |
| `user-invocable: false` | No | Yes | Background knowledge |
| `disable-model-invocation: true` | Yes | No | On-demand only |
| Both set | No | No | Disabled |

## 10. Custom Tool Sets

Tool sets group related tools under a name, referenced by agents in `tools:`.

### File Location

`.vscode/toolsets.jsonc` — discovered automatically by VS Code.

### File Format

```jsonc
{
  "set-name": {
    "tools": ["toolA", "toolB"],
    "description": "What this group provides",
    "icon": "codicon-name"
  }
}
```

### Using in Agent Files

Reference tool set names alongside individual tools in the `tools:` list:

```yaml
tools:
  - codebase-reader                        # custom tool set
  - test-runner                            # custom tool set
  - pylance-mcp-server/pylanceSyntaxErrors # individual tool
```

### Naming Conventions

- Use `kebab-case` for tool set names
- Avoid collisions with built-in sets: `search`, `edit`, `runCommands`,
  `runNotebooks`, `runTasks`
- Name by capability, not by agent role

### Pre-Save Checklist Addition

- [ ] Tool set names in agent `tools:` match names defined in `toolsets.jsonc`
- [ ] No duplicate tools between a referenced set and individual tool entries
- [ ] Built-in set names not accidentally shadowed by custom sets
