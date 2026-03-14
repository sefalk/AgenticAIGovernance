---
name: refactoring
description: Disciplined code restructuring without behaviour change. Code smells, refactoring catalog, safe workflow, and IDE-assisted moves.
argument-hint: '[module or function to refactor] [smell: complexity|duplication|coupling|naming]'
disable-model-invocation: true
---

# Refactoring Skill

Guidance for the **refactorer** agent and any agent performing structural
code changes. Refactoring changes *structure*, never *behaviour*.

## When to Use

- Refactor phase of TDD (Red → Green → **Refactor**)
- Complexity threshold exceeded (radon grade C+ in domain core)
- Code review identified structural issues
- Before adding a feature when existing code doesn't accommodate it cleanly

## Principles

- **Behaviour preservation** — tests must pass before, during, and after
- **Small steps** — one refactoring per commit, never combined with behaviour changes
- **Test-driven safety** — if test coverage is insufficient, write tests first
- **Justified** — refactor to reduce future cost, not for aesthetic purity

## The Refactoring Workflow

```
1. Identify the smell (complexity, duplication, coupling)
2. Ensure adequate test coverage for the affected code
3. Plan the steps (write them down if complex)
4. Apply one refactoring at a time
5. Run tests after each step
6. Commit after each successful step
7. Review: is the code genuinely better?
```

**Critical rule:** Never refactor and change behaviour in the same commit.

## Code Smells Reference

| Smell | Symptom | Typical Refactoring |
|---|---|---|
| **Long Function** | > 50 lines | Extract Function |
| **Long Parameter List** | > 4 parameters | Introduce Parameter Object |
| **Duplicate Code** | Same logic in multiple places | Extract Function, Pull Up |
| **Feature Envy** | Function uses another module's data more than its own | Move Function |
| **Data Clumps** | Same group of fields/params appear together | Extract Class or Parameter Object |
| **Primitive Obsession** | Using primitives instead of domain objects | Replace Primitive with Object |
| **Divergent Change** | One module modified for unrelated reasons | Extract Module (split responsibilities) |
| **Shotgun Surgery** | One change requires edits across many files | Move Function/Field (consolidate) |
| **Dead Code** | Unused functions, unreachable branches | Delete |
| **High Complexity** | Cyclomatic complexity > threshold | Decompose Conditional, Extract Function |

## Refactoring Catalog

### Extract

| Refactoring | When | Mechanics |
|---|---|---|
| **Extract Function** | Block does one identifiable thing | Move block to named function, replace with call |
| **Extract Variable** | Complex expression is hard to read | Assign to named variable |
| **Extract Class** | Class has multiple responsibilities | Move fields/methods to new class |
| **Extract Module** | File has grown too large (> 500 lines) | Group related functions into separate module |

### Inline (Reverse of Extract)

| Refactoring | When |
|---|---|
| **Inline Function** | Body is as clear as the name; indirection without value |
| **Inline Variable** | Used once, adds no clarity |

### Move

| Refactoring | When |
|---|---|
| **Move Function** | Function is closer to another module's concern |
| **Move to Separate File** | Module has grown too large |

### Simplify Conditionals

| Technique | Pattern |
|---|---|
| **Decompose conditional** | Extract complex conditions: `if is_eligible(user)` instead of `if user.age > 18 and user.verified and ...` |
| **Guard clauses** | Early returns reduce nesting depth |
| **Replace conditional with polymorphism** | When `if/elif` on type is repeated |

### Simplify Data

| Technique | Pattern |
|---|---|
| **Replace magic numbers** | `MAX_RETRIES = 3` instead of `3` |
| **Introduce Parameter Object** | Replace long parameter lists with a dataclass |

## IDE-Assisted Refactoring

Always prefer IDE-assisted over manual text editing:

| VS Code Action | Shortcut | What It Does |
|---|---|---|
| Rename Symbol | F2 | Renames across all references |
| Extract Function | Ctrl+Shift+R | Moves selection to named function |
| Extract Variable | Ctrl+Shift+R | Assigns expression to variable |

Pylance MCP tools available:
- `pylanceInvokeRefactoring` — programmatic refactoring moves
- `pylanceWorkspaceUserFiles` — find all references

## Quality Gates

| Gate | Threshold |
|---|---|
| Tests pass | 100% before AND after every step |
| No behaviour change | Commit diffs show only structural changes |
| Complexity reduced | Measurable improvement (radon) |
| No new dead code | 0 |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Big-bang refactoring** | Rewriting everything at once | Small, incremental steps |
| **Refactoring without tests** | No safety net | Write tests first |
| **Mixing with features** | Can't tell if bug is from refactoring or feature | Separate commits |
| **Refactoring for purity** | Abstracting code that won't change | Refactor when change is needed (YAGNI) |
| **Manual rename** | Missing some call sites | Use IDE rename (F2) |
