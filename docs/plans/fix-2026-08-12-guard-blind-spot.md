<!-- copilot:generated | documenter | 2026-08-12 -->

# Fix: the guard's silence was indistinguishable from its approval (issue #125)

- **Issue:** [#125](https://github.com/sefalk/AgenticAIGovernance/issues/125)
- **Branch:** `agent/125-guard-blind-spot`
- **Base:** `dev` @ `9201b70`
- **Complexity tier:** Standard
- **Status:** COMPLETED
- **Date:** 2026-08-12

## Problem

`check-context-budget-staged.py` measures the **staged** payload. That scope is
deliberate and correct — it is the reason an ordinary commit pays nothing, and
the reason the verdict is a statement about the change being made rather than
about whatever happens to be lying in the working tree.

It has one consequence nobody stated. A project that blanket-ignores `.github/`
in its root `.gitignore` can never stage a budget input. The guard was
installed, wired into the pre-commit shim, and dispatched on every commit —
and structurally unable to fire. Its code path was:

```python
roots = sorted({r for path in _staged_files() if (r := _payload_root(path))})
if not roots:
    return 0
```

Exit 0, no output. Which is also precisely what the guard emits when it has
measured the whole payload and found it within budget. The two states were
indistinguishable to the human reading the commit output, so the absence of
complaints read as consent.

When the payload was finally tracked, the guard's first run reported three
simultaneous breaches:

```
always-on     5,512 / 4,950   (562 over)
conditional   5,661 / 5,500   (161 over)
coordinator  11,536 / 10,900  (636 over)
```

No single commit had introduced them. They accumulated across months of deploys
and workflows while the guard reported nothing at all.

## The distinction the guard could not make

There are two reasons the staged set can be empty, and only one of them is
benign:

| State | Meaning | Right response |
|---|---|---|
| No budget input staged, payload tracked | This commit does not touch the payload. Whatever it would measure was measured when it *was* committed. | Silence. Pay nothing. |
| No budget input tracked at all | There was no such commit, and there cannot be one. | Say so — on every commit, until it is fixed. |

A third state sits between them and was created by the obvious fix: a project
that unignores *part* of `.github/`. Detecting only the total case would have
let a project silence the warning by tracking `agents/` while leaving
`instructions/` — the larger always-on cost — invisible. Half an unignored
`.github/` is not half a gate; it is a gate that measures a subset and reports
it as the total.

## Approach

The guard now computes a **blind spot**: budget inputs present in the working
tree that git does not track. "Budget input" is one predicate — the measured
content plus `af-env.conf` (which sets the ceilings) and `.af-manifest` (which
decides ownership) — and `_payload_root` was rewritten to use it, so the
trigger set and the blind-spot set cannot drift apart.

- **Nothing staged, blind spot empty** → silent, exit 0. Unchanged.
- **Nothing staged, everything blind** → `NOT GATED`, naming the file count,
  whether a gitignore rule is the cause, and the payload measured from disk.
- **Nothing staged, partially blind** → `PARTIALLY GATED`, listing the files,
  with the same disk reading.
- **Payload commit with a blind spot** → the measurement is labelled a floor,
  not a total, and the omitted files are named.

Without a staged path there is nothing to derive the payload root from, so the
guard falls back to where it is installed: `hooks/scripts/` → `.github/`.
Outside the repository being committed to it stays silent — that is someone
else's payload.

## Three decisions worth recording

**The reading comes from disk where the index is blind.** Copilot loads
instruction files from the working tree; whether git holds them changes nothing
about what they cost. So the index is the right basis for a *verdict* — it is
what the commit is made of, which is what BB/CC pin — and the wrong basis for a
*number*. Measuring the working tree on *every* commit was considered and
declined: it would report breaches the committer did not stage and cannot act
on, and a fully-tracked repository would pay 0.6 s for a second reading that
can only repeat the first. The measurement runs exactly where the index cannot
answer, which costs a healthy repository nothing and stops the moment the
tracking is fixed.

**Blindness is reported, never blocked.** An exit code is a statement about the
commit in front of the guard; untracked files are a statement about the
repository. Charging one to the other would make an unrelated commit pay for a
configuration defect, and would hand a project that deliberately keeps its
payload local no way forward except disabling the guard entirely. The
persistent, specific complaint plus a real number is the enforcement.

**The advisory failure output is verbose, deliberately.** When the disk reading
fails it carries the checker's full breakdown and fix advice — roughly twenty
lines on every commit. That is the cost of a payload outside version control,
it names the file responsible, and it ends the moment the tracking is fixed. A
passing reading is a single line.

## Changes

| File | Change |
|---|---|
| `.github/hooks/scripts/check-context-budget-staged.py` | `_is_budget_input`, `_on_disk`, `_tracked`, `_blind_spot`, `_own_root`, `_ignored`, `_report_blind_spot`, `_advise`, `_checker`; `_payload_root` rewritten on the shared predicate; floor note on payload commits |
| `.github/scripts/test-context-budget.ps1` | Cases TT–WW (11 checks) plus `Install-Guard` / `Invoke-DeployedGuard`, which deploy the guard *into* the fixture so it can locate its own payload |
| `.github/skills/git-workflow/SKILL.md` | Blind-spot bullet beside the existing scope and override bullets |
| `CHANGELOG.md` | Entry under Unreleased → Fixed |

## Verification

- `test-context-budget.ps1`: **82/82** checks pass (71 before, 11 added). The new
  assertions match strings this change introduces (`NOT GATED`,
  `PARTIALLY GATED`, `is a floor`, `gitignore rule`, `advisory`), none of which
  the guard could previously emit.
- `python -m ruff check` clean on the guard.
- Case `UU_tracked_payload_stays_silent` pins the ordinary commit as silent —
  the fix must not turn every commit into a banner, and a healthy repository
  must not pay for a measurement.
- Run against the AF repository itself with nothing staged: silent, exit 0
  (its payload is fully tracked).
- Run against a throwaway repository with `.github/` gitignored: `NOT GATED`,
  files named, gitignore identified as the cause, `FAIL -- AF always-on set is
  1,507 tok over budget` printed as advisory, exit 0.

## Known limitation

The blind-spot report fires only from the guard, which runs on commit. A
repository that never commits never hears it. That is the same boundary every
pre-commit gate has, and closing it needs CI — which this framework does not
have.
