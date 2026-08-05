# Fix: the researcher's fetch hook judged a payload it never receives (#64)

<!-- copilot:generated | documenter | 2026-08-05 -->

- **Created:** 2026-08-05
- **Issue:** [#64](https://github.com/sefalk/AgenticAIGovernance/issues/64)
- **Branch:** `agent/64-researcher-hook-inert`
- **Complexity tier:** Standard
- **Status:** COMPLETED

## The measured defect

`researcher-pretooluse.sh` read `tool_input.url` / `.uri`. VS Code's fetch tool
sends **`urls`** — an array — beside `query`. Both of the hook's gates sit
behind that read, so both were inert:

```
=== urls array, with a WORKING python3 ===
rc=0 output: [{}]
```

The credential scan never ran. The domain allowlist never ran. The hook
returned `{}` on every real fetch, which the runtime reads as "examined, no
objection".

The suite was green the whole time, because the fixtures encoded the
*implementation's belief* about the payload. That is the reason all of this
survived: a test written from the code cannot contradict the code.

Defect 1 of the issue — death on the Windows `python3` stub under `set -e` —
was already repaired by #54's shared preamble, which this hook now sources.

## What changed

| Area | Before | After |
|---|---|---|
| Payload | `url` / `uri` string | `urls` array primary, `url` / `uri` kept as legacy fallbacks |
| Decision over an array | n/a | every entry scanned and allowlist-checked; **one unlisted entry decides the batch** |
| Sanitiser | `sed -E 's\|…(token\|key)…\|…\|gI'` — `\|` as both delimiter and alternation, exit 1 | `#` as the `s` delimiter |
| Host extraction | text before the first `:` in the authority | text after the last `@`, port stripped |
| `.ps1` config | `Split-Path` chain + `Select-String` re-rolled per file | `Get-AfConfig` from `_common.ps1` |
| PS fixture | copied the hook only | copies `_common.ps1` too, as the bash harness does |

## The defect the issue did not contain

Probing the credential path once it could run produced this:

```
https://docs.python.org:x@evil.example.com/
-> "permissionDecision":"allow","...":"Allowlisted documentation domain."
```

The authority of a URL is `[userinfo@]host[:port]`. Reading up to the first `:`
reads the **userinfo** whenever one is present, so any allowlisted name used as
a username approved an arbitrary host. It was invisible while the credential
path was unreachable — the only URLs that carry userinfo are the ones the
sanitiser used to abort on.

Found by execution, not by reading. Both suites now assert it.

## Subtasks

1. **Red — the real payload shape.** `urls` fixtures in `test-hooks.sh` and
   `test-hooks.ps1`: allowlisted, unlisted, mixed, credentialed. `Assert-Allow`
   was deliberately *not* used — it counts `{}` as an allow, which is how an
   inert hook passes. The assertions read the explicit decision. ✔ `826381a`
2. **Green — array payload and sanitiser.** Both siblings rewritten around a
   list of URLs; `#` as the `s` delimiter; the `.ps1` now dot-sources
   `_common.ps1`. ✔ `05f689f`
3. **Red — the userinfo bypass.** ✔ `fee310a`
4. **Green — host from after the last `@`.** ✔ `dd0058f`

## Outcome

| Suite | Before | After |
|---|---|---|
| `test-hooks.sh` | 23 / 0 (blind to the defect) | **28 / 0** |
| `test-hooks.ps1` | 105 / 0 (blind to the defect) | **110 / 0** |
| `check-hook-resolution.py hooks` | exit 0 | exit 0 |
| `test-hooks-integration.ps1` | pass | pass |
| `test-lint-gate.ps1` | 21 / 21 | 21 / 21 |

The pattern across #54, #65 and #64 is one pattern: a gate that cannot run and
a gate with nothing to say produce the same output. Here the tests were the
thing at fault — they were written from the implementation, so they agreed with
it about the one fact that mattered.
