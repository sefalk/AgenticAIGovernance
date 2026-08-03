---
name: 'AI Provenance Marking'
description: 'Rules for marking AI-generated and AI-assisted code. All agents that create or substantially modify files must follow these rules.'
applyTo: '**'
---

# AI Provenance Marking

All contributions by AI agents must be traceable. Implements L1 Principle 3
(Transparency / Traceability) and domain rule R-SD-23 (agent commits attributed
to an Agent ID).

Provenance has three layers: **in-code markers** (this file), **git commits**
(agent name in the commit message), and **workflow logs** (`.github/logs/`).

## Scope

These markers trace AI authorship of **project deliverables** — source code,
tests, and documents produced *inside a target project*.

**Do not mark AF framework files.** That covers everything under `.github/`
(`agents/`, `instructions/`, `skills/`, `prompts/`, `chatmodes/`, `MANIFEST.md`,
`copilot-instructions.md`, `.af-manifest`, `af-env.conf`, hooks, scripts) plus
framework tooling (`deploy.*`, `mcp-deploy/**`, `CHANGELOG.md`, `docs/**`,
`core/**`). These load into agent context on nearly every request, so markers
are pure noise — git history and the CHANGELOG already trace authorship.

**Exception:** `templates/*.md` keep their placeholder, because the documents
they generate *are* project deliverables.

## When to Mark

| Change Type | Marker | Rationale |
|---|---|---|
| New file created by agent | ✅ file-level header | Entire file is AI-generated |
| Substantial modification (≥ 5 lines of logic) | ✅ function/section level | Meaningful AI contribution |
| New test suite created by agent | ✅ file-level header | Tests are first-class artifacts |
| Config file created by agent | ✅ comment header | Track origin |
| Trivial edit (< 5 lines: rename, formatting) | ❌ | Noise outweighs signal |
| Automated refactoring (import sort, unused removal) | ❌ | Mechanical, no creative contribution |

## Marker Format

Always use this parseable format — never free-form text:

```
copilot:generated | <agent-name> | <YYYY-MM-DD>
copilot:modified  | <agent-name> | <YYYY-MM-DD> | <brief description>
```

Comment syntax per file type:

| File type | Placement |
|---|---|
| Python — new file | `# copilot:generated \| implementer \| YYYY-MM-DD` after the module docstring (and after `from __future__ import annotations` if present) |
| Python — modified function | Line in the docstring `Notes` section (NumPy-style); if no docstring, an inline `#` comment above the function |
| Test file — new | `# copilot:generated \| test-writer \| YYYY-MM-DD` after the module docstring |
| Markdown — new file | `> copilot:generated \| documenter \| YYYY-MM-DD` |
| Markdown — modified | `<!-- copilot:modified \| documenter \| YYYY-MM-DD \| added section -->` |
| YAML / config | `# copilot:generated \| planner \| YYYY-MM-DD` |
| JSONC | `// copilot:generated \| implementer \| YYYY-MM-DD` |

## Lifecycle

- Human reviews and accepts → marker remains (traceability).
- Agent modifies AI-generated code again → update the date, keep the most
  recent agent.
- **Markers are never removed by agents.** Only humans may remove them.
- Never add more than one `copilot:generated` header to the same file.
