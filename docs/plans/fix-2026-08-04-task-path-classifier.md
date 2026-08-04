# Fix: classify the task execution path (#56)

<!-- copilot:generated | planner | 2026-08-04 -->

- **Created:** 2026-08-04
- **Issue:** [#56](https://github.com/sefalk/AgenticAIGovernance/issues/56)
- **Branch:** `agent/56-task-path-classifier`
- **Complexity tier:** Deep
- **Status:** IN PROGRESS

## The measured defect

`block-dangerous.*` filters on the tool name before anything else:

```powershell
if ($toolName -notmatch 'terminal|Terminal') { ...no opinion... }
```

The same command in two shapes, against the deployed hook:

| Payload | Verdict |
|---|---|
| `runInTerminal` + `git push --force origin main` | **deny** |
| `createAndRunTask` + `{command: "git", args: ["push","--force","origin","main"]}` | **`{}`** — allowed |

The entire hard-deny tier is unenforced through the task path. `coordinator-pretooluse.*`
(commit-message format, staging checks) and `coordinator-posttooluse.*` share the filter.

## Root cause: the instruction points at the ungated path

This is not an agent circumventing a rule. `coordinator.agent.md` working rule 3
reads **"Prefer tasks over terminal"** and orders the ladder
`run_task → createAndRunTask → terminal`. `TOOLS.md` repeats it as a principle.
The exception that would have prevented every observed violation — *"reserve
terminal for git commands"* — is a subordinate clause at the end of the same
paragraph, competing with the bolded heading above it.

So the framework instructs the coordinator to prefer the one path no hook
inspects. Closing the classifier gap without fixing the instruction leaves an
instruction pushing agents at a door we just locked.

### Was there a sanctioned path? Per observed task family

| Family | Sanctioned path | Verdict |
|---|---|---|
| `git: stage/commit …` | Yes — terminal, named in rule 3 | Existing path bypassed |
| `git: show <sha>`, `diff gitignore`, `status porcelain` | Yes — terminal; `git: status` label already existed | Bypass + duplication |
| `databricks: run / cancel / poll` | Yes — terminal | Bypass; irreversible remote ops, unclassified |
| `tests: <one file>` | Yes — `runTests(files=[…])`, documented one line above | Wrong rung taken |
| `lint: <one file>` | **No** | **Genuine gap** — no parameterised lint entry point exists |

One genuine gap out of five. A blanket ban costs almost no legitimate
capability — provided the gap is filled first.

### Why 19 ad-hoc entries accumulated

`run_task` cannot take arguments. A Databricks run id is a dynamic value, so
every poll, fetch and cancel needed its own task with the id **encoded into the
label**. The count is the arithmetic of a parameterless path meeting a
parameterised need, not carelessness.

## Design decision: allowlist the command, do not blocklist the payload

The issue originally proposed reconstructing the effective command line from
`task.command + task.args` and running it through the existing segment
classifier. That is a blocklist. Rejected in favour of an **allowlist**:

> `createAndRunTask` may only invoke a **tracked script under a declared script
> directory** (`AF_TASK_SCRIPT_DIRS`, default `.github/scripts`). Arguments are
> free. Everything else is denied: bare binaries (`git`, `databricks`, `ruff`),
> `powershell -Command "<string>"`, and `-File <path outside the script dir>`.

Reasons:

1. A blocklist must anticipate every dangerous command. The allowlist answers
   one question: is this a reviewed repo script?
2. It kills `powershell -ExecutionPolicy Bypass -File %TEMP%\x.ps1`
   **structurally**. No blocklist can — the payload is not in the task.
3. It relocates review from an untracked file to a versioned script. Today the
   *behaviour* lives in `.vscode/tasks.json`; afterwards the behaviour lives in
   a reviewed script and only the arguments vary.
4. It makes the preference order defensible instead of arbitrary: each rung adds
   freedom and all rungs share one classification.

**Consequence that reduces scope:** with `command: "git"` denied outright, the
task path cannot run git at all. `coordinator-pretooluse` therefore needs **no**
task-shape mirror of the commit-message and staging gates — there is nothing left
for them to catch. Only the deny has to be proven (subtask 1).

### Rejected alternatives

- **Withdraw `createAndRunTask` from the coordinator.** Proposed and retracted.
  The tasks-over-terminal rule exists because the coordinator previously used the
  terminal to bypass everything; the task path was adopted for traceability.
  Removing the tool regresses to that. The two paths each hold one of the two
  properties needed — terminal is *classified*, task leaves an *artifact* — and
  the fix is to give the task path the missing one, not to delete it.
- **Pass arguments via environment variables.** Moves the problem somewhere
  worse: the payload would show `run-databricks.ps1` while the effective
  behaviour lives elsewhere — the `-File %TEMP%` failure mode in nicer clothes.
  And the variable would be set from a terminal.
- **Track `.vscode/tasks.json`.** Listed as item 4 in the issue; retracted here.
  Either encoding is bad once tracked: a unique label per invocation turns the
  file into a history, a stable label turns every call into churn on a tracked
  file. More decisively, the traceability it was supposed to buy **never
  materialised** — the file is `.gitignore`d in the downstream project (line 158)
  and has never appeared in a diff, PR or review.

### Where each property actually lives

| Question | Answer | Surface |
|---|---|---|
| What *can* run? | The set of reviewed scripts | `.github/scripts/` — tracked |
| What *did* run? | Every tool call with full payload, timestamped, per agent | Debug logs |
| What is `tasks.json`? | Curated `run_task` labels plus scratch | Cache, not an artifact |

Evidence for the third row: the entire history behind this issue — which agent
did what, the subagent that wrote a task into `tasks.json` while verifying that
same file, the 19-entry cleanup — was reconstructed from the **debug logs**.
`tasks.json` held only the post-cleanup end state.

## Stopgap notice

This is a patch on a tool whose shape is wrong. `createAndRunTask` is a *call*
wearing the costume of a *definition*: it writes a task file on every
invocation, and that side effect is inherent. The target state — a standalone
command registry tool with agent-supplied, schema-validated arguments, distinct
from the terminal tool — is recorded as
[#60](https://github.com/sefalk/AgenticAIGovernance/issues/60). This work is its
prerequisite, not competition: #60 replaces the *transport*, and keeps the
tracked script directory that this issue establishes as the *surface*.

## Subtasks

### 1. Red — deny tests in task shape

Mirror the full hard-deny tier in `createAndRunTask` shape in
`.github/scripts/test-hooks.ps1`, plus the three shapes the allowlist must
reject structurally.

**Acceptance criteria**
- Every hard-deny case asserted in `runInTerminal` shape has a `createAndRunTask`
  twin: force push, push to a protected branch, `reset --hard`, `rebase`,
  `branch -D`, `rm -rf`, `--no-verify`.
- Deny asserted for: `command` a bare binary; `powershell -Command "<string>"`;
  `-File` resolving outside `AF_TASK_SCRIPT_DIRS`.
- Deny asserted for any `${input:` occurrence in a task payload.
- Allow asserted for `.github/scripts/run-tests.ps1 -Scope domain` and the other
  existing curated invocations — the gate must not break legitimate runs.
- All new assertions fail against the current hooks, for the stated reason.

**Empirical probes to resolve in this phase** (documented, not assumed):
- Does `createAndRunTask` with a repeated label replace the entry or duplicate it?
- Do `isBackground` / `problemMatcher` carry long-running invocations usefully?

### 2. Green — allowlist in `block-dangerous.ps1` and `.sh`

**Acceptance criteria**
- Tool-name filter widened to task-shaped payloads.
- `command` must resolve, after path normalisation, inside a directory listed in
  `AF_TASK_SCRIPT_DIRS`; anything else denies.
- Interpreter invocations with an external payload (`-File`, `-c`, a script path
  argument) deny unless the payload itself resolves inside the allowlisted set.
- Unrecognised payload shape denies (fail closed), with a reason string naming
  the sanctioned alternative.
- Both shells behave identically; the `.sh` is asserted by the same table.

### 3. Green — fill the one real gap

**Acceptance criteria**
- `run-lint.ps1` accepts `-Scope changed`, linting the branch delta against
  `BASE_BRANCH` — the same set the stop hooks already compute.
- A `lint: changed files` label exists in the payload `tasks.json`.
- Documented in `skills/test-execution/SKILL.md` and the metrics skill table.

### 4. Green — fix the incentive

**Acceptance criteria**
- `coordinator.agent.md` rule 3 rewritten: the two tools are described as
  different things (parameterless entry points vs parameterised calls into the
  same reviewed surface), not as rungs of a freedom ladder. The git/terminal
  reservation is promoted out of the trailing clause.
- `TOOLS.md`: the "tasks over terminal" principle reworded, and the
  `execute/runInTerminal` rationale row updated so it no longer claims a
  restriction the task path used to undo.
- `testing.instructions.md`: the "avoids terminal confirmation" framing removed
  or qualified — in a framework where only some paths are classified, "avoid the
  terminal" reads as "avoid the gate".
- `tooling.instructions.md`: `${input:…}` banned for agent-run tasks (it blocks
  on a prompt); the label identifies the *script*, never the invocation;
  `tasks.json` is a cache, not an audit trail.
- `AF_TASK_SCRIPT_DIRS` documented in `af-env.conf`.

### 5. Green — scratch hygiene

**Acceptance criteria**
- A workflow-end check reports scratch labels remaining in `.vscode/tasks.json`
  beyond the curated set.

*Drop first if scope grows.* The allowlist removes most of the pressure by
construction: one script invoked with varying arguments replaces N labels.

## Risks

| Risk | Severity | Mitigation |
|---|---|---|
| The allowlist breaks legitimate task runs | High | Subtask 1 asserts every existing curated label still passes, before the allowlist lands |
| Path normalisation differs between PowerShell and bash, so the two shells disagree | Medium | One assertion table drives both; symlink and `..` traversal cases included |
| Downstream projects have scripts outside `.github/scripts` | Medium | `AF_TASK_SCRIPT_DIRS` is a list; MP's `scripts/` is the known second entry |
| Agents lose a capability they actually need and route around it again | Medium | Subtask 3 fills the one measured gap; the per-family table above bounds what else could be missing |
| Rewriting rule 3 changes coordinator behaviour in ways not covered by hook tests | Medium | Instruction changes are SOFT-gated; the hard boundary is the hook, which is tested |

## Change log

| Date | Change |
|---|---|
| 2026-08-04 | Plan created. Root cause identified as an instruction/enforcement conflict, not agent misbehaviour. |
| 2026-08-04 | Blocklist approach from the issue replaced by an allowlist on `command`. |
| 2026-08-04 | "Track `tasks.json`" (issue item 4) retracted — the traceability it assumed never existed. |
| 2026-08-04 | Recorded as a stopgap for #60. |
