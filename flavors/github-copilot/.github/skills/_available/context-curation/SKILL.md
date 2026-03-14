---
name: context-curation
description: Techniques for managing LLM token load, ensuring high-density context, and preventing hallucinations caused by context exhaustion.
argument-hint: '[task description] — ask for context strategy advice'
---

# Context Curation

## When to Use

- When planning how to gather context for a complex multi-file task
- When an agent is at risk of exceeding token budget
- When designing project-level context artifacts (ARCHITECTURE.md, scratchpads)
- When defining context strategies for long-running agent workflows

## Principles

1. **High Density over High Volume** — 10 lines of precise code are
   infinitely more valuable than 10,000 lines of irrelevant codebase
   architecture. Efficiency demands targeted reads.
2. **Read Before You Write** — Agents must actively discover their context
   using file-system search tools rather than assuming the shape of the
   codebase. Never guess — verify.

## Techniques & Patterns

### 1. Mechanical Discovery

- **Grep over Cat:** Before viewing a file, agents should use AST parsers
  or `grep` to find the specific function or class.
- **Tree Exploration:** Always use directory listing tools (`tree` or
  similar) to understand the project skeleton before diving into specific
  files.

### 2. Context Packing (Project Bindings)

- **Scoped Instructions:** Instead of one massive global rule file, project
  boundaries should use scoped instructions (e.g., placing a specific
  `.instructions.md` inside the `frontend/` directory and a different one
  in `backend/`).
- **Summary Architecture Artifacts:** Large projects must maintain a
  high-density `ARCHITECTURE.md` file that summarizes the system. The
  agent reads this *instead* of reading 50 source files to understand
  the data flow.

### 3. State Management

- **Checkpoints:** When working on a long task (e.g., refactoring 20
  files), the agent must create intermediate summary artifacts (like a
  `scratchpad.md` in session memory) to offload memory, preventing token
  exhaustion.

## Quality Gates

| Gate | Threshold | Notes |
|------|-----------|-------|
| **Context Limit Monitor** | < 80% of model context window | Flag if an agent's prompt consistently exceeds this. |
| **Blind Edit Prevention** | 0 blind writes | An agent MUST NOT write to a file it has not read in the current session. |

## Anti-Patterns

| Anti-Pattern | Why It's Harmful | Better Approach |
|---|---|---|
| **"Read All Files"** | Passing the entire `src/` directory guarantees degraded reasoning (Lost in the Middle). | Use semantic search or tag-based extraction to find only relevant files. |
| **Guessing Imports** | Attempting to import a module without verifying its path. | Always mechanically verify file paths before writing code. |
| **Monolithic Instruction Prompts** | A 5-page prompt telling the agent every rule for the whole company. | Distil instructions into domain-specific, dynamically loaded skills. |

## References

- "Lost in the Middle" — Liu et al. (2023), context window degradation research.
