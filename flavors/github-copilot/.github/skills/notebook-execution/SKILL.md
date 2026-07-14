---
name: notebook-execution
description: Interact with Jupyter / .ipynb notebooks through the VS Code notebook tools (run/edit cells, select kernel, read outputs) instead of terminal scripts. Use when a task involves executing, editing, or inspecting notebook cells.
argument-hint: '[notebook.ipynb] [action: run|edit|inspect|configure]'
disable-model-invocation: true
metadata:
  activation:
    agents: [coordinator, implementer, refactorer, code-critic, test-writer]
    priority: required
---

# Notebook Execution Skill

Guidance for working with local Jupyter notebooks (`.ipynb`) in VS Code. The
central rule: **use the dedicated notebook tools — never shell out to the
terminal to run or fabricate notebook cells.**

## When to Use

- Executing one or more cells of an `.ipynb` notebook
- Adding, editing, or reordering notebook cells
- Selecting or configuring the kernel / Python environment for a notebook
- Inspecting notebook structure or reading a cell's output

## Cardinal Rule — notebook tools over the terminal

A notebook is **not** a script. Running `python file.py`, `jupyter nbconvert
--execute`, `papermill`, or writing a throwaway `.py` and executing it in the
terminal does **not** exercise the notebook's cells, kernel state, or outputs —
it fakes them and drifts from what the user sees. Always drive the notebook
through the notebook tools instead.

## Tool Map

| Need | Tool |
|---|---|
| Inspect cells / ids / languages / output metadata | `read/getNotebookSummary` |
| Read a specific cell's output | `read/readNotebookCellOutput` |
| Create / edit / reorder cells | `edit/editNotebook` |
| Run a cell (and capture its output) | `execute/runNotebookCell` |
| Select / configure the kernel | `ms-toolsai.jupyter/configureNotebook` |
| List packages in the kernel environment | `ms-toolsai.jupyter/listNotebookPackages` |
| Select / configure the Python environment | `ms-python.python/configurePythonEnvironment` |

## Workflow

1. **Inspect** — `getNotebookSummary` to learn the cell layout before touching anything.
2. **Configure** — ensure a kernel / Python env is selected (`configureNotebook`,
   `configurePythonEnvironment`) if execution is needed.
3. **Edit** — use `editNotebook` to add or change cells (never hand-edit the
   `.ipynb` JSON).
4. **Run** — use `runNotebookCell`; read results with `readNotebookCellOutput`.
5. **Report** — refer to cells by **number** (starting at 1) to the user, never by cell id.

## Anti-Patterns (do NOT do)

- Writing a `.py` script and running it in the terminal to "execute the notebook logic".
- `jupyter nbconvert --execute` / `papermill` as a substitute for `runNotebookCell`
  (only acceptable for an explicit headless-CI requirement, not for interactive work).
- `Set-Content` / `echo >` to fabricate or overwrite a notebook instead of `editNotebook`.
- Editing raw `.ipynb` JSON by hand.
- Trying to "execute" markdown cells — markdown cells are not runnable.

## Delegation (coordinator)

The **coordinator has only the read-only notebook tools** (`getNotebookSummary`,
`readNotebookCellOutput`). It **must not** improvise terminal scripts to run or
edit notebooks — **not even for trivial actions**. Any notebook execution or
editing is delegated to a subagent with the full notebook toolset:

| Need | Delegate to |
|---|---|
| Run / edit notebook cells (feature work) | `implementer` |
| Clean up / restructure a notebook (behaviour-preserving) | `refactorer` |
| Execute a notebook to verify / review | `code-critic` |
| Inspect a notebook to write tests | `test-writer` |

## Notes

- **Output hygiene:** when `NOTEBOOKS_ENABLED=true` in `af-env.conf`, the
  `nbstripout` git filter strips cell outputs from git — do not fight it by
  committing outputs.
- **Scope:** this skill is for **local `.ipynb`** notebooks in VS Code.
  Databricks notebooks stored as `.py` (source format) are edited as ordinary
  Python files; for **remote** Databricks job/notebook runs use the
  `databricks-execution-patterns` skill instead.
