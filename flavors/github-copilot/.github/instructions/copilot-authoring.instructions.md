---
name: 'Copilot Authoring Rules'
description: 'Gotchas, link conventions, and pre-save checklist for authoring .agent.md, .prompt.md, and .instructions.md files.'
applyTo: '**/*.agent.md,**/*.prompt.md,**/*.instructions.md'
---

# Copilot File Authoring Rules

These rules prevent common errors when creating or editing VS Code Copilot
customisation files. Every gotcha below was discovered through real trial
and error.

**Reference depth lives in `skills/copilot-authoring/SKILL.md`** — the
coordinator/worker subagent pattern, model tiers, managed regions, the built-in
tool-name catalogue, hooks JSON, prompt-file features, skill visibility, and
custom tool sets. Read it when you are building one of those from scratch. This
file holds what binds on every edit.

## 1. Markdown Link Resolution

**Links resolve relative to the file's own directory, NOT the workspace root.**

From `.github/copilot-instructions.md`:
- → `.github/MANIFEST.md` → use `MANIFEST.md` (same directory)
- → `.github/instructions/arch.md` → use `instructions/arch.md`

From `.github/agents/planner.agent.md`:
- → `.github/MANIFEST.md` → use `../MANIFEST.md` (up one level)
- → `.github/instructions/arch.md` → use `../instructions/arch.md`

**Rule:** Always count directory levels from the file you're editing.

## 2. Known Gotchas

### 2.1 Handoff Prompts: No Block Scalars

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

### 2.2 Renamed / Deprecated Fields

| Old Name | Current Name | Notes |
|---|---|---|
| `todos` | **`todo`** | "Tool 'todos' has been renamed, use 'todo' instead." |
| `user-invokable` | **`user-invocable`** | Dropped the "k" in latest VS Code |
| `infer` | **`user-invocable` + `disable-model-invocation`** | `infer` is deprecated; use the two new fields for independent control |

### 2.3 Extension Tool Prefix Required

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

## 3. Pre-Save Checklist

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

The same reasoning applies one level down: a narrow `applyTo` makes a file load
*less often*, not *cheaply*. The conditional set has its own ceiling
(`AF_CONDITIONAL_BUDGET_TOKENS`), so depth still belongs in a skill.
