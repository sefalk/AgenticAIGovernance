# Fix: the hook harness read silence as consent (#68)

<!-- copilot:generated | documenter | 2026-08-06 -->

- **Created:** 2026-08-06
- **Issue:** [#68](https://github.com/sefalk/AgenticAIGovernance/issues/68)
- **Branch:** `agent/68-assert-allow-silence`
- **Complexity tier:** Standard
- **Status:** COMPLETED

## The measured defect

`Assert-Allow` in `test-hooks.ps1` accepted an empty answer as an approval:

```powershell
# Allow = empty JSON or no hookSpecificOutput or no permissionDecision
$isAllow = ($text -eq '{}' -or $text -eq '' -or $null -eq $text)
```

A hook that **examined the request and approved it** and a hook that **never
ran, crashed, or read a field that does not exist** produce the same bytes.
Thirty call sites were blind in that direction.

This is not a test-quality nicety. It is the mechanism by which the last two
defects shipped:

| Issue | What the hook did | What the harness saw |
|---|---|---|
| #65 | failed `bash -n`, exited non-zero, printed nothing | PASS |
| #64 | read `tool_input.url` where the tool sends `urls`, returned `{}` on every real fetch | PASS |

The framework's safety argument is that hooks speak up. A harness that reads
silence as consent cannot verify that argument.

## What changed

| Area | Before | After |
|---|---|---|
| Verdict classification | inline in each `Assert-*`, three variants | one `Resolve-Decision`, returning `allow` / `deny` / `ask` / `silent` / `error` |
| `{}` and empty output | counted as an allow | `silent` — a distinct outcome |
| Non-zero exit | ignored; stdout judged on its own | `error` — a crash is credited with no opinion |
| Unparsable output | fell through to allow | `error` |
| Intent of a case | one assertion for two different claims | `Assert-Allow` (the gate approved) vs `Assert-Silent` (the gate had no remit) |
| `Assert-Deny` / `Assert-Ask` | own copies of the parse-and-compare | thin wrappers over `Assert-Decision` |
| bash `run_case` | judged stdout regardless of exit status | non-zero exit voids the verdict |

15 of the 30 `Assert-Allow` sites were re-stated as `Assert-Silent`: the
coordinator's delegation gate, the test-writer and refactorer branch gates and
every "not my tool" case return `{}` by design and never emit an approval. The
remaining 15 — `block-dangerous`'s auto-approval tier, its `createAndRunTask`
allowlist, and the researcher's allowlisted domain — must produce an explicit
`allow`, and now have to.

## Subtasks

1. **Red — the instrument must discriminate.** Self-check section asserting
   that `Resolve-Decision` separates an explicit verdict from silence and from
   a crash; the 15 silence cases moved to `Assert-Silent`. ✔ `fe4f94d`
2. **Green — one classifier, two distinct assertions.** ✔ `fdc0724`
3. **Red — the exit code must survive the plumbing.** Classifying a string is
   half the instrument; the runner has to carry the exit code out of a real
   hook process. Two stub hooks, run as processes. ✔ `9673bbd`
4. **Green — `Invoke-HookScript` extracted** so the runner is callable with an
   arbitrary script path. ✔ `6c4efe4`
5. **Green — bash parity.** `run_case` captures the subshell status and voids
   the verdict when it is non-zero. ✔ `463d3f6`

## Verified by mutation, not by a green run

A suite that goes from green to green proves nothing about a gate that was
already blind. Both harnesses were checked against a deliberately broken hook:

```
# block-dangerous.ps1: Emit 'allow' -> Write-Output '{}'
FAIL  pip show via call operator is safe -- expected allow, got 'silent' (exit 0, output: {})
FAIL  commit message mentioning databricks export does not false-ask -- ...
    (9 failures; all 9 passed under the previous Assert-Allow)

# refactorer-pretooluse.sh: a syntactically perfect deny, followed by exit 3
FAIL  file creation denied on agent branch -- expected deny,
      got: {"...","permissionDecision":"deny",...} (exit 3)
```

Both hooks were restored from git immediately afterwards.

## Outcome

| Suite | Before | After |
|---|---|---|
| `test-hooks.ps1` | 110 / 0 | **119 / 0** |
| `test-hooks.sh` | 28 / 0 | 28 / 0 (exit status now judged) |
| `test-hooks-integration.ps1` | pass | pass |
| `test-lint-gate.ps1` | 21 / 21 | 21 / 21 |

No hook changed behaviour: every existing case still holds under the stricter
reading. The blindness was entirely in the instrument — which is the least
comfortable place for it, because it is the thing that reports on everything
else.

## Follow-up

#69 (audit every hook's `tool_name` match and `tool_input` field reads against
captured payloads) depends on this: until the harness stopped reading `{}` as
an allow, a wrong field name could not fail a test.
