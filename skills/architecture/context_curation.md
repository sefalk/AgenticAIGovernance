---
title: Agentic Context Curation
description: Techniques for managing LLM token load, ensuring high-density context, and preventing hallucinations caused by context exhaustion.
applies_to: [all]
complexity: advanced
maturity: draft
version: "1.0"
last_reviewed: 2026-03-04
related: [task_decomposition, system_design]
---
# Agentic Context Curation

## Purpose
This skill teaches agents and prompt engineers how to manage the Context Window (token budget). Giving an AI agent the entire repository as context wastes compute, causes memory loss ("needle in a haystack" failures), and leads to hallucinations. Proper context curation ensures the agent only "sees" the exact files necessary to solve the active task.

## Principles
1. **High Density over High Volume:** 10 lines of precise code are infinitely more valuable than 10,000 lines of irrelevant codebase architecture. *(AAIG L1: Efficiency / Pragmatism)*
2. **Read Before You Write:** Agents must actively discover their context using file-system search tools rather than assuming the shape of the codebase. *(AAIG L1: Fail-Safe)*

## Techniques & Patterns

### 1. Mechanical Discovery
*   **Grep over Cat:** Before viewing a file, agents should use AST parsers or `grep` to find the specific function or class.
*   **Tree Exploration:** Always use directory listing tools (`tree` or similar) to understand the project skeleton before diving into specific files.

### 2. Context Packing (Project Bindings)
*   **Dynamic `.cursorrules`:** Instead of one massive global rule file, project boundaries should use scoped instructions (e.g., placing a specific `.cursorrules` inside the `frontend/` directory and a different one in `backend/`).
*   **Summary Architecture artifacts:** Large projects must maintain a high-density `ARCHITECTURE.md` file that summarizes the system. The agent reads this *instead* of reading 50 source files to understand the data flow.

### 3. State Management
*   **Checkpoints:** When working on a long task (e.g., refactoring 20 files), the agent must create intermediate summary artifacts (like a `scratchpad.md`) to offload memory, preventing token exhaustion.

## Quality Gates
*   **Context Limit Monitor:** CI/CD or Agent orchestration platforms should flag if an agent's prompt consistently consumes >80% of the model's maximal context window.
*   **Blind Edit Prevention:** An agent MUST NOT execute a file write operation if it has not previously read the file or its direct AST dependencies in the current session.

## Anti-Patterns

| Anti-Pattern | Why it's harmful | Better Approach |
| :--- | :--- | :--- |
| **"Read All Files"** | Passing the entire `src/` directory to the LLM guarantees degraded reasoning performance due to the "Lost in the Middle" phenomenon. | Use semantic search or tag-based extraction to find only relevant files. |
| **Guessing Imports** | Attempting to import a module without verifying its path via `ls` or `find`. | Always mechanicaly verify file paths before writing code. |
| **Monolithic Instruction Prompts** | Giving the agent a 5-page prompt telling it every rule for the whole company. | Distil instructions into domain-specific, dynamically loaded skills (like this one). |

## See Also
*   [Task Decomposition](file:///d:/Dokumente/Projekte/AgenticAIGovernance/skills/project_management/task_decomposition.md)
*   [System Design](file:///d:/Dokumente/Projekte/AgenticAIGovernance/skills/architecture/system_design.md)
