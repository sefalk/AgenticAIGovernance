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
  whether a gitignore rule is the cause, and the command to measure by hand.
- **Nothing staged, partially blind** → `PARTIALLY GATED`, listing the files.
- **Payload commit with a blind spot** → the measurement is labelled a floor,
  not a total, and the omitted files are named.

Without a staged path there is nothing to derive the payload root from, so the
guard falls back to where it is installed: `hooks/scripts/` → `.github/`.
Outside the repository being committed to it stays silent — that is someone
else's payload.

## Two decisions worth recording

**Blindness is reported, never blocked.** An exit code is a statement about the
commit in front of the guard; untracked files are a statement about the
repository. Charging one to the other would make an unrelated commit pay for a
configuration defect, and would hand a project that deliberately keeps its
payload local no way forward except disabling the guard entirely. The
persistent, specific complaint is the enforcement.

**Measuring the working tree on every commit was declined.** The issue raised
it as an option. It would give a reading on every commit — including breaches
the committer did not stage, cannot act on, and did not cause. And a
non-blocking measurement printed identically on every commit is the banner that
becomes the next form of silence. The guard reports the defect it can act on
(the gate is off) and points at the one command that produces the number.

## Changes

| File | Change |
|---|---|
| `.github/hooks/scripts/check-context-budget-staged.py` | `_is_budget_input`, `_on_disk`, `_tracked`, `_blind_spot`, `_own_root`, `_ignored`, `_report_blind_spot`; `_payload_root` rewritten on the shared predicate; floor note on payload commits |
| `.github/scripts/test-context-budget.ps1` | Cases TT–WW (8 checks) plus `Install-Guard` / `Invoke-DeployedGuard`, which deploy the guard *into* the fixture so it can locate its own payload |
| `.github/skills/git-workflow/SKILL.md` | Blind-spot bullet beside the existing scope and override bullets |
| `CHANGELOG.md` | Entry under Unreleased → Fixed |

## Verification

- `test-context-budget.ps1`: **79/79** checks pass (71 before, 8 added). The new
  assertions match strings this change introduces (`NOT GATED`,
  `PARTIALLY GATED`, `is a floor`, `gitignore rule`), none of which the guard
  could previously emit.
- `python -m ruff check` clean on the guard.
- Case `UU_tracked_payload_stays_silent` pins the ordinary commit as silent —
  the fix must not turn every commit into a banner.
- Run against the AF repository itself with nothing staged: silent, exit 0
  (its payload is fully tracked).
- Run against a throwaway repository with `.github/` gitignored: `NOT GATED`,
  4 files named, gitignore identified as the cause, exit 0.

## Known limitation

The blind-spot report fires only from the guard, which runs on commit. A
repository that never commits never hears it. That is the same boundary every
pre-commit gate has, and closing it needs CI — which this framework does not
have.
