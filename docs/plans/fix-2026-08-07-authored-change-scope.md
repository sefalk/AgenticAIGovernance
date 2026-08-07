<!-- copilot:generated | documenter | 2026-08-07 -->

# Fix: gates were scoped to the diff, so a formatter run looked like authorship

**Issue:** [#86](https://github.com/sefalk/AgenticAIGovernance/issues/86)
**Branch:** `agent/86-gates-scoped-to-authored-change`
**Status:** COMPLETED
**Workflow:** L3_Bug_Fix

## The defect

Three HARD gates in the implementer's stop hook ask their question of every
file in the branch diff:

| Gate | Scope before |
|---|---|
| Provenance marker | every changed `.py` file |
| Docstrings / type hints | every changed *function*, via `changed_ranges` |
| Ignore hygiene | every suppression on a *changed line* |

A diff answers "which lines moved". A formatter moves all of them. So for a
purely mechanical change the three gates demand content the agent has no
reason to write — and, in the provenance case, content that is factually
false.

MPUsageXPTP work item **WIT #3121** asked for `ruff format` across the
repository, with the acceptance criteria "a single dedicated commit" and "no
logic change". `ruff format` alone touches 80 files. The implementer returned
**148 additional hand edits across 68 files**:

| Edit | Count | Gate it satisfies |
|---|---|---|
| `copilot:generated` / `copilot:modified` lines | 72 | provenance |
| `Returns` / `Parameters` docstring sections | 35 | docstring quality |
| `# noqa: RULE  # reason` justifications | 9 | ignore hygiene |

Each maps 1:1 onto a gate the agent had to clear in order to exit. Nothing
in the workflow was broken; the gates were answered exactly as written.

The damage is threefold:

1. **False provenance.** 72 markers claiming authorship of files nobody
   authored — the inverse of L1 Principle 3 (transparency/traceability).
2. **Unreviewed semantics smuggled into a mechanical commit.** Raw
   comparison found 14 of 96 files semantically different; after normalising
   docstring *whitespace*, **11 still differed** — authored docstring
   *content* inside a commit labelled "formatting only". Only an AST
   equivalence check caught it. A formatter-only rerun produced 80 files,
   0 provenance lines, 0 suppressions and **0 AST differences**.
3. **A blocked class of work.** Formatter adoption, import rewrites,
   codemods and `pyupgrade` migrations have no correct path: the
   implementer and refactorer are gated, and the coordinator cannot write
   code (Cardinal Rule 1). There was no escape hatch, so the failure mode
   was silent — the agent complied and nobody saw a gate fire.

Same family as #64, #69, #70, #72, #78, #81 and #85. #81 was about *where* a
marker may sit; this is about *which files may be asked for one*. Fixing #81
alone would still have left a formatter run demanding 72 markers.

## The fix

Option 2 from the issue: scope authorship gates to authored change, not to
the diff. No new mode, no flag an agent can set, nothing that can be reused
as a general bypass.

`ruff format` cannot change an AST. So a file whose AST — modulo docstring
whitespace, which formatters *do* re-indent — matches the base carries no
authored change, and the authorship gates have nothing to say about it.

### `check-python-quality.py`

| Addition | Purpose |
|---|---|
| `base_text(path, base)` | the file as it stands in the base commit |
| `_normalise_docstrings(tree)` | collapse whitespace inside docstrings only |
| `_ast_signature(source)` | `ast.dump` of the normalised tree; `None` if unparseable |
| `is_authored(path, base)` | signatures differ, or the question is undecidable |
| `--list-authored` | report the authored subset, run no checks |

`ast.dump` omits line and column attributes by default, so reflowing,
re-quoting and re-bracketing leave the signature untouched. Docstrings are
the one construct a formatter rewrites *inside* the tree, hence the
normalisation — whitespace is collapsed, the words are not.

**Undecidable means authored.** No base blob, an unparseable file on either
side, or git unable to answer all return `True`. Failing the other way would
hand every authorship gate an off switch, which is the #64/#69/#85 failure
mode this repository keeps paying for.

The docstring and type-hint checks are skipped for a file that is not
authored. The suppression check is not — see below.

### Ignore hygiene: ownership by suppression, not by line

The hygiene check previously split blocking from advisory by asking whether a
suppression sat on a changed *line*. A reformat rewrites the line an
inherited suppression sits on, so an inherited `# noqa` became branch-owned
and demanded a justification for a comment the agent never wrote — root
cause 3 of the issue.

Ownership is now decided by the suppression itself: `_inherited_suppressions`
counts the whitespace-normalised suppression comments present in the base
blob, and each match in the working tree consumes one. What is left over is
what the branch introduced.

### The hole this opens, and why it is closed

**Comments do not appear in an AST.** A `# noqa` added to an otherwise
mechanical change is invisible to the authorship filter — a "formatting
only" commit could carry a smuggled suppression past a gate that had just
declared the file untouched. So the authorship filter is deliberately *not*
applied to ignore hygiene: the suppression check runs on every file
regardless, and ownership there is decided by base content instead. Test 25
asserts exactly this, and the mutation that applies the filter to hygiene
turns it red.

The same reasoning is why **linting is not scoped this way at all**. A ruff
violation is real whoever produced it. `test-hooks.ps1` and `test-hooks.sh`
assert statically that no lint invocation references the authorship filter.

### `implementer-stop.ps1` / `.sh`

The merge base and the Python interpreter are resolved once, before the
provenance gate rather than after it, so all three gates speak about the same
base. The provenance gate then takes its file list from
`--list-authored` instead of from `git diff`.

If the query cannot run — no merge base, no interpreter, script missing, or a
non-zero exit — the gate keeps the whole diff. An unanswerable question must
not silence a gate.

`refactorer-stop` needed no change: it has no provenance gate, and its
quality and hygiene gates go through `check-python-quality.py`, so both
behaviours reach it for free.

## Verification

| Suite | Before | Red | Green |
|---|---|---|---|
| `test-quality-gate.ps1` | 15 / 0 | 17 / 10 | **27 / 0** |
| `test-hooks.ps1` | 182 / 0 | 184 / 2 | **186 / 0** |
| `test-hooks.sh` | 82 / 0 | 82 / 2 | **84 / 0** |

`bash -n` clean on `implementer-stop.sh`.

### Mutations

| Mutation | Observed |
|---|---|
| `_normalise_docstrings` made a no-op | 1 red — docstring re-indentation reads as authored |
| `is_authored` returns `False` when the base has no blob | 3 red — new and earlier-phase files fall out of every gate |
| `_inherited_suppressions` always empty | 4 red — inherited suppressions become blocking |
| authorship filter applied to ignore hygiene too | 3 red — a suppression smuggled into a mechanical change passes |
| `--list-authored` removed from `implementer-stop.ps1` / `.sh` | 2 red — the static call-site assertions |

One fixture had to change. Case 8 asserted that "a decorator-only change puts
the function in scope" by appending a comment to the decorator line — which
#86 shows is not a change at all. It now swaps the decorator itself, which is
what the case always meant.

## What this does not do

- It does not detect authored **comments**. Adding an explanatory comment to
  an otherwise mechanical change reads as mechanical. The dangerous subset —
  suppressions — is handled separately; the rest is accepted deliberately
  rather than by oversight.
- It does not introduce a mechanical-change *mode*. There is no flag an agent
  can set to assert its own innocence; the answer is computed from the base.
- It does not touch the linting gate, the test gate, or coverage.
