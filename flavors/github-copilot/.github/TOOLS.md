# Agent Tool Inventory

> Central reference for all tools considered, assigned, and excluded across
> the agent team. Agents consult this to understand their capabilities and
> know which agent to delegate to. Humans use it to identify gaps when new
> tools become available.
>
> Tool identifiers match the official VS Code built-in tools reference:
> https://code.visualstudio.com/docs/copilot/reference/copilot-vscode-features#_chat-tools

## Tool-Agent Matrix

Legend: **W** = Write/Edit, **R** = Read, **X** = Execute, **—** = not assigned

| Tool (frontmatter key) | Category | coordinator | planner | test-writer | test-critic | implementer | refactorer | code-critic | documenter | arbiter | researcher | compliance |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **Search & Read** | | | | | | | | | | | | |
| `search/codebase` | R | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `search/textSearch` | R | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `search/fileSearch` | R | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `search/listDirectory` | R | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `search/changes` | R | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | — | ✅ |
| `search/usages` | R | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | — | — |
| `read/readFile` | R | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `read/problems` | R | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Edit** | | | | | | | | | | | | |
| `edit/editFiles` | W | — | — | ✅ | — | ✅ | ✅ | — | ✅ | — | — | — |
| `edit/createFile` | W | — | — | ✅ | — | ✅ | — | — | ✅ | — | — | — |
| `edit/createDirectory` | W | — | — | ✅ | — | ✅ | — | — | ✅ | — | — | — |
| **Execution** | | | | | | | | | | | | |
| `execute/runTests` | X | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | — | — | — | — |
| `execute/runTask` | X | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | — | — | — |
| `execute/createAndRunTask` | X | ✅ | — | — | — | ✅ | ✅ | ✅ | — | — | — | — |
| `execute/testFailure` | X | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | — | — | — | — |
| `execute/runInTerminal` | X | ✅ | — | — | — | — | — | — | — | — | — | — |
| `execute/getTerminalOutput` | X | ✅ | — | — | — | — | — | — | — | — | — | — |
| **Notebook** | | | | | | | | | | | | |
| `edit/editNotebook` | W | — | — | — | — | ✅ | ✅ | — | ✅ | — | — | — |
| `read/getNotebookSummary` | R | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | — | — | — |
| `read/readNotebookCellOutput` | R | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | — | — | — | — |
| `execute/runNotebookCell` | X | — | — | — | — | ✅ | ✅ | ✅ | — | — | — | — |
| `ms-toolsai.jupyter/configureNotebook` | X | — | — | ✅ | — | ✅ | ✅ | ✅ | — | — | — | — |
| `ms-toolsai.jupyter/listNotebookPackages` | R | — | — | — | — | — | — | ✅ | — | — | — | — |
| `ms-python.python/configurePythonEnvironment` | X | — | — | ✅ | — | ✅ | ✅ | ✅ | — | — | — | — |
| **Pylance MCP** | | | | | | | | | | | | |
| `pylance-mcp-server/pylanceFileSyntaxErrors` | R | — | — | ✅ | ✅ | ✅ | ✅ | ✅ | — | — | — | — |
| `pylance-mcp-server/pylanceImports` | R | — | — | ✅ | ✅ | ✅ | ✅ | ✅ | — | — | — | — |
| `pylance-mcp-server/pylanceSyntaxErrors` | R | — | — | ✅ | — | ✅ | ✅ | ✅ | — | — | — | — |
| `pylance-mcp-server/pylanceRunCodeSnippet` | X | — | — | ✅ | — | ✅ | ✅ | — | — | — | — | — |
| `pylance-mcp-server/pylanceInvokeRefactoring` | X | — | — | — | — | — | ✅ | — | — | — | — | — |
| `pylance-mcp-server/pylanceWorkspaceUserFiles` | R | — | — | — | — | — | — | ✅ | — | — | — | — |
| **Web** | | | | | | | | | | | | |
| `web/fetch` | R | — | — | — | — | — | — | — | — | — | ✅ | — |
| **Agent orchestration** | | | | | | | | | | | | |
| `agent` (invoke subagents) | X | ✅ | — | — | — | — | — | — | — | — | — | — |
| `todo` | R/W | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| **VS Code UI** | | | | | | | | | | | | |
| `vscode/askQuestions` | X | ✅ | ✅ | — | — | — | — | — | — | — | — | — |
| `vscode.mermaid-markdown-features/renderMermaidDiagram` | W | — | ✅ | — | — | — | — | — | ✅ | — | — | — |

## Excluded Tools — Rationale

| Tool (docs key) | Why Excluded | Risk if Included |
|---|---|---|
| `newWorkspace` | Not relevant to development workflows. | Scope creep |
| `vscode/installExtension` | Extension management is a human decision. | Unreviewed extensions, supply-chain risk |
| `vscode/runCommand` | Too broad — can invoke any VS Code command. | Bypasses tool restrictions |
| `execute/runInTerminal` (workers) | Workers use `runTests` / `runTask` / `createAndRunTask`. Only coordinator has terminal. | Ad-hoc commands bypass quality gates |
| `read/terminalLastCommand` | Only useful with terminal access (coordinator only). Not assigned to avoid encouraging terminal reliance. | — |
| `read/terminalSelection` | Same as above. | — |

### Notebook-specific exclusions

| Tool (internal) | Why Excluded | Risk if Included |
|---|---|---|
| `create_new_jupyter_notebook` | New notebooks are architectural decisions (entry points). Human decides. | Unreviewed entry points, scope creep |
| `ms-toolsai.jupyter/installNotebookPackages` | Installs inside kernel, bypasses `requirements-dev.txt` and dep-tracking workflow. | Untracked dependencies, venv/kernel drift |
| `configure_non_python_notebook` | Project is Python-only. No use case. | Confusion, wasted tokens |
| `configure_python_notebook` | Superseded by `ms-python.python/configurePythonEnvironment`. | Redundant |
| `restart_notebook_kernel` | No assignable frontmatter key found. Appears to be auto-injected by the Jupyter extension at runtime. | If a key is discovered, add to implementer/refactorer |

### Other built-in tools — considered but not assigned

| Tool (docs key) | Why Not Assigned | Potential Future Use |
|---|---|---|
| `vscode/getProjectSetupInfo` | Project scaffolding — not relevant to maintenance workflows. | New-project setup workflows |
| `vscode/VSCodeAPI` | VS Code extension development reference — not relevant. | Extension development projects |

## Tool Assignment Principles

1. **Least privilege** — agents get only tools needed for their role
2. **Tasks over terminal** — predefined tasks (`run_task`) before ad-hoc terminal
3. **Read before write** — critics and planners get read-only subsets
4. **Dep-tracking integrity** — no tool that installs packages outside the spec file workflow
5. **Kernel = venv** — kernel management happens via venv tools; notebook cell execution is sufficient

## How to Use This Document

- **Coordinator:** consult the matrix to decide which agent can handle a task
  involving specific tools (e.g., "who can edit notebooks?" → implementer,
  refactorer, documenter)
- **Agents:** check your column to confirm you have the tool before attempting
  to use it; if not, report BLOCKED and let the coordinator delegate
- **Humans:** use the Excluded Tools table to evaluate new tools — if the
  exclusion rationale no longer applies, add the tool to the relevant agents
  and update this matrix
