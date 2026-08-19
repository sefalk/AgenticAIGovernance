# Fix: assert that a hook can speak before trusting its silence (#65)

<!-- copilot:generated | documenter | 2026-08-05 -->

- **Created:** 2026-08-05
- **Issue:** [#65](https://github.com/sefalk/AgenticAIGovernance/issues/65)
- **Branch:** `agent/65-hook-parse-gate`
- **Complexity tier:** Standard
- **Status:** COMPLETED

## The measured defect

Two shipped hooks did not parse. Confirmed by execution on `HEAD` before any
change:

```
bash -n coordinator-pretooluse.sh  -> syntax error near unexpected token
bash -n session-mcp-readiness.sh   -> unexpected EOF while looking for matching '"'
```

- `coordinator-pretooluse.sh` embedded `\'git status\'` inside a single-quoted
  string. A backslash does not escape a quote inside single quotes in POSIX
  shell; the string ended early and the rest of the line became syntax.
- `session-mcp-readiness.sh` used `msg_escaped=${msg//"/\"}`. The `"` opens a
  quote that the expansion never closes.

The consequence is not "the hook errors out". A hook that exits non-zero
without writing a decision is read by the agent runtime exactly like a hook
that examined the request and had nothing to say. **The absence of a decision
is how a hook says "no objection."** For as long as the defect existed, the
coordinator's delegation gate, its worktree-branch check and its
commit-message rule permitted everything.

Nothing in either harness asserted that the shipped hooks parse.

## What the behavioural tests then found

A parse gate alone would have declared victory here. It was written first, and
it was not enough: three further defects sat behind the syntax error, each with
the same signature — the hook runs, decides nothing, and looks compliant.

| # | Defect | Effect |
|---|---|---|
| 1 | Outer `case "$TOOL_NAME" in *terminal*)` | `case` is case-sensitive and VS Code sends `runInTerminal`. The whole terminal branch was unreachable. The *inner* `case` one screen below already spelled both cases — a copy that was only half-corrected. |
| 2 | `echo "$CMD" \| python << 'PYEOF'` | The heredoc **is** python's stdin, so the pipe is discarded and `sys.stdin.read()` returns `''`. The commit message was always empty and the gate never fired. `coordinator-postmerge.sh` carried the identical collision and always reported "No active agent/* worktrees". |
| 3 | `^\[agent:[^\]]+\]` | A backslash is literal inside an ERE bracket expression, so the pattern demanded two closing brackets. It matched no well-formed commit message. Invisible while the hook was unparsable; immediate once it ran. |

Defect 3 was only observable *after* defects 1 and 2 were repaired — each layer
of silence hid the next.

## Subtasks

1. **Red — parse gate.** `test-hooks.ps1` §9 tokenizes every `.ps1` through
   `[System.Management.Automation.PSParser]::Tokenize` and shells out to
   `bash -n` for the `.sh` side when bash is available (skipping with a notice
   otherwise, since `test-hooks.sh` covers it). `test-hooks.sh` runs `bash -n`
   over every shipped hook. Both went red on exactly the two known files.
   ✔ `e3dd0f8`
2. **Red — behavioural coverage.** Cases for the coordinator gate (direct file
   edit denied, `pytest` via terminal denied, phase-only commit message denied,
   described message passes) and for `session-mcp-readiness.sh` (emits a
   `SessionStart` payload with `additionalContext`). The coordinator hook's
   whole purpose is delegation enforcement and nothing exercised it — which is
   how it stayed silent without a single red test. ✔ `b1cf835`
3. **Green — the two syntax repairs.** `'\''git status'\''` for the quoted
   string; a `sed` pipeline for the readiness escaping, backslashes before
   quotes so the escape this step introduces is not re-escaped.
   ✔ `7558bd8`, `6f051d0`
4. **Green — the three silent defects.** `*terminal*|*Terminal*`; payloads
   passed through the environment (`AF_RAW_COMMAND`, `AF_WT_RAW`) so the quoted
   heredoc stays intact; `[^]]` as the portable spelling of "not a closing
   bracket". ✔ `6f051d0`, `16bf116`

## Harness trap encountered

`bash -n` writes its diagnostics to stderr. Under
`$ErrorActionPreference = 'Stop'`, native-command stderr becomes a *terminating*
PowerShell error, and `*> $null` does not prevent it — the parse gate killed the
suite with the very output it was collecting. The gate now saves the preference,
sets `Continue` for the loop, and restores it. This is the same trap #54 hit
with the drift checker; it is a property of the language, not of either script.

## Outcome

| Suite | Before | After |
|---|---|---|
| `test-hooks.sh` | 17 / 1 red | **23 / 0** |
| `test-hooks.ps1` | 104 / 1 red | **105 / 0** |
| `check-hook-resolution.py hooks` | exit 0 | exit 0 |
| `test-hooks-integration.ps1` | pass | pass |
| `test-lint-gate.ps1` | pass | pass |
| `bash -n` over all 16 `.sh` hooks | 2 failing | **all clean** |

Scope note: issue #65 reported the syntax errors. It asked, as scope point 3,
what the coordinator hook *should* have been blocking while inert. The answer
turned out to be "also everything it would have failed to block after the
syntax fix" — three defects, none of them visible to the gate the issue asked
for. The parse gate is necessary; it is not sufficient, and behavioural tests
are what closed the gap.

Left for its own branch: `#64` (`researcher-pretooluse` dead on every path).
Noted in passing, not addressed: five `.sh` hooks carry CRLF line endings in the
working tree (git normalises to LF in the index, so the deployed payload is
unaffected).
