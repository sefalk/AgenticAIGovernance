---
name: 'AI Provenance Marking'
description: 'Rules for marking AI-generated and AI-assisted code. All agents that create or substantially modify files must follow these rules.'
applyTo: '**'
---

# AI Provenance Marking

All contributions by AI agents must be traceable. This instruction defines
when and how to mark files.

**Governance reference:** Implements L1 Principle 3 (Transparency /
Traceability) and domain rule R-SD-23 (Agent commits attributed to Agent ID).

## 3-Layer Provenance Model

| Layer | What | Where | Persistence |
|---|---|---|---|
| **In-code markers** | Comments/docstrings | Source files | Permanent until human review |
| **Git commits** | Agent name in commit message | Git history | Permanent |
| **Workflow logs** | Full traceability per step | `.github/logs/` | Operational (30 days) |

This instruction governs **Layer 1: in-code markers**.

## When to Mark

| Change Type | Marker Required | Rationale |
|---|---|---|
| New file created by agent | ✅ Yes — file-level header | Entire file is AI-generated |
| Substantial modification (≥ 5 lines of logic) | ✅ Yes — function/section level | Meaningful AI contribution |
| New test suite created by agent | ✅ Yes — file-level header | Tests are first-class artifacts |
| Trivial edit (< 5 lines: rename, formatting) | ❌ No | Noise outweighs signal |
| Automated refactoring (import sort, unused removal) | ❌ No | Mechanical, no creative contribution |
| Configuration files created by agent | ✅ Yes — comment header | Track origin |

## Marker Format

All markers follow a **parseable, consistent format**:

```
copilot:generated | <agent-name> | <YYYY-MM-DD>
copilot:modified  | <agent-name> | <YYYY-MM-DD> | <brief description>
```

### Python Files — New File

```python
"""Module docstring here."""
# copilot:generated | implementer | YYYY-MM-DD
```

If the file has `from __future__ import annotations`, the marker goes after it.

### Python Files — Modified Function

Add to the function's docstring `Notes` section (NumPy-style):

```python
def compute_result(df):
    """Compute result from input data.

    Notes
    -----
    copilot:modified | implementer | YYYY-MM-DD | extracted pure logic
    """
```

If no docstring exists, add as inline comment above the function:

```python
# copilot:modified | implementer | YYYY-MM-DD | added validation logic
def compute_result(df):
    ...
```

### Test Files — New File

```python
"""Tests for module_name — description."""
# copilot:generated | test-writer | YYYY-MM-DD
```

### Markdown Files — New File

```markdown
> copilot:generated | documenter | YYYY-MM-DD
```

### Markdown Files — Modified

```markdown
<!-- copilot:modified | documenter | YYYY-MM-DD | added section -->
```

### YAML / JSONC / Config Files

```yaml
# copilot:generated | planner | YYYY-MM-DD
```

```jsonc
// copilot:generated | implementer | YYYY-MM-DD
```

## Marker Lifecycle

| Event | Action |
|---|---|
| Agent creates a file | Add `copilot:generated` header |
| Agent substantially modifies a function | Add `copilot:modified` to docstring |
| Human reviews and accepts | Marker remains (traceability) |
| Human substantially rewrites | Human may remove or replace marker |
| Agent modifies AI-generated code again | Update date; keep most recent agent |

**Rule:** Markers are never removed by agents. Only humans may remove them.

## What NOT to Do

- Do **not** add markers for trivial changes (< 5 lines, formatting only)
- Do **not** add multiple `copilot:generated` headers to the same file
- Do **not** use free-form text — always use the parseable format
