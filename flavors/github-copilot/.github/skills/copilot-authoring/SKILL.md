---
name: copilot-authoring
description: 'Reference depth for authoring VS Code Copilot customisation files — the coordinator/worker subagent pattern, model tiers, managed regions, the built-in tool-name catalogue, hooks JSON, prompt-file features, skill visibility, and custom tool sets.'
---

# Copilot Customisation Authoring

Lookup depth behind `instructions/copilot-authoring.instructions.md`. That file
carries the rules that bind on every edit; this one carries the tables you need
when you are *building* an agent, hook, prompt, or tool set rather than tweaking
one.

## When to Use

- Creating a new agent, prompt, skill, hook, or tool set from scratch.
- Restructuring the coordinator/worker topology or model tiers.
- Looking up an exact built-in tool name or hook event name.

## Coordinator-Worker Pattern (Subagents)

### Key YAML Fields

| Field | Where | Purpose |
|---|---|---|
| `agents:` | Coordinator | List of worker agent names available as subagents |
| `user-invocable: false` | Workers | Hides agent from dropdown (subagent-only) |
| `disable-model-invocation: true` | Special | Prevents agent from being used as subagent |

### How Subagents Work

1. The coordinator lists workers in its `agents:` array.
2. The coordinator must have `agent` in its `tools:` list.
3. The coordinator invokes workers by prompting "Use the {name} agent as a subagent".
4. Each subagent gets its own isolated context window.
5. Subagents return a summary to the coordinator.

```yaml
---
name: coordinator
tools: ['agent', 'todo', 'search/codebase', 'read/readFile']
agents: ['planner', 'implementer', 'reviewer']
---
```

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

Model names use the format `Model Name (vendor)` — e.g. `Claude Sonnet 4
(copilot)`, `GPT-4.1 (copilot)`, `Gemini 3 Flash (Preview) (copilot)`. A raw
array works where a tier placeholder is not appropriate; VS Code tries each
entry in order. With no `model:` field the user's current selection is used.

| Worker Type | Model Strategy |
|---|---|
| Analysis (planner, critics, arbiter) | Fast/efficient first |
| Editing (test-writer, implementer, refactorer) | Most capable (or user-selected) |
| Documenter | Efficient (structured output) |

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

## Supported Tool Names (Built-in)

**Search:** `search/codebase` (semantic), `search/textSearch` (exact/regex),
`search/fileSearch` (glob), `search/listDirectory`, `search/usages`
(references/definitions), `search/changes` (git diffs).

**Read:** `read/readFile`, `read/problems` (compiler/lint errors).

**Edit:** `edit/editFiles`, `edit/createFile`, `edit/createDirectory`.

**Execute:** `execute/runInTerminal`, `execute/getTerminalOutput`,
`execute/runTests`, `execute/testFailure`.

**Orchestration:** `todo` (task list), `agent` (invoke subagents — requires the
`agents:` field for control).

**Web:** `web` (search), `web/fetch` (fetch page content).

Extension / MCP tools need their server prefix
(`pylance-mcp-server/pylanceImports`); `pylance-mcp-server/*` takes all of them.

## Agent Hooks Authoring

Hook configurations live in `.github/hooks/*.json`.

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

Event names: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`,
`PreCompact`, `SubagentStart`, `SubagentStop`, `Stop`.

Exit codes: `0` → success (stdout parsed as JSON); `2` → blocking error (stop
processing); anything else → non-blocking warning.

Security: never hardcode secrets in hook commands — use `env` or environment
variables; always validate stdin input in hook scripts; use
`chat.tools.edits.autoApprove` to prevent agents editing hook scripts.

## Prompt File Features

```yaml
agent: coordinator  # routes to the coordinator agent
```

Valid `agent:` values: `ask`, `agent`, `plan`, or any custom agent name.

Input variables: `${input:variableName}` and
`${input:variableName:placeholder}`.

Built-in variables: `${workspaceFolder}`, `${workspaceFolderBasename}`,
`${selection}`, `${selectedText}`, `${file}`, `${fileBasename}`,
`${fileDirname}`.

## Skills Visibility Controls

Skills support the same visibility fields as agents:

| Configuration | In `/` Menu | Auto-Loaded | Use Case |
|---|---|---|---|
| Both defaults (`user-invocable: true`, `disable-model-invocation: false`) | Yes | Yes | General-purpose skills |
| `user-invocable: false` | No | Yes | Background knowledge |
| `disable-model-invocation: true` | Yes | No | On-demand only |
| Both set | No | No | Disabled |

## Framework Skill vs Project Skill

**Platform skills carry the runbook; projects carry a configuration overlay,
never a forked runbook.**

A project-local skill that restates framework guidance is a drift generator,
and the cost is correctness, not context. Two overlapping runbooks activated
for the same agent means the agent follows whichever it happened to consult,
and the two diverge silently — the framework copy keeps the stale rule while
the local copy gets the fix, or the reverse.

A project overlay legitimately holds: profile and cluster ids, catalog/schema
conventions, table-family naming, job-registry entries, local precedents. That
is a handful of lines.

If a project needs to **change** the runbook rather than parameterise it, that
is a signal the framework skill is wrong. Fix it upstream instead of forking.

Applies to any skill presenting a run-type or tool-selection matrix:
**enumerate the disallowed options explicitly, with the reason.** Listing only
the sanctioned paths does not forbid the others — it just fails to mention
them, and an agent optimising for speed finds them anyway.

## Custom Tool Sets

Tool sets group related tools under a name, referenced by agents in `tools:`.
They live in `.vscode/toolsets.jsonc`, discovered automatically by VS Code.

```jsonc
{
  "set-name": {
    "tools": ["toolA", "toolB"],
    "description": "What this group provides",
    "icon": "codicon-name"
  }
}
```

```yaml
tools:
  - codebase-reader                        # custom tool set
  - test-runner                            # custom tool set
  - pylance-mcp-server/pylanceSyntaxErrors # individual tool
```

- Use `kebab-case` for tool set names; name by capability, not by agent role.
- Avoid collisions with built-in sets: `search`, `edit`, `runCommands`,
  `runNotebooks`, `runTasks`.
- Check: set names in agent `tools:` match names defined in `toolsets.jsonc`;
  no duplicate tools between a referenced set and individual entries; no
  built-in set name shadowed by a custom set.

## References

- `instructions/copilot-authoring.instructions.md` — the binding rules and the
  pre-save checklist
- `instructions/quality-gates.instructions.md` — agent naming conventions
