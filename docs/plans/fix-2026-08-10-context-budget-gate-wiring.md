<!-- copilot:generated | documenter | 2026-08-10 -->

# Fix: wire the context budget gate to something that runs

- **Issue:** [#85](https://github.com/sefalk/AgenticAIGovernance/issues/85)
- **Branch:** `agent/85-context-budget-gate-wiring`
- **Base:** `dev` @ `6306981`
- **Complexity tier:** Standard
- **Status:** IN PROGRESS

## Problem

`check-context-budget.py` measures the payload correctly and has never once
been asked to. Its only reference anywhere in the repository is a checklist
line in `copilot-authoring.instructions.md` — a line that told the reader to
run a Python script with `pwsh`, which means it was never executed as written.

The consequence was visible on `dev`: the conditional instruction set sat
**273 tokens over its own ceiling** (5,773 > 5,500) and nobody noticed until
issue #59 happened to run the script by hand. `test-context-budget.ps1` case
`J_real_payload_within_budget` was red on `dev` for the same period. A red
test in a suite nobody runs is indistinguishable from a green one.

This is the same defect class as #86/#78/#87/#91: **a gate that cannot run and
a gate with nothing to say produce identical output — silence — and every
layer reads that silence as consent.** Here it is the purest form. The gate is
not broken. It is simply never asked.

## Investigation

### The obvious attachment point does not cover the repo that needs it

`.github/hooks/git/pre-commit` already dispatches to `hooks/scripts/check-*.py`
and is the natural home. But the AF source repo does not run it:

```
$ git config core.hooksPath
.githooks
$ Test-Path .github
False
```

The AF repo's hook path is the repo-root `.githooks/`, whose `pre-commit` does
exactly one thing: auto-bump `flavors/github-copilot/VERSION`. The shipped shim
resolves its checkers at `$repo_root/.github/hooks/scripts`, a path that does
not exist here — and the shim's `[ -f "$checker" ] || continue` fail-open turns
that absence into a silent skip.

So `check-large-files.py` and `check-strict-json.py` — the framework's own
commit guards — have never run on a single framework commit. They protect
consumer projects only. **The repo that authors the guards is the one repo they
do not guard.** That is why acceptance criterion 3 (`J_real_payload_within_budget`
cannot sit red on `dev` unobserved again) cannot be met by adding a checker to
the shim alone.

### Decisions the issue asked to settle

| Question | Decision | Reasoning |
|---|---|---|
| Block or advise? | **Block**, with a one-off `ALLOW_CONTEXT_BUDGET=1` override | The budgets carry ~2% headroom by design, so the block *is* intended to be hit. That is the point: the person who tips the ceiling over is the only person who still has context on what they just added. An advisory prints into a hook that already prints other things and lands the drift on whoever notices later — which #85 documents as "never". The override is per-commit and cannot be made permanent by configuration, exactly like `ALLOW_LARGE_FILES` / `ALLOW_JSONC`. |
| Staged blobs or working tree? | **Staged blobs**, materialised from the index | The other two guards check what would be committed, not what happens to be on disk. Anything else lets a dirty working tree either mask a breach or invent one. |
| Reimplement the measurement? | **No** — materialise the index payload into a temp tree and invoke the existing `check-context-budget.py --github-dir` | Globs, budgets, thresholds and the `applyTo` semantics stay in exactly one place. A second implementation would drift from the first, and the drift would be invisible until it mattered. |
| Does the deployed flavour inherit it? | Yes | The shim ships via the `.af-manifest` `hooks/` entry. The guard derives the `.github` directory from the staged path, so it reads the *consumer's* `af-env.conf` budgets, not the framework's. |
| One mechanism or two? (AC4) | **One** | One checker, registered in the one dispatch loop, plus making the AF repo actually use that dispatch loop. No session-start advisory, no second checklist line. |

### Why the AF hook dispatches the whole set, not just the budget checker

Teaching `.githooks/pre-commit` about one checker would produce a bespoke
one-off and leave the other two guards dead. Making it dispatch the payload's
checker set fixes the class instead of the instance, and the budget gate on
`dev` falls out of it. Verified before enabling: no tracked file exceeds
`LARGE_FILE_MAX_BYTES`, and `flavors/github-copilot/.vscode/tasks.json` parses
as strict JSON — both newly-live guards are green today.

The guards run **before** the VERSION auto-bump, so a blocked commit does not
leave a bumped VERSION staged behind it.

## Subtasks

| # | Task | Acceptance criteria |
|---|---|---|
| 1 | `hooks/scripts/check-context-budget-staged.py` | Blocks (1) when the staged payload is over budget; silent 0 when no measured file is staged; reads index blobs, not the working tree; honours `ALLOW_CONTEXT_BUDGET`; propagates the inner checker's BLOCKED (2) rather than passing |
| 2 | Register it in `.github/hooks/git/pre-commit` | The checker loop names it; consumer projects inherit it via `.af-manifest` |
| 3 | `.githooks/pre-commit` dispatches the payload checkers | Runs the guard set before the VERSION bump; `dev` can no longer drift over budget unobserved (AC3) |
| 4 | Regression cases in `test-context-budget.ps1` | Scoping, staged-vs-worktree, override, BLOCKED propagation, consumer budgets, nested payload path, and both wiring assertions |
| 5 | Replace the checklist line with the mechanism | `copilot-authoring.instructions.md` documents the gate that runs instead of asking a human to remember (AC4) |

## Results

_Filled in at completion._

## Notes

_Filled in at completion._
