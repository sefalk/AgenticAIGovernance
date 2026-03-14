---
category: code_quality
applies_to: [all]
complexity: intermediate
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [static_analysis, code_review, design_patterns]
---
# Refactoring

## Purpose

Refactoring is the disciplined practice of improving code structure without changing its observable behavior. It reduces complexity, improves readability, and makes future changes easier and safer. Invoke this skill when code exhibits growing complexity, duplication, or design drift, or when defining Level-3 refactoring workflows.

## Principles

- **Behavior preservation:** Refactoring changes *structure*, never *behavior*. Tests must pass before, during, and after.
- **Small steps:** Each refactoring move is atomic and safe. Never combine structural changes with behavior changes in the same commit.
- **Test-driven safety:** Refactoring requires an adequate test suite as a safety net. If tests are insufficient, write them first.
- **Verifiability (AAIG L1):** Every refactoring step must be verifiable -- tests pass, behavior unchanged.
- **Efficiency (AAIG L1):** Refactor to reduce future cost, not for aesthetic purity. Refactoring must be justified.

## Techniques & Patterns

### When to Refactor

| Trigger | Signal |
|---------|--------|
| **Before adding a feature** | The existing code doesn't accommodate the new feature cleanly. |
| **After fixing a bug** | The bug's root cause was unclear or deeply nested code. |
| **During code review** | Reviewer identifies structural issues. |
| **Rule of three** | Third time you see duplicated logic -- extract it. |
| **Complexity threshold exceeded** | Cyclomatic or cognitive complexity exceeds team standards. |
| **High change coupling** | Changing one file always requires changing three others. |

### Refactoring Catalog

#### Extract

| Refactoring | When to Apply | Mechanics |
|-------------|---------------|-----------|
| **Extract Function/Method** | Block of code does one identifiable thing | Move block to named function. Replace original with call. |
| **Extract Variable** | Complex expression is hard to read | Assign to named variable. Use variable in expression. |
| **Extract Class** | Class has multiple responsibilities | Identify responsibility boundary. Move fields/methods to new class. |
| **Extract Interface** | Multiple classes share a contract | Define interface. Implement in each class. |
| **Extract Module/Package** | File has grown too large | Group related functions/classes into a separate module. |

#### Inline (Reverse of Extract)

| Refactoring | When to Apply |
|-------------|---------------|
| **Inline Function** | Function body is as clear as the name. Indirection without value. |
| **Inline Variable** | Variable is used once and adds no clarity. |
| **Inline Class** | Class does too little to justify its existence. |

#### Move

| Refactoring | When to Apply |
|-------------|---------------|
| **Move Function/Method** | Function is closer to another module's data or concern. |
| **Move Field** | Field is used more by another class than its current class. |
| **Move to Separate File** | Module has grown too large. Single-responsibility split. |

#### Rename

| Refactoring | When to Apply |
|-------------|---------------|
| **Rename Variable / Function / Class** | Current name is misleading, vague, or outdated. |
| **Rename File / Module** | File name doesn't match its contents after changes. |

#### Simplify Conditionals

| Refactoring | Technique |
|-------------|-----------|
| **Decompose conditional** | Extract complex conditions into named functions: `if isEligible(user)` instead of `if user.age > 18 && user.verified && ...` |
| **Replace nested conditionals with guard clauses** | Early returns reduce nesting depth. |
| **Replace conditional with polymorphism** | When `if/switch` on type is used repeatedly. |
| **Consolidate conditional** | Merge parallel conditions with same result. |

#### Simplify Data

| Refactoring | Technique |
|-------------|-----------|
| **Replace magic numbers with constants** | `MAX_RETRIES = 3` instead of `3`. |
| **Introduce Parameter Object** | Replace long parameter lists with a structured object. |
| **Replace Temp with Query** | Replace temporary variable with a method call. |

### The Refactoring Workflow

```
1. Identify the smell (complexity, duplication, coupling).
2. Ensure adequate test coverage for the affected code.
3. Plan the refactoring steps (write them down if complex).
4. Apply one refactoring at a time.
5. Run tests after each step.
6. Commit after each successful step (or logical group).
7. Review the result: is the code genuinely better?
```

**Critical rule:** Never refactor and change behavior in the same commit. This makes it impossible to verify that the refactoring preserved behavior.

### Safe Refactoring with IDE Support

Modern IDEs automate many refactorings safely:

| IDE | Key Refactorings |
|-----|-----------------|
| **JetBrains (IntelliJ, PyCharm, WebStorm)** | Extract, inline, rename, move, change signature -- all with cross-reference updates |
| **VS Code** | Rename symbol (F2), extract function/variable, move to file |
| **Vim/Neovim + LSP** | Rename via LSP, extract via plugins |

**Always prefer IDE-assisted refactoring over manual text editing.** IDE refactorings update all references automatically.

### Code Smells Reference

| Smell | Symptom | Typical Refactoring |
|-------|---------|---------------------|
| **Long Function** | > 50 lines | Extract Function |
| **Long Parameter List** | > 4 parameters | Introduce Parameter Object |
| **Duplicate Code** | Same logic in multiple places | Extract Function/Method, Pull Up |
| **Feature Envy** | Method uses another class's data more than its own | Move Method |
| **Data Clumps** | Same group of fields/params appear together repeatedly | Extract Class or Parameter Object |
| **Primitive Obsession** | Using primitives instead of small domain objects | Replace Primitive with Object |
| **Switch Statements** | Repeated type-based switching | Replace with Polymorphism |
| **Divergent Change** | One class modified for many unrelated reasons | Extract Class (split responsibilities) |
| **Shotgun Surgery** | One change requires many small edits across files | Move Function/Field (consolidate) |
| **Dead Code** | Unused functions, unreachable branches | Delete |

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Tests pass** | 100% | Before AND after every refactoring step. |
| **No behavior change** | Verified | Commit diffs should show only structural changes. |
| **Complexity reduced** | Measurable improvement | Cyclomatic/cognitive complexity should decrease (or at minimum not increase). |
| **No new dead code** | 0 | Refactoring often reveals dead code. Remove it. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Big-bang refactoring** | Rewriting everything at once. Risky, hard to review, hard to revert. | Small, incremental steps. One refactoring per commit. |
| **Refactoring without tests** | No safety net. Bugs introduced silently. | Write tests first, then refactor. |
| **Mixing refactoring with features** | Impossible to tell if a bug is from the refactoring or the feature. | Separate commits: refactor first, then add feature. |
| **Refactoring for purity** | Abstracting code that will never change "just in case." | Refactor when the code needs to change, not pre-emptively (YAGNI). |
| **Renaming without grep** | Renaming a function but missing some call sites. | Use IDE rename (updates all references) or grep to verify. |


## See Also

- [Static Analysis](../code_quality/static_analysis.md)
- [Code Review](../code_quality/code_review.md)
- [Design Patterns](../architecture/design_patterns.md)

## References

- Martin Fowler, *Refactoring: Improving the Design of Existing Code* (2018, 2nd ed.) -- the canonical reference.
- Martin Fowler, Refactoring Catalog: https://refactoring.com/catalog/
- Michael Feathers, *Working Effectively with Legacy Code* (2004) -- techniques for refactoring untested code.
- Joshua Kerievsky, *Refactoring to Patterns* (2004) -- bridging refactoring and design patterns.
