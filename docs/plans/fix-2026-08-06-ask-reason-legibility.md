<!-- copilot:generated | documenter | 2026-08-06 -->

# Fix: ask-tier confirmations were one unanswerable sentence (issue #78, part b)

- **Status:** COMPLETED
- **Issue:** [#78](https://github.com/sefalk/AgenticAIGovernance/issues/78)
- **Branch:** `agent/78-ask-reason-legibility`
- **Complexity tier:** Small
- **Date:** 2026-08-06

## Problem

All eleven TIER 3 rules emitted the same string:

> This command makes a durable change. Please confirm it is intentional.

`git merge`, `git checkout`, `git tag`, `pip install`, `conda remove`,
`ruff format`, `databricks … deploy`, `az … delete`, `Remove-Item`, `rm`,
`mkdir` — one prompt for all of them, naming neither the rule that fired nor
the command it fired on. The deny tier next door has always been specific
(`Policy hard-deny: force push (remote history rewrite)`), which makes the
asymmetry the clearest evidence that this was an omission rather than a design.

A confirmation prompt is a question put to a human. A question that does not
say what it is about cannot be answered — it can only be waved through. That
turns the confirmation into a keystroke and the gate into noise, which is the
same failure the deny-tier false positives in #62 produce from the other side.

## Change

1. Each ask rule carries its own reason, stating the actual effect rather than
   the category.
2. The command line is echoed in the reason, whitespace-collapsed and capped at
   300 characters (an unbounded string in a dialog is its own way of hiding
   information).
3. `block-dangerous.sh` escapes the reason before interpolating it into its
   hand-built JSON — in both of its emitters, `emit` and `emit_task`.

Point 3 is not cosmetic. The bash hook builds its response with `printf`, and
the reason now carries the command's own quotes and backslashes —
`Remove-Item "C:\tmp\a b\file.txt"` would have produced invalid JSON. VS Code
cannot parse that, so the hook would have fallen silent at exactly the moment
it had something to say: a #68-class defect introduced by a wording change.
PowerShell goes through `ConvertTo-Json` and was never exposed, which is why
the asymmetry had to be checked rather than assumed.

Checking that asymmetry turned up a second, pre-existing instance of the same
bug. The task branch has its own emitter, `emit_task`, which built JSON with a
heredoc — and its deny reasons quote the offending task command back at the
reader, because a deny that will not say what it denied is the very thing this
issue is about. A task command is a path, and on Windows a backslash path:
`C:\evil\run.ps1` yields `\e`, which is not a valid JSON escape. So the task
tier could already silence its own deny, and unlike the ask tier it did not
need a wording change to get there. It is fixed here because it is the same
defect in the same file, found by the same question.

## Deliberately not in this change

Part (a) of the issue — narrowing the ask tier so that generic durable-change
rules return `{}` and Copilot's own assessment renders instead — is a policy
decision about auto-approval, not a wording fix. `{}` defers to the user's
`chat.tools.terminal.autoApprove` settings, so it can mean *no prompt at all*
on a machine whose settings we have never seen. That has to be decided rule by
rule and is tracked separately on the issue.

## Files

| File | Change |
|---|---|
| `hooks/scripts/block-dangerous.ps1` | `$askRules` becomes pattern + reason; command echoed |
| `hooks/scripts/block-dangerous.sh` | `ask_reasons` array; `emit` and `emit_task` escape the reason |
| `scripts/test-hooks.ps1` | `Assert-AskReason` + 7 cases |
| `scripts/test-hooks.sh` | `ask_reason` helper + 8 cases |
| `CHANGELOG.md` | entry |

## Verification

`test-hooks.ps1`: 133 → 140, 0 failed. `test-hooks.sh`: 41 → 49, 0 failed.

Mutation: restoring the single generic sentence in the PowerShell hook reddens
5 of the 6 ask-reason cases (the sixth asserts JSON validity, which the generic
string also satisfies — it is there for the bash escaping).

The two JSON-validity cases were mutation-tested against the bash hook
directly, since that is the side that hand-builds the response. Reverting
`emit` to raw interpolation makes `Remove-Item "C:\tmp\a b\file.txt"` emit
`"…Command: Remove-Item "C:\tmp\a b\file.txt""` — unparsable. Reverting
`emit_task` makes the denied task command `C:\evil\run "it".ps1` unparsable in
the same way. In both cases the hook exits 0 with a well-formed-looking line
that no consumer can read, which is why a green suite alone would not have
caught it.

Two cases guard the construction rather than the behaviour: the bash reasons
live in an array index-aligned with the patterns, so the suite asserts the two
arrays have the same non-zero length, and one case asserts that two different
rules do not return the identical payload — the defect itself, stated as a
test.
