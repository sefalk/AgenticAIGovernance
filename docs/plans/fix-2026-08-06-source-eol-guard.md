# Fix: guard the source tree against CRLF in shipped shell scripts (#70)

<!-- copilot:generated | documenter | 2026-08-06 -->

- **Created:** 2026-08-06
- **Issue:** [#70](https://github.com/sefalk/AgenticAIGovernance/issues/70)
- **Branch:** `agent/70-source-eol-guard`
- **Complexity tier:** Trivial
- **Status:** COMPLETED

## What the issue asked for, and what was actually true

The issue asked for three things. Two of them were already in place, and the
central claim — that CRLF hooks ship to targets — no longer holds.

| Asked for | State on `dev` |
|---|---|
| Normalise the five CRLF files | Not needed: the git blobs were **always LF** (`git ls-files --eol` shows `i/lf` for every `.sh`). Only this Windows checkout had drifted. |
| `*.sh text eol=lf` in `.gitattributes` | **Already present**, together with `* text=auto eol=lf` and per-extension rules. |
| A line-ending check in the parse gate | **Missing.** This is the only real deliverable. |

The shipping claim was the important one to test rather than accept.
`deploy.ps1` no longer copies bytes for text files: `Get-CanonicalBytes`
strips the BOM, folds `\r\n` and lone `\r` to `\n`, and `Copy-Item` survives
only on the branch where decoding as UTF-8 *fails* — i.e. binary assets. The
MCP path does the same in `deploy_core.resolved_source_bytes`, with eight tests
in `test_eol_parity.py` locking it.

Verified rather than read: a real deploy from this checkout — with five CRLF
sources in it — into a throwaway directory produced **22 deployed `.sh` files,
0 containing a CR**. The EOL/BOM parity work closed the deploy hole as a side
effect; the issue predates it.

## The gap that remained

Nothing tests the source. `bash -n` accepts a stray CR — the script parses, and
the `\r` simply becomes part of the last token on each line. So the existing
parse gate, which exists precisely to catch hooks that disarm themselves
silently, walks straight past the one defect that would make
`#!/usr/bin/env bash\r` fail with `bad interpreter` on Linux: exit non-zero,
print nothing. Per #68, that is indistinguishable from approval.

Two layers already protect the deployed copy. This adds the one that makes the
drift *visible* instead of waiting for someone to notice it — and in a deployed
project the same assertion runs against the deployed `.github/`, where it
asserts that the deploy canonicalization did its job.

## What changed

A single assertion in each harness, appended to the parse gate:

- `test-hooks.ps1` — `no shipped shell script carries a CR`, scanning
  `hooks/scripts/*.sh`, `scripts/*.sh` and the extensionless
  `hooks/git/pre-commit` shim.
- `test-hooks.sh` — the same assertion over the same three paths.

Scope deliberately includes `.github/scripts/*.sh` and the git shim: four of
the five drifted files were outside `hooks/scripts/`, which is all the parse
gate had been looking at.

## Verification

| Check | Result |
|---|---|
| Red, `test-hooks.ps1` | 123 passed / **1 failed** — `CRLF in: test-writer-stop.sh, bootstrap-python-env.sh, cleanup-worktree.sh, run-tests.sh, setup-worktree.sh` |
| Red, `test-hooks.sh` | 35 / **1**, same five files |
| Mutation: CRLF injected into `hooks/git/pre-commit` | both harnesses fail naming `pre-commit` — the extensionless path is genuinely scanned, which the Red phase did not cover |
| Green, `test-hooks.ps1` | 124 / 0 |
| Green, `test-hooks.sh` | 36 / 0 |
| Deploy from a CRLF checkout into a temp target | 22 `.sh` deployed, 0 with a CR |

## Note on the "fix" that isn't a commit

Normalising the five files produced **no diff**: `git diff --numstat` is empty
afterwards, because the blobs were already LF and only the working tree had
drifted. The Red phase was therefore real, but local — a fresh clone would have
been green all along.

That is worth stating plainly rather than dressing up. The repository content
was never broken; the deploy path was fixed months ago by unrelated work; what
this branch adds is the instrument that would have told us any of that without
someone going and looking.
