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

### Phase 1: Reproduce & Isolate
**Entry Criteria:** A bug report (issue/ticket) or observed failure exists.

1. Read the bug report. Identify the expected behavior vs. actual behavior.
2. Reproduce the bug locally by running the existing test suite or triggering the failing scenario manually.
3. If the bug cannot be reproduced, investigate further (up to 3 attempts per R-SD-25). If still unreproducible, escalate per R-SD-26.
4. Identify the minimal reproduction case: the smallest input or state that triggers the bug.

**Exit Criteria:** Bug is confirmed reproducible with a documented reproduction case.

---

### Phase 2: Red — Write the Failing Test
**Entry Criteria:** Phase 1 is complete.

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

**Exit Criteria:** Fix is merged, bug report is closed.

---

## Quality Gates

| Gate | Threshold | Enforced By |
|------|-----------|-------------|
| Failing test exists | mandatory | Agent self-check (R-SD-24) |
| Test actually fails before fix | mandatory | Test runner output |
| Test passes after fix | mandatory | `[L4-DEFINED: test command]` |
| No regressions | 0 new failures | `[L4-DEFINED: test command]` |
| Two-commit audit trail | mandatory | PR review |
