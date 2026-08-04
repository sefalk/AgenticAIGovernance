# Fix: quality gate scopes to the file, not the changed function (#45)

<!-- copilot:generated | planner | 2026-08-04 -->

- **Created:** 2026-08-04
- **Issue:** [#45](https://github.com/sefalk/AgenticAIGovernance/issues/45)
- **Branch:** `agent/45-quality-gate-diff-scope`
- **Complexity tier:** Standard
- **Status:** COMPLETED

## The reported symptom is real; the stated cause is not

#45 is right about the damage. In WIT #3105 (project `MP Usage XP at Teamplay`,
AF 1.21.43) a change to the `COLPAR_RDF` registry forced ~90 lines of
NumPy docstrings onto six unrelated methods, blocked three commit attempts,
burned two subagent retries that blamed the agent for scope creep, and ended in
a recorded deviation. There was no correct path: the alternatives were
out-of-scope edits or bypassing a HARD gate.

But the proposed fix — *"mirror `check-python-linting.py`"* — cannot be applied
as written, because **neither checker contains diff logic**. Both take a file
list:

```
check-python-quality.py --files a.py b.py
check-python-linting.py --files a.py b.py
```

The branch-delta resolution lives in the **hooks**:

| Location | What it resolves |
|---|---|
| `implementer-stop.ps1` ~L151 | `merge-base HEAD $BASE_BRANCH`, then `origin/$BASE_BRANCH` |
| `refactorer-stop.ps1` ~L159 | same |
| `implementer-stop.sh` ~L127, `refactorer-stop.sh` ~L125 | same, bash |

So acceptance criterion 4 ("base-branch resolution matches
`check-python-linting.py`, no second divergent implementation") is unsatisfiable
in its literal form. Its *intent* is satisfiable and worth keeping: **do not add
a second base-branch resolver.** The hooks already resolve it — pass the result
in rather than re-deriving it.

### What is actually wrong

File scoping is already correct. `implementer-stop.ps1` builds `$changedSrcPy`
from the staged diff (falling back to `diff HEAD`), so only touched files reach
the checker. The defect is one level down: `_collect_public_functions` walks the
**whole module AST** and reports every public function it finds.

The gate wording is function-scoped —

> "Verify **changed public functions** include non-trivial docstrings"

— and the implementation is file-scoped. That gap is the entire bug.

## Scope

| Subtask | What | Gate |
|---|---|---|
| 1 | `--diff-base REF` on `check-python-quality.py`: derive changed line ranges per file from `git diff --unified=0 REF -- <file>` | Ranges match the diff, including added files |
| 2 | Report only functions whose `lineno..end_lineno` intersects a changed range, plus functions added wholesale | The six WIT #3105 methods drop out; the touched one stays |
| 3 | Hooks pass their already-resolved base (`implementer-stop` + `refactorer-stop`, `.ps1` + `.sh`) | One resolver, four call sites |
| 4 | Unresolvable base (shallow clone, no merge-base, not a repo) → fall back to whole-file **and say so** | Never silently narrower than today |
| 5 | Tests: the four acceptance cases plus the fallback | Each fails when its own branch is removed |

## Design decisions

**Default stays whole-file.** The checker is also invoked ad hoc, where there is
no meaningful base. Function scoping activates only when `--diff-base` is
supplied. The issue proposes the inverse (diff-scoped by default, whole-file
behind a flag); inverting it would make every caller that forgets the flag
*silently more permissive*, which is the wrong direction for a HARD gate to
fail.

**Fail wide, not narrow.** If the base ref does not resolve, the checker reports
whole-file results with a notice rather than passing everything. A gate that
disappears when git is unavailable is worse than one that over-reports.

**Which base to pass.** The hooks resolve `merge-base(HEAD, BASE_BRANCH)`. Using
that — rather than `HEAD` — means a function touched in an earlier phase of the
same workflow stays in scope. That matches the branch-delta accountability
argument already established for the linting gate (issue #13): the unit is what
the merge will add.

## Resolved: ignore hygiene is scoped, inherited ones are ADVISORY

**Decision (human, 2026-08-04): option (c).** A suppression on a changed line
fails the gate as today. A suppression the branch did not touch is printed as
`ADVISORY:` and does not affect the exit code.

The reasoning: the same scope-discipline argument applies to `# noqa` as to
docstrings — an agent should not have to justify a suppression it did not add.
But suppressions are cheap to add and expensive to notice, so dropping the
whole-file scan entirely would lose the only signal for inherited ones.
Advisory output keeps them visible without blocking on someone else's debt.

## Acceptance criteria

1. A file with one modified function and ten untouched undocumented functions
   passes.
2. A newly added undocumented public function still fails.
3. A modified public function with a missing/unstructured docstring still fails.
4. No second base-branch resolver is introduced; the hooks pass theirs in.
5. Unresolvable git history falls back to whole-file with an explicit notice,
   never to a silent pass.

## Outcome

| # | Acceptance criterion | Evidence |
|---|---|---|
| 1 | Untouched undocumented functions pass | `untouched functions are out of scope (WIT-3105 shape)` |
| 2 | Newly added undocumented function fails | `newly added public function is in scope` |
| 3 | Modified function with a bad docstring fails | `changed function with no docstring fails`, `... unstructured docstring fails`, `... without annotations fails` |
| 4 | No second base-branch resolver | `resolve_base` verifies a ref but never computes a merge-base; the four stop hooks pass their existing `merge_base` in via `--diff-base` |
| 5 | Unresolvable history degrades loudly | `unresolvable base falls back to whole-file with a notice`, `no git repository falls back to whole-file with a notice` |

**Suites:** `test-quality-gate.ps1` 15/15 (new), `test-lint-gate.ps1` 21/21,
`test-hooks.ps1` 63/63, `test-hooks-integration.ps1` 7/7.

**Mutation: 7/7 killed.** Mutants covered the scope check, decorator spans,
the untracked-file fallback, pure deletions, the unresolved-base fallback, and
both directions of the blocking/advisory split.

One mutant (`cat-file -e {base}:` -> `cat-file -e HEAD:`) survived at first and
turned out to be **equivalent**, not a coverage gap: a file merely absent from
the base is already reported as wholly added by `git diff`, so the probe's only
real job is the *untracked* case -- where both refs miss alike. Rather than
annotating an equivalent mutant, the probe was replaced by the condition it
actually tests (`git ls-files --error-unmatch`), after which the mutant is no
longer expressible and its replacement dies.

**Process lesson.** Two mutation runs were started concurrently. The second
snapshotted the file *mid-mutation* and wrote that snapshot back as the
"restored" original, silently leaving a mutant in the working tree. Never run
mutation harnesses in parallel, and always re-run the baseline after a restore.

## Risks

- **Line ranges vs. AST ranges disagree on decorators.** `ast` reports
  `lineno` at the `def`, with decorators above it. A change to a decorator must
  count as changing the function; use `min(decorator_list.lineno, lineno)`.
- **`end_lineno` requires Python 3.8+.** Fine for the framework floor, but
  assert rather than assume.
- **Renamed/moved files** produce diffs that look like full rewrites. Acceptable:
  over-reporting, not under-reporting.
- **The tests must be branch-independent.** Same lesson as #37 — build fixture
  repos with real commits rather than asserting against this checkout.

## Change log

| Date | Change |
|---|---|
| 2026-08-04 | Created. Corrects the issue's stated cause: no diff logic exists in either checker; the hooks resolve the base and the defect is function-vs-file granularity. |
| 2026-08-04 | Human decision (c): ignore hygiene is diff-scoped, inherited suppressions are reported as ADVISORY. |
| 2026-08-04 | COMPLETED. `--diff-base` implemented and wired into all four stop hooks; 15 new tests; mutation 7/7. |
