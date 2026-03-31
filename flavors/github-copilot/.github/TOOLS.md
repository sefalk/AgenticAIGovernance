# Agent Tool Inventory

> Central reference for all tools considered, assigned, and excluded across
> the agent team. Agents consult this to understand their capabilities and
> know which agent to delegate to. Humans use it to identify gaps when new
> tools become available.

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
| `notebook/editNotebookFile` | W | — | — | — | — | ✅ | ✅ | — | ✅ | — | — | — |
| `notebook/getNotebookSummary` | R | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | — | — | — |
| `notebook/readNotebookCellOutput` | R | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | — | — | — | — |
| `notebook/runNotebookCell` | X | — | — | — | — | ✅ | ✅ | ✅ | — | — | — | — |
| `notebook/configureNotebook` | X | — | — | — | — | ✅ | ✅ | ✅ | — | — | — | — |
| `notebook/configurePythonNotebook` | X | — | — | — | — | ✅ | ✅ | ✅ | — | — | — | — |
| `notebook/restartNotebookKernel` | X | — | — | — | — | ✅ | ✅ | — | — | — | — | — |
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

## Excluded Tools — Rationale

| Tool | Why Excluded | Risk if Included |
|---|---|---|
| `notebook/createNewJupyterNotebook` | New notebooks are architectural decisions (entry points). Human decides. | Unreviewed entry points, scope creep |
| `notebook/notebookInstallPackages` | Installs inside kernel, bypasses `requirements-dev.txt` and dep-tracking workflow. | Untracked dependencies, venv/kernel drift |
| `notebook/notebookListPackages` | Kernel packages should match venv. Use `pip: install` tasks. | Encourages kernel-level management |
| `notebook/configureNonPythonNotebook` | Project is Python-only. No use case. | Confusion, wasted tokens |
| `execute/runInTerminal` (for workers) | Workers use `runTests` / `runTask` / `createAndRunTask`. Only coordinator has terminal. | Ad-hoc commands bypass quality gates |

## Tool Assignment Principles

1. **Least privilege** — agents get only tools needed for their role
2. **Tasks over terminal** — predefined tasks (`run_task`) before ad-hoc terminal
3. **Read before write** — critics and planners get read-only subsets
4. **Dep-tracking integrity** — no tool that installs packages outside the spec file workflow
5. **Kernel = venv** — kernel management happens via venv tools; `restartNotebookKernel` is the only kernel-specific tool (for reload after code changes)

## How to Use This Document

- **Coordinator:** consult the matrix to decide which agent can handle a task
  involving specific tools (e.g., "who can edit notebooks?" → implementer,
  refactorer, documenter)
- **Agents:** check your column to confirm you have the tool before attempting
  to use it; if not, report BLOCKED and let the coordinator delegate
- **Humans:** use the Excluded Tools table to evaluate new tools — if the
  exclusion rationale no longer applies, add the tool to the relevant agents
  and update this matrix
