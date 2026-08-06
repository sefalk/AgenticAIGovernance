# Fix: every write gate matched tool names VS Code never sends (#69)

<!-- copilot:generated | documenter | 2026-08-06 -->

- **Created:** 2026-08-06
- **Issue:** [#69](https://github.com/sefalk/AgenticAIGovernance/issues/69)
- **Branch:** `agent/69-payload-ground-truth`
- **Complexity tier:** Standard
- **Status:** COMPLETED

## The measured defect

#64 was a single hook reading `url` where the tool sends `urls`. The question
this issue asked was whether that was one mistake or a habit. It was a habit.

The evidence is the chat debug log, which records every hook invocation with
the verbatim stdin payload and the verbatim response: **1935 hook events across
25 files**. What VS Code actually sends:

| Tool name | `tool_input` keys |
|---|---|
| `create_file` | `content`, `filePath` |
| `replace_string_in_file` | `filePath`, `newString`, `oldString` |
| `multi_replace_string_in_file` | `explanation`, `replacements` |
| `read_file` | `filePath`, `startLine`, `endLine` |
| `run_task` | `id`, `workspaceFolder` |
| `run_in_terminal` | `command`, `explanation`, `goal`, `mode` |

Not one occurrence of `editFiles`, `createFile`, `createDirectory`,
`editNotebook`, `writeFile` or `createAndRunTask` — the names four hooks were
matching on. The recorded responses say the rest:

```
block-dangerous.ps1,        replace_string_in_file       -> {}   (37x)
block-dangerous.ps1,        multi_replace_string_in_file -> {}   (25x)
block-dangerous.ps1,        create_file                  -> {}   (10x)
block-dangerous.ps1,        run_task                     -> {}   (14x)
coordinator-pretooluse.ps1, run_task                     -> {}   (14x)
```

So the coordinator's delegation gate, the test-writer's TDD isolation gate, the
refactorer's no-new-files gate and the secret scan were **inert on every file
edit the agents have ever made**. The only one that partly worked was the
refactorer's creation deny, by accident: `create_file` happens to contain both
`create` and `file`, which was what its substring heuristic looked for.

The two platforms failed in opposite directions, which is why neither showed
up. PowerShell matched camelCase names and therefore **never fired**. Bash used
wildcards so broad (`*edit*|*create*|*write*|*file*`) that `read_file` matched
— the branch gates would have **denied a read** on a non-agent branch.

`multi_replace_string_in_file` adds the second half of the defect: it carries
no top-level `filePath` at all. The paths live one level down in
`replacements[].filePath` — the same nesting that made #64's `urls` invisible.
A gate that reads `tool_input.filePath` sees nothing and lets a batched edit of
twenty production files through without an opinion.

## What changed

| Area | Before | After |
|---|---|---|
| Tool classification | five different matchers, four inert, four over-broad | one `Test-AfWriteTool` / `af_is_write_tool` in `_common` |
| Name matching | camelCase guesses (`.ps1`) / `*file*` wildcards (`.sh`) | captured names, plus a verb+noun heuristic for names not yet seen |
| `read_file` | matched by the bash gates | excluded — no write verb |
| Path extraction | `tool_input.filePath` only | `Get-AfWritePaths` / `af_write_paths`: `filePath`, `path`, `dirPath`, `notebookUri`, `uri` **and** `replacements[].filePath` |
| Batched edits | invisible to every gate | each path checked; the first offender is named in the deny reason |
| Refactorer creation deny | two overlapping substring heuristics | explicit creation-tool list |
| Fixtures | written from the implementation's belief | captured payloads |

The heuristic fallback is deliberate and narrow: a name qualifies if it
contains a write verb (`create|write|edit|insert|apply|replace`) **and** a file
noun (`file|notebook|dir`). `read_file` has the noun but no verb;
`create_and_run_task` has the verb but no noun. Both stay out.

### Two further defects found in the bash secret scan

Restructuring `scan-secrets.sh` for multiple paths exposed two bugs that had
nothing to do with tool names and everything to do with the same theme:

1. **The gitleaks verdict was discarded.** `result=$(gitleaks detect ...) ||
   true` followed by `if [ $? -ne 0 ]` tests the exit code of `true`, not of
   gitleaks. A detection was reported as a pass, always.
2. **The fallback regex could not match.** `[^\s"']{8,}` — inside a bracket
   expression `\` is literal, so the class excluded the letter *s* instead of
   whitespace, and the Generic Secret rule never fired. Since `gitleaks` is not
   installed on this machine, the fallback *is* the live path. Replaced with
   POSIX classes and verified against a probe: CURRENT-REGEX MISS,
   POSIX-REGEX MATCH.

## Subtasks

1. **Evidence — mine the payload corpus.** 1935 hook events extracted from
   `main.jsonl`; the tool × hook × response matrix above posted to #69.
   ✔ [comment](https://github.com/sefalk/AgenticAIGovernance/issues/69#issuecomment-5202220757)
2. **Red — fixtures carry the real shapes.** Every write fixture in
   `test-hooks.ps1` restated with captured tool names and key sets, plus new
   `multi_replace_string_in_file` cases. 14 failures, all of the form
   "expected deny, got 'silent' (exit 0, output: {})". ✔ `10f4379`
3. **Green — PowerShell.** `Test-AfWriteTool` and `Get-AfWritePaths` in
   `_common.ps1`; the four gates rewired. 123 passed / 0 failed. ✔ `2edbdd5`
4. **Green — bash.** `af_is_write_tool` and `af_write_paths` in `_common.sh`;
   the four gates rewired; the two secret-scan repairs; new cases in
   `test-hooks.sh`. 35 passed / 0 failed. ✔ `03c6aec`

## Verification

Green runs prove little here — the suite was green while all of this was
broken. The evidence is the Red phase and a mutation:

| Check | Result |
|---|---|
| Red phase (`test-hooks.ps1` before the fix) | 109 passed / **14 failed**, every failure a gate returning `{}` |
| Mutation: `af_is_write_tool` forced to return false | 26 passed / **9 failed** — the bash cases bind to the classifier, not to the fixture |
| `test-hooks.ps1` | 123 / 0, exit 0 |
| `test-hooks.sh` | 35 / 0, exit 0 |
| `test-hooks-integration.ps1` | 7 checks, "HOOKS ARE WORKING" |
| `test-lint-gate.ps1` | 21 / 21 |
| `bash -n` on all five edited shell scripts | clean |
| Direct bash probe, batched edit containing a secret | `{"gate":"secret-scan","status":"FAIL",...}`, exit 1 |
| Direct bash probe, `read_file` | `{}`, exit 0 |

The bash mutation matters more than the passing count: those cases were written
after the fix and could have been tautological. Nine of them go red when the
classifier is disabled, so they are testing the gate rather than the fixture.

## Scope split

`block-dangerous` matches `createAndRunTask`; the real tools are `run_task` and
`create_and_run_task`, so its task allowlist is inert too. That is **not** a
name repair: `run_task` sends only `{id, workspaceFolder}`, so the command
being launched lives in the project's `.vscode/tasks.json`. Classifying it
means judging a project's existing, human-authored tasks — a policy decision,
not a fix. Split out as
[#74](https://github.com/sefalk/AgenticAIGovernance/issues/74) with three
options for the human to choose from.

## What this says about the framework

Three consecutive defects (#64, #68, #69) are the same defect: **a gate that
cannot run and a gate with nothing to say produce identical output.** #68 gave
the harness the vocabulary to tell those apart, and that is the only reason
this one was findable — under the old `Assert-Allow`, every fixture in the Red
phase would have passed.

The remaining exposure is that hooks are still written against *remembered*
payloads. The corpus mined here is a one-off; nothing keeps it current. A
periodic re-mine, or fixtures generated from captured events rather than typed
by hand, is the structural answer.
