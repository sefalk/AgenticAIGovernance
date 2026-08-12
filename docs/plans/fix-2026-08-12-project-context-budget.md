<!-- copilot:generated | documenter | 2026-08-12 -->

# Fix: the context budget had one ceiling and two owners (issue #107)

- **Issue:** [#107](https://github.com/sefalk/AgenticAIGovernance/issues/107)
- **Branch:** `agent/107-project-context-budget`
- **Base:** `dev` @ `1a25953`
- **Complexity tier:** Standard
- **Status:** COMPLETED
- **Date:** 2026-08-12

## Problem

`check-context-budget.py` enforced three ceilings over the whole `.github`
instruction payload. But that payload has two authors. The framework ships and
controls `quality-gates`, `git-workflow`, `provenance`, `testing`, `tooling`
and `copilot-authoring`. The project owns `copilot-instructions.md` and
`architecture.instructions.md` — AF marks both `[customizable]` in
`.af-manifest`, protects them on update, and ships templates that invite the
project to fill them in.

Measured on the framework repository today:

```
always-on    AF-owned 3,461   project 1,404   ceiling 4,950
conditional  AF-owned 3,824   project 1,617   ceiling 5,500
```

The framework spends roughly 70% of both ceilings on its own files. Whatever
was left over became the project's allowance — 1,489 always-on tokens, against
a template that invites about 2,000. Issue #107 measured a fresh consumer
failing all three budgets on the day it was deployed:

```
always-on   5,512 / 4,950   FAIL by 562
conditional 5,661 / 5,500   FAIL by 161
coordinator 11,536 / 10,900 FAIL by 636
```

Nobody had drifted anywhere. The gate failed on arrival.

### Why raising the numbers was not an option

A gate that fails on arrival admits exactly two responses.

Raise the ceilings until it passes. That converts a drift detector into a
rubber stamp: a gate whose passing verdict carries no information, because it
was set to whatever made today's failure go away. Same failure shape as #98 and
#27.

Or shrink the project's files to fit the framework's leftovers. That is what
the consumer actually did. Re-measured against the live consumer on 2026-08-12,
**#107 no longer reproduces** — all three budgets pass:

```
always-on   4,866 / 4,950   PASS   (84 tok headroom, 1.7%)
conditional 5,466 / 5,500   PASS   (34 tok headroom, 0.6%)
coordinator 10,632 / 10,900 PASS   (268 tok headroom)
```

That is not a fix, it is the symptom of the second response. The consumer's
`copilot-instructions.md` went from 2,051 tokens to 1,405 — a 31% cut to the
file that tells every agent what the project *is* — and its
`architecture.instructions.md` from 1,837 to 1,642. It now sits one paragraph
away from failing again, and the file it must not grow is its own
self-description. The framework was rationing the project's ability to describe
itself, and calling the result a budget.

### A correction to the issue

#107's breakdown labels `testing.instructions.md` and `tooling.instructions.md`
as "(project)". They are not. Hash-compared against the framework payload, both
are byte-identical to AF's, as are `git-workflow`, `provenance`,
`quality-gates` and `copilot-authoring`. Only `architecture.instructions.md`
differs — exactly the one file the manifest marks `[customizable]`.

This strengthens the argument rather than weakening it: only **one** of the
four conditional files is project-authored, and the framework's three consume
3,824 of the 5,500 ceiling. It also validates `[customizable]` empirically as
the ownership discriminator, rather than as a plausible-sounding convention.

## Approach

Split each ceiling by author, and calibrate each in the repository that
controls it.

**Ownership** comes from two signals, because one is not enough.
`[customizable]` in `.af-manifest` catches the files AF ships as templates. It
cannot catch a file AF never shipped at all — a project's own
`instructions/*.md` sits in the same directory as AF's and carries no
annotation — so `.af-hashes`, the deployment record, supplies the second
signal. A measured file is the project's when it is customizable, or when a
deployment record exists and does not list it.

Missing `.af-manifest` is **BLOCKED** (exit 2), not a pass. Falling back to
"everything is AF's" reproduces the defect; "everything is the project's" makes
the framework ceiling vacuous. The result is unknown, and silence must not read
as success.

**The framework ceilings were tightened**, not relaxed. Each is now the
measured framework share plus the headroom it already carried against the
combined ceiling:

| Budget | Was | Framework share | Now |
|---|---|---|---|
| `AF_CONTEXT_BUDGET_TOKENS` | 4,950 | 3,461 | 3,500 |
| `AF_CONDITIONAL_BUDGET_TOKENS` | 5,500 | 3,824 | 3,850 |
| `AF_AGENT_CONTEXT_BUDGET_TOKENS` | 10,900 | 9,227 | 9,450 |

**The project ceilings have no default.** Two new keys,
`AF_PROJECT_CONTEXT_BUDGET_TOKENS` and `AF_PROJECT_CONDITIONAL_BUDGET_TOKENS`,
are seeded from what the project actually has plus 10% headroom. No constant
would have worked here: a number that fits one project fails the next, and a
number generous enough for every project measures nothing. 2,000 would still
have failed the consumer's 2,051 at the time #107 was filed.

Unset, the project share is measured, printed as `UNBUDGETED` with the seeding
command, and **not gated**. A project that has never stated a baseline has not
drifted from one, and inventing a ceiling on its behalf is the arrival failure
itself. The framework share stays gated either way — that is the part this
repository can honestly enforce.

**Per-agent totals exclude the project's always-on set.** An agent must not
stop fitting because the consuming project wrote itself a longer overview. The
true total is still printed as the worst case.

**Deploy seeds on a fresh install only.** On an update `af-env.conf` is a
baseline somebody chose, and overwriting it would erase exactly the drift the
ceiling exists to detect. Both dialects carry the step; where no Python is
found, deploy says so and names the command rather than passing silently.

## Changes

| File | Change |
|---|---|
| `.github/scripts/check-context-budget.py` | Ownership classification, split totals and ceilings, `--seed-project-budget` / `--force`, blocked on missing manifest |
| `.github/af-env.conf` | Framework ceilings retuned to the framework share; two project keys with the seeding workflow documented |
| `.github/hooks/scripts/check-context-budget-staged.py` | Exports `.af-manifest` from the index and copies `.af-hashes` from the working tree, so the staged payload can be attributed |
| `.github/scripts/test-context-budget.ps1` | Fixture generator writes `.af-manifest` / `.af-hashes`; 15 new checks (LL–SS) |
| `deploy.ps1`, `deploy.sh` | Seed the project ceilings on a fresh install; warn, do not pass silently, when Python is absent |
| `CHANGELOG.md` | Entry under `[Unreleased]` |

## Verification

- `test-context-budget.ps1`: **71/71 checks pass** (56 before, 15 added).
- `test-hooks.ps1`: all pass — the staged guard changed.
- `ruff check` clean on both changed Python files.
- Gate against the framework repository: PASS, AF always-on 3,461/3,500, AF
  conditional 3,824/3,850, coordinator 9,227/9,450.
- Gate against the live consumer: PASS, project share reported as `UNBUDGETED`
  (it has not been seeded — `af-env.conf` is protected on update, by design).

The new checks are discriminating, not decorative. `QQ` fails under the old
model (agent 4,000 + project 2,000 + AF 200 = 6,200 over a 5,000 ceiling) and
passes under the split. `PP` exits 0 under the old model and 2 under the new
one. `LL`, `MM`, `NN`, `OO` and `RR` assert output and exit codes that did not
exist before.

## Known limitation

Existing consumers never receive the new keys, because `af-env.conf` is
`[customizable]` and protected on update. Their project share will report as
`UNBUDGETED` until somebody runs `--seed-project-budget`. This is deliberate:
the alternative is deploy overwriting a file the project owns. The gate names
the command every time it runs.
