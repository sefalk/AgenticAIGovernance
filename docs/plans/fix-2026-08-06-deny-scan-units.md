<!-- copilot:generated | documenter | 2026-08-06 -->

# Fix: the deny gate reads quoted data as commands (issue #62)

- **Status:** COMPLETED
- **Issue:** [#62](https://github.com/sefalk/AgenticAIGovernance/issues/62)
- **Branch:** `agent/62-deny-scan-units`
- **Complexity tier:** Standard
- **Date:** 2026-08-06

## Problem

`block-dangerous` matched every deny pattern against the raw command line. A
command line is not one string: it is a sequence of statements, some of whose
quoted arguments are data the agent is *passing*, not commands it is *running*.
Matching the raw text erases that distinction, so the gate objected to text.

Three false denies were observed in a single session:

1. A read-only probe piping JSON into a hook, where the JSON contained
   `Remove-Item -Recurse -Force` as **test data**.
2. The same harness carrying a force-push string as an inert fixture.
3. `git add <file> ; git commit -m "…the negated guard sm --force…"`.

The third is the worst shape of the bug. The rule

```
git\s+add\s+(\S+\s+)*(--force|-f)(\s|$)
```

has `(\S+\s+)*`, which matches a `;` like any other non-space run. So a genuine
`git add` in one statement joined up with prose in the next, and the gate denied
a commit whose message described the gate. The message had to be reworded to
get the work through.

A false deny is not a harmless over-reaction. It spends the same currency as a
false allow, in the other direction: it teaches the agent that the gate is
noise, and hands work back to the human for no security gain.

## Why the obvious fix is wrong

Stripping quotes before the deny scan — which is what the ASK tier already does
via `stripped_guard` — would blind the gate to the case it exists for. The
payload of `bash -c "rm -rf /"` lives inside quotes and *is* executed. Quote
stripping is only safe where the quoted text is unambiguously prose.

## Change

The unit of matching changes; no threshold or rule text changes.

1. **Segment.** The command line is split into top-level statements on
   `; && || |` and newlines, quote-aware. Each statement is scanned on its own,
   so no rule can span a separator. This alone fixes case 3.
2. **Classify quoted arguments by position.** Quoted text is dropped only for
   *data carriers*: `echo`, `printf`, `Write-Host|Output|Error|Verbose|Debug`,
   `git commit|tag|notes|stash`, and a segment that is nothing but a quoted
   literal (case 1, JSON on stdin). Everything else keeps its quotes.
3. **Promote payloads.** The quoted argument of `-c`, `--command`, `-Command`,
   `-e`, `--eval`, `-ScriptBlock`, `-ArgumentList`, `-Args`, `/c`, `/k`, `iex`,
   `Invoke-Expression`, `eval` is executed, so it becomes a scan unit of its
   own and is re-split. This *strengthens* the gate: `powershell -Command
   "git add -A"` never matched `-A(\s|$)` while the closing quote was still
   glued to the argument.
4. **Quotes lose protection when the shell reaches inside them.** A segment
   containing `$(` or a backtick is never stripped.
5. **Keep a raw backstop.** Three rules are about structure rather than a
   statement and stay scoped to the whole line: `| bash|sh|iex|Invoke-Expression`,
   `DROP TABLE|DATABASE`, `TRUNCATE TABLE`. Destructive SQL is deliberately
   raw — SQL clients take it as a quoted argument, and a false deny on a commit
   message mentioning `DROP TABLE` is the lesser evil.

TIER 2 (segment allow) and TIER 3 (ask) are unchanged. Making the *ask* tier
articulate is issue #78 and is deliberately not mixed in here.

## Files

| File | Change |
|---|---|
| `hooks/scripts/block-dangerous.ps1` | `Get-ScanUnits` / `Test-AnyUnit`; deny rules gain a `raw` scope flag |
| `hooks/scripts/block-dangerous.sh` | shared `SPLIT_PY` splitter with `segments`/`units` modes; `matches_unit`; `deny_patterns_raw` |
| `scripts/test-hooks.ps1` | `Assert-NotDeny` + 12 cases |
| `scripts/test-hooks.sh` | `notdeny` expectation + 10 cases |
| `CHANGELOG.md` | entry |

The bash TIER 2 segmenter was an inline Python program duplicating the same
split; it now calls the shared splitter in `segments` mode, so the two tiers
cannot drift apart in how they read a command line.

## Verification

`test-hooks.ps1`: 133 → 145, 0 failed. `test-hooks.sh`: 41 → 51, 0 failed.

Mutation runs, to show the new cases bind to the gate rather than to a fixture:

| Mutation | Expected red | Observed |
|---|---|---|
| `$scanUnits = @($command)` (no segmentation, no stripping) | the 4 false-deny cases | 4 red |
| `$payloadRe` neutralised (no payload promotion) | the 2 promotion cases | 2 red |

The second mutation is the interesting one: the other payload cases
(`bash -c "rm -rf /tmp/data"`, `Invoke-Expression "…"`) survive it, because the
segment keeps its quotes and `rm\s+-r[f ].*(\s|=)(/|~|\*)` matches inside them
anyway. Only the rules anchored on end-of-argument need the promotion. Without
that mutation the promotion code would have shipped untested — which is the
same class of defect as the issues this branch follows.

## Residual risk

- The data-carrier list is an allowlist and will need extending (a new
  logging command, a new `git` subcommand that takes a message). Missing an
  entry costs a false deny, not a false allow.
- Payload promotion recognises flags by name. An interpreter invoked with an
  unlisted flag keeps its quotes and is still scanned as one segment, which is
  the pre-existing behaviour, not a regression.
