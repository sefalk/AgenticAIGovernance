<!-- copilot:generated | documenter | 2026-08-07 -->

# Scope the ask tier to what the framework knows and VS Code does not

**Issue:** #78, part (a)
**Branch:** `agent/78a-ask-tier-scope`
**Base:** `dev` @ `7331858`
**Status:** COMPLETED

## The defect

Terminal confirmations arrive in two forms. One is Copilot's own assessment: it
categorises the command and says in plain language what it will actually do.
The other is ours: a sentence written months earlier by someone who could not
know which command it would be shown for.

Which one appears is not negotiated. When `block-dangerous` returns
`permissionDecision: "ask"`, VS Code renders our `permissionDecisionReason`
verbatim and the native flow does not run. Every time the useful summary
appeared, our hook had stayed silent; every time the flat sentence appeared, we
had spoken over it.

Part (b) of the issue already fixed the wording — eleven rules had shared one
sentence that named neither the rule nor the command. But a better sentence is
still a sentence. For a generic durable change, ours is simply the worse of the
two prompts, and emitting it costs the user the better one. There is no way to
*call* the native assessment from a hook — the only way to get it is to not
preempt it.

## The decision

Scope the tier by what we know that VS Code cannot: repository and branch
state, autonomy policy, effects that land outside git. Everything else goes
back.

| Handed back (`{}`) | Why it is not ours |
|---|---|
| `pip install/uninstall` | an ordinary environment change; the native summary describes it better |
| `conda install/remove` | same |
| `ruff format` | a repo-local rewrite git can undo — the very operation issue #86 was about |
| `New-Item`, `mkdir`, `Copy-Item`, `Move-Item`, `mv`, `cp` | a confirmation dialog for `mkdir` is noise |

| Retained (`ask`) | What we know that VS Code does not |
|---|---|
| `git merge` | branch and worktree state, protected-branch policy |
| `git checkout` / `switch` | the path form discards uncommitted work, and the allow tier deliberately does not cover it |
| `git tag` | a release marker others may already rely on |
| `databricks …`, `az …` | the effect lands outside this repository, and may cost money |
| `Remove-Item`, `rm` | the one durable change git cannot undo |
| task-launch asks | they fire when the command cannot be resolved *at all* — the case that must never go quiet |

## Deferring is not approving

`{}` hands the decision to `chat.tools.terminal.autoApprove`. That is the real
trade-off the issue warned about, so it was measured rather than assumed. On
the machine this was decided on the setting contains five entries, matched as
prefixes:

```jsonc
".venv\\Scripts\\python.exe", "git checkout", "git add", "Test-Path", ".venv\\Scripts\\ruff"
```

Of the four handed-back rules, only `ruff` is covered — and it is covered
because the user put it there. For `pip`, `conda`, `mkdir`, `mv` and `cp` the
setting says nothing, so deferring produces a *better* prompt, not a missing
one. That asymmetry is what makes the change safe: handing a rule back only
removes a prompt where the user had already asked for it to be removed.

It also explains the sharpest retention. `git checkout` is in that list as a
prefix, so `git checkout -- src/foo.py` would match it — and that form discards
uncommitted changes to the path. Today our `ask` is the only thing standing in
front of it. The allow tier already separates the safe cases: `git switch
<branch>` never touches files, and `git checkout <ref>` is auto-allowed only
after `git rev-parse --verify` confirms the argument resolves to a commit. What
reaches the ask rule is the remainder, which is exactly the dangerous part.

## Cross-harness drift

The two classifiers are independent files. A rule retained in one and handed
back in the other is a confirmation that appears on Windows only — a gate whose
behaviour depends on which shell the user happens to run. A static assertion
now compares the length of `$askRules` against `ask_patterns` and fails if they
diverge.

## Verification

| Suite | Before | Red | Green |
|---|---|---|---|
| `test-hooks.ps1` | 186 / 0 | 192 / 5 | **197 / 0** |
| `test-hooks.sh` | 84 / 0 | — | **92 / 0** |

`bash -n` clean on `block-dangerous.sh`.

Two existing cases had to move off `pip`, which is no longer an ask: the
"reason explains the environment-wide effect" case now asserts the `git tag`
reason, and the "two different rules give two different reasons" case pairs
`Remove-Item` with `git tag`.

### Mutations

| Mutation | Observed |
|---|---|
| put the `pip` rule back | 2 red — the deferral, and the cross-harness count |
| put the filesystem rule back | 4 red — `mkdir`, `Copy-Item`, the count, and the delete reason it shadows |
| hand deletion back too | 8 red — every case that depends on the tier still owning `rm` |
| drop one rule from the bash harness only | 1 red — the drift assertion |

## What this does not do

- It does not build our own semantic assessment. Option (c) in the issue stays
  rejected: a model call inside a security gate adds latency to every command
  and makes the gate itself sometimes unavailable, which is the failure mode
  this framework keeps finding.
- It does not touch the deny tier. Nothing that was denied is now asked, and
  nothing that was asked is now denied.
- It does not touch the task-launch branch, whose asks exist precisely because
  the payload could not be classified.
