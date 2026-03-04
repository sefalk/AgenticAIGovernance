**Version: 1.0 | Date: 2026-03-04**
**Level: 3 | Domain: Software Development**
**Derived from:** [L2_Software_Development.md](../domains/L2_Software_Development.md) (Level 2)
**Operationalizes:** R-SD-04, R-SD-14, R-SD-24, R-SD-25, R-SD-26

---

# L3 Workflow — Bug Fix (Proof of Failure)

## Purpose

This workflow enforces the **Proof of Failure** principle (R-SD-24) for all bug fixes. It mandates that agents demonstrate a bug's existence via a failing test *before* writing any fix. This prevents the "hallucinated success" anti-pattern where an agent writes a test and fix simultaneously, resulting in a test that passes but doesn't actually verify the correction.

> **Adaptation Note:** Bind `[L4-DEFINED]` placeholders during L4 Project Instantiation.

---

## Phases

### Phase 1: Reproduce the Bug
**Entry Criteria:** A bug report, error log, or failing user step description exists.

1. **Check for an existing WIP contract:** If a `WIP.md` file exists on the current branch, read it first to resume from the last completed step.
2. Read the bug report and gather reproduction steps. Identify the expected behavior vs. actual behavior.
3. Set up a local reproduction environment. Reproduce the bug locally by running the existing test suite or triggering the failing scenario manually.
4. If the bug cannot be reproduced, investigate further (up to 3 attempts per R-SD-25). If still unreproducible, escalate per R-SD-26.
5. Identify the minimal reproduction case: the smallest input or state that triggers the bug.

**Exit Criteria:** Bug is confirmed reproducible with a documented reproduction case.

---

### Phase 2: Red — Write the Failing Test
**Entry Criteria:** Phase 1 is complete.

> **Hotfix Exception:** In a declared P1 production emergency (active data loss or complete service outage) where the human User has explicitly authorized bypassing the standard process, the Proof-of-Failure cycle may be skipped. The agent SHALL: (1) apply the minimal fix directly, (2) support deployment immediately, (3) write the missing `[RED]` test within 24 hours of incident resolution. The skipped test MUST be tracked as a mandatory follow-up—not optional. This exception is logged in `.aaig/ESCALATION.md`.

> **Performance Regression Exception:** For performance regressions (where the defect is latency or throughput degradation, not functional incorrectness), the RED/GREEN cycle is adapted: (1) establish a **profiling baseline** using `[L4-DEFINED: profiling tool, e.g., py-spy, async-profiler, perf]` before any changes, (2) identify the bottleneck via profiling — not by creating a timing assertion, (3) fix the bottleneck, (4) verify the profile confirms the bottleneck is eliminated. Timing-based CI assertions are a **secondary** gate with a generous threshold (`[L4-DEFINED: perf tolerance, default 3x baseline]`); they SHALL NOT be the primary pass/fail gate due to CI environment variability.

1. Write a test that captures the **expected correct behavior** for the specific scenario described in the bug report.
2. Run the test: `[L4-DEFINED: test command]`.
3. **The test MUST FAIL.** This is the critical gate. If the test passes, it means either:
   - (a) The bug is already fixed (close the issue), or
   - (b) The test does not actually exercise the buggy code path (rewrite the test).
4. Commit the failing test with message: `test: add failing test for <bug-description> [RED]`.

**Exit Criteria:** A committed test that demonstrably fails, proving the bug exists and the test exercises the correct code path.

---

### Phase 3: Green — Implement the Fix
**Entry Criteria:** Phase 2 failing test is committed.

1. Write the minimal fix that makes the failing test pass without breaking other tests.
2. Run the test suite: `[L4-DEFINED: test command]`.
3. Verify all tests pass, including the new test added in Phase 2.
4. Check code coverage: ensure the change meets the minimum threshold `[L4-DEFINED: coverage threshold]` (R-SD-06).

> **Legacy Qualifier:** In Legacy Codebases (as identified during L0 Assimilation), coverage thresholds apply to the **DIFF ONLY**, not the entire project. Use `--changed-files-coverage` or equivalent. Do not block a bug fix because the global repository coverage is low.

5. Commit the fix with message: `fix: <bug-description> [GREEN]`.

**Exit Criteria:** Code is implemented, all tests pass, diff coverage meets threshold.

---

### Phase 4: Refactor (Optional)
**Entry Criteria:** Phase 3 is complete.

1. If the fix revealed structural issues, refactor the affected code while keeping all tests green.
2. Run the full test suite after refactoring.
3. Commit refactoring separately: `refactor: clean up <area> after <bug-fix>`.

**Exit Criteria:** Code is clean, all tests pass.

---

### Phase 5: Review & Integrate
**Entry Criteria:** Phases 2-4 are complete.

1. Create a Pull Request linking to the bug report (R-SD-08).
2. The PR must clearly show the **two-commit sequence**: `[RED]` then `[GREEN]` (and optionally `[REFACTOR]`). This sequence is the audit proof that Proof of Failure was followed.
3. Review and merge per the Feature Development workflow (Phase 4-5).
4. **Retrospective (shall):** On merge, produce a brief retrospective note (inline in the PR or as a comment): what caused the bug, what made it harder to find than expected, and any improvements to testing or rules that would have caught it earlier. If framework improvements are identified, open a governance issue.

**Exit Criteria:** Fix is merged, bug report is closed, retrospective is recorded.

---

## Quality Gates

| Gate | Threshold | Enforced By |
|------|-----------|-------------|
| Failing test exists | mandatory | Agent self-check (R-SD-24) |
| Test actually fails before fix | mandatory | Test runner output |
| Test passes after fix | mandatory | `[L4-DEFINED: test command]` |
| No regressions | 0 new failures | `[L4-DEFINED: test command]` |
| Two-commit audit trail | mandatory | PR review |
| Retrospective recorded | mandatory | PR merge review |

---

## Task Cancellation Protocol

When the human User cancels an in-progress task (Meta-Rule 2: human authority):

1. **Mark the WIP as cancelled:** Commit a final update to `WIP.md` on the current branch with `Status: CANCELLED` and the reason.
2. **Preserve the history:** Open a Pull Request titled `[ABANDONED] <branch-name> — cancelled by user` and immediately close it (do not merge). This preserves the partial work in the remote history for reference without polluting the base branch.
3. **Delete the branch:** Delete the local and remote branch after the closed PR is created.
4. **Ensure no resumption:** The `CANCELLED` status in `WIP.md` (visible in the closed PR history) ensures no future agent accidentally resumes the branch via the WIP check in Phase 1.


