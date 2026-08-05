# Fix: classify the task execution path (#56)

<!-- copilot:generated | planner | 2026-08-04 -->

- **Created:** 2026-08-04
- **Issue:** [#56](https://github.com/sefalk/AgenticAIGovernance/issues/56)
- **Branch:** `agent/56-task-path-classifier`
- **Complexity tier:** Deep
- **Status:** COMPLETED

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

**Scope widened** — see *In-flight confirmation* above. The behaviour is not
coordinator-specific, so a fix confined to `coordinator.agent.md` would miss the
agents that actually produced the specimen.

**Acceptance criteria**
- `coordinator.agent.md` rule 3 rewritten: the two tools are described as
  different things (parameterless entry points vs parameterised calls into the
  same reviewed surface), not as rungs of a freedom ladder. The git/terminal
  reservation is promoted out of the trailing clause.
- Every other agent definition granting `createAndRunTask` carries the same
  framing. The audit is part of the subtask, not an assumption.
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
- `.vscode/` is gitignored in this repo. It is ignored downstream in MP but not
  here, so the scratch file described above was one `git add -A` away from being
  committed as if it were a framework artifact.

*Drop first if scope grows.* The allowlist removes most of the pressure by
construction: one script invoked with varying arguments replaces N labels.

## In-flight confirmation

While subtask 2 was being implemented, the implementer agent — writing the very
classifier that denies `powershell -Command "<inline>"` — created four scratch
tasks in this repo's `.vscode/tasks.json`:

| Label | Shape |
|---|---|
| `test-hooks: block-dangerous` | `powershell -NoProfile -Command "<inline>"` |
| `parse-check: block-dangerous.ps1` | `powershell -NoProfile -Command "<inline>"` |
| `parse-check: block-dangerous.ps1 v2` | `powershell -NoProfile -Command "<inline>"` |
| `test-hooks: final verification` | `powershell -NoProfile -Command "<inline>"` |

All four would be denied by the hook committed in `75f2dc4`. Three things follow,
and none of them were assumptions before this:

1. **The behaviour is not coordinator-specific.** The diagnosis generalises, so
   subtask 4 must cover every agent granted `createAndRunTask`, not just rule 3
   of `coordinator.agent.md`.
2. **The label-churn prediction is confirmed empirically.** `… .ps1` followed by
   `… .ps1 v2` followed by `final verification` is the untracked-history pattern
   the plan predicted from the MP evidence, reproduced here in a single session.
3. **The framework does not enforce its own hooks on itself.** The payload lives
   in `flavors/github-copilot/.github/`; there is no `.github/` at the repo root,
   so no hook was ever consulted for these calls. The enforcement being built
   here is live in MP but inert in AAIG. That is a separate structural gap and
   is out of scope for this fix — it needs its own issue.

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
| 2026-08-04 | Red phase measured: 82 assertions, 67 passed, 15 failed, every failure `output: {}` — the documented defect, not an incidental bug. |
| 2026-08-04 | Green subtask 2 landed and independently verified at 82/0. The `.sh` port is unverified by execution (no bash on this host). |
| 2026-08-04 | In-flight confirmation recorded. Subtask 4 widened beyond the coordinator; subtask 5 gained the `.gitignore` criterion. |
| 2026-08-04 | Verification against the official VS Code tasks documentation found **three bypasses in the code committed at subtask 2** and one false deny. Specification corrected (see below). Fixed and verified at 90/0 plus an independent 11-payload probe set. |
| 2026-08-04 | `.sh` port verified **by execution** after all: Git Bash is present on this host, contrary to the earlier assumption. Running it exposed two pre-existing fail-opens in the hook (interpreter detection, grep pattern passing) that inspection had not. |
| 2026-08-04 | Two structural findings filed as their own issues rather than absorbed here: [#61](https://github.com/sefalk/AgenticAIGovernance/issues/61) (the framework never runs its own hooks) and [#62](https://github.com/sefalk/AgenticAIGovernance/issues/62) (deny patterns match inside quoted data). |
| 2026-08-04 | Subtask 3 landed and verified by execution in a real Python repo — empty and non-empty changed sets, both shells. AAIG has no venv, so the scope could not be exercised in this repo. |
| 2026-08-04 | Subtask 4 landed. Audit found four agents holding `createAndRunTask`; all four now carry the same framing, as do `TOOLS.md`, both instruction files and the test-execution skill. |
| 2026-08-04 | Subtask 5 landed. The scratch audit is a shared Python checker called by both stop hooks — a second pair of parallel implementations was the risk this workflow had already been bitten by. |

## Correction: what the allowlist must actually check

The specification in *Design decision* above was too narrow. It said "allowlist
`command`". `command` is not the executed thing.

Per the tasks documentation, the executed command is a **resolution** over three
inputs, and the classifier must check the result, not the declaration:

| Mechanism | Documented behaviour | Consequence for the classifier |
|---|---|---|
| `windows` / `linux` / `osx` scope | "Properties defined in an operating system specific scope **override** properties defined in the task or global scope." | A benign `command` plus a `windows.command` decoy was classified on the decoy. Every scope present must be classified; one failure denies. |
| `options.shell` | "you can override a task's shell with the `options.shell` property" | The payload moves into the shell's own arguments, invisible to the classifier. Presence denies. |
| `command` in `type: shell` | "If a single command is provided, the task system passes the command **as is** to the underlying shell" (doc example: `chcp 866 && more russian.txt`) | `command` may be a whole command line. Shell metacharacters survive path normalisation, so `…/run-tests.ps1; <anything>` matched the allowlisted prefix. `command` must be a path, not a command line. |
| `${workspaceFolder}` etc. | Variable substitution is supported in `command`, `args` and `options` | Was denied outright — a false deny. Substituted before normalisation; a rooted result is no longer re-joined onto the repo root. |

The corrected rule: **allowlist the effective executable — the resolution over
`command`, the OS override and `options.shell` — and require `command` to be a
path rather than a command line.**

Two of these were found by reading the specification, not by testing, and the
tests that now cover them were written from the specification afterwards. Tests
derived from an implementation can only confirm what the implementation already
believes.

## Defects found by executing the `.sh` hook

Both pre-existing, both fail-open, neither visible by inspection. They are
fixed in the same commit as the port because they sit in the same file.

| Defect | Effect |
|---|---|
| `command -v python3` resolves the 0-byte App Execution Alias under `WindowsApps` on Windows hosts. It is non-empty, so it passed the emptiness check, but executes nothing. | Every `python` call failed silently, so the hook emitted no opinion for **every** command — terminal classification included. The whole hook was inert on that host class. Candidates are now probed for executability. |
| The three matcher helpers passed a caller-supplied pattern to `grep` positionally, so a pattern beginning with a dash was parsed as an option. | The commit-hook-bypass deny rule never matched. The same defect made a negated guard in the branch-deletion auto-approve path always report "no match", weakening an allow rule. Patterns are now passed after `-e`. |

## Outcome

All five subtasks landed. Every acceptance criterion is met, with the one
qualification recorded below.

| # | Subtask | Commit | Evidence |
|---|---|---|---|
| 1 | Red — mirror the deny tier in task shape | `d1ccea1` | 82 assertions, 15 failing for the documented reason |
| 2 | Green — allowlist classifier | `75f2dc4`, `127a026`, `a588d4d` | 90/0; independent probe sets 8/8 (`.ps1`) and 11/11 (`.sh`) |
| 3 | Green — fill the one real gap | `78126a4` | Executed in a real Python repo, both shells |
| 4 | Green — fix the incentive | `f117d83` | Four agents audited, not assumed |
| 5 | Green — scratch hygiene | `ecb75ee` | Checker flags 4/4 real scratch labels, 0 false positives on the curated set |

**Verification that matters more than the counts:** the tests written in
subtask 1 all passed against the subtask 2 implementation, and three bypasses
were still open. What found them was reading the VS Code tasks specification and
deriving payloads from it. What found the two `.sh` fail-opens was executing the
hook. Neither was found by the suite, and the suite was green throughout.

**Qualification on subtask 3.** `-Scope changed` was exercised against the MP
project, because AAIG has no virtual environment and the runner exits before
file collection without one. Both the empty changed set (`files=0`, exit 0) and
a seeded one (`files=1`, lint error surfaced, exit 2) were confirmed, in
PowerShell and bash. The scope has never run inside this repository.

**Not fixed here, deliberately.** The enforcement built in this workflow is live
in deployed projects and inert in AAIG itself ([#61](https://github.com/sefalk/AgenticAIGovernance/issues/61)),
and the deny tier still produces false denies on quoted data
([#62](https://github.com/sefalk/AgenticAIGovernance/issues/62)) — one of which
blocked a legitimate commit during this very workflow. This fix also remains a
stopgap for [#60](https://github.com/sefalk/AgenticAIGovernance/issues/60):
the hook classifies a payload shape, and the durable answer is to stop treating
the two execution paths as different surfaces at all.

**Open empirical questions**, carried rather than answered: whether
`createAndRunTask` with a repeated label replaces or duplicates the entry, and
whether `isBackground` / `problemMatcher` can carry a long-running invocation
past the classifier's assumptions.
