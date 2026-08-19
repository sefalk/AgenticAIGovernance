# Fix: classify task launches at creation and at execution (#74)

<!-- copilot:generated | documenter | 2026-08-06 -->

- **Created:** 2026-08-06
- **Issue:** [#74](https://github.com/sefalk/AgenticAIGovernance/issues/74)
- **Branch:** `agent/74-task-launch-classification`
- **Complexity tier:** Standard
- **Status:** COMPLETED

## The defect

A task is a second way to execute a command line. `block-dangerous` guarded
that path with a name VS Code never sends.

| Gate | Matched | Actually sent | Effect |
|---|---|---|---|
| Creation | `createAndRunTask` | `create_and_run_task` | The whole allowlist from #56 never ran once in production. |
| Execution | — | `run_task` (14 captured events) | Not classified at all. |

The creation allowlist was not weak — it denies bare binaries, checks
interpreters by their payload, catches OS-scope decoys and `options.shell`
overrides. It was simply addressed to nobody. This is the same defect as #69,
one gate over: the name was written from an assumption about the tool rather
than read off a captured payload.

`run_task` was the worse half. Its payload is `{id, workspaceFolder}` — a
name, and a name is not a command. The command lives in the project's
`.vscode/tasks.json`. A task running `git push --force` therefore launched
with the classifier none the wiser, and `run_task` is the tool the framework
*pushes agents towards*: workers have no terminal and are told to reach
reviewed scripts through tasks. The safer path was the unguarded one.

## Payload shapes, from ground truth

Per #69, no shape here is invented.

| Tool | Shape | Source |
|---|---|---|
| `run_task` | `{id, workspaceFolder}` | 14 captured PreToolUse events |
| `create_and_run_task` | `{task: {label, type, command, args?, group?, isBackground?, problemMatcher?}, workspaceFolder}` | The tool's declared input schema — **no captured events exist** |

The second row is schema-derived, not capture-derived, and is labelled as such
in the code. It is the best evidence available, and weaker than the first.

One detail only the captures could have supplied: VS Code addresses a task as
`{type}: {label}`, so the ids look like `shell: tests: all`. Matching the bare
label alone would have left every real launch unresolved — the gate would have
answered `ask` for everything and been switched off within a day.

## Decision: two gates, different in kind

The human decision on this issue was blocklist semantics (option b) checked at
**both** points. The two checks are deliberately not the same check:

- **Creation** (`create_and_run_task`) keeps the **allowlist**. The agent is
  authoring the task, so it must point at a reviewed script under
  `AF_TASK_SCRIPT_DIRS`.
- **Execution** (`run_task`) uses the **blocklist** — the same three tiers as a
  terminal command. `tasks.json` is human-authored and legitimately calls
  `git`, `pytest`, `databricks` and `powershell -File` against one-off scripts.
  An allowlist there would deny nearly every real task in a real project.

Both are checked because the danger can enter at either point, and the two
points fail differently:

- A task can be smuggled into `tasks.json` by a plain file edit that never
  touches the creation gate. Execution-time classification catches it.
- A task that was acceptable when it was written may not be acceptable now.
  `PROTECTED_BRANCHES`, `AUTONOMY_LEVEL` and the `AUTONOMY_CAT_*` categories
  all move underneath a `tasks.json` that does not change. Classifying only at
  creation would freeze a verdict against a policy that has since moved.

## Implementation

`run_task` is resolved into a command line *before* the tiers run, so the
existing classifier is reused rather than reimplemented:

1. Read `{workspaceFolder}/.vscode/tasks.json`.
2. Find the task whose `label` matches the id, or the id with its first
   `{type}: ` prefix stripped.
3. Reconstruct `command + args` for the task scope **and** every
   `windows`/`linux`/`osx` override present.
4. Join the scopes with newlines. The deny tier scans line by line and the
   allow tier already splits on newlines, so every scope must clear the bar
   independently — an OS override cannot ride in behind a benign `command`.

Everything unresolvable answers **`ask`**, never silence: no `tasks.json`,
JSONC instead of strict JSON, an unknown label, an `${input:}`/`${command:}`/
`${config:}` variable, an `options.shell` override, or a composite task with no
command of its own. Per #68, silence is what a gate that cannot judge and a
gate with no objection have in common. `ask` says which one this is.

## Evidence

- **Red first (PowerShell):** all 9 new cases failed, every one of them with
  `silent` and `{}` — the signature of a gate that never saw the request.
- **Green:** `test-hooks.ps1` 124 → **133 passed / 0 failed**; `test-hooks.sh`
  36 → **41 / 0**. The 25 pre-existing creation cases stay green: the allowlist
  behaviour is unchanged, it is now merely reachable.
- **Mutation (bash):** the bash cases were written after the implementation, so
  a green run proves little. Removing `run_task` from the accepted tool names
  turned exactly the 4 `run_task` cases red — all four reporting `{}`. The
  tests bind to the gate, not to the fixture.
- **No regressions:** `test-hooks-integration.ps1` 7/7 "HOOKS ARE WORKING";
  `test-lint-gate.ps1` 21/21; both harnesses exit 0.

## Residual gap

A task carrying `runOptions.runOn: folderOpen` written straight into
`tasks.json` by a file edit runs on the next folder open without passing
either gate. The creation gate hard-denies `folderOpen`, but only for tasks it
sees. Closing this means classifying partial edits to `tasks.json` — a
different problem, and one better solved by watching the file than by parsing
diff fragments. Not attempted here; recorded so it is a known gap rather than
an assumed absence.
