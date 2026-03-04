**Version: 1.0 | Date: 2026-03-04**
**Level: 3 | Domain: Software Development**
**Derived from:** [L2_Software_Development.md](../domains/L2_Software_Development.md) (Level 2)
**Operationalizes:** R-SD-01, R-SD-02, R-SD-04, R-SD-05, R-SD-06, R-SD-08, R-SD-09

---

# L3 Workflow — Feature Development

## Purpose

This workflow defines the standard procedure for implementing a new feature in any software project. It transforms declarative L2 rules into an ordered sequence of phases with explicit entry criteria, exit criteria, and quality gates.

> **Adaptation Note:** This is a generic baseline. During L4 Project Instantiation, bind `[L4-DEFINED]` placeholders to project-specific values (branch naming, CI commands, coverage thresholds).

---

## Phases

### Phase 1: Plan
**Entry Criteria:** A ticket, issue, or user request describing the feature exists.

1. **Check for an existing WIP contract:** If a `WIP.md` file exists on the current branch, read it first to determine the last completed phase, last completed step, and the next action. Resume from there instead of starting from Phase 1.
2. Create a feature branch: `[L4-DEFINED: branch naming, e.g., feat/<ticket-id>-<description>]`.
3. Write a brief implementation plan: what will be built, what files will be touched, what tests are needed.
4. Get plan confirmation if the change is high-impact (R-SD-26: Fail-Safe / Ask First).

**Exit Criteria:** An approved (or self-reviewed) Implementation Plan exists.

---

### Phase 2: Implement
**Entry Criteria:** Phase 1 is complete.

1. Write the implementation code following project conventions and active skills.
2. Write automated tests concurrently with or immediately after implementation (R-SD-04).
3. Commit atomically with messages following `[L4-DEFINED: commit format]` (R-SD-09).
4. If an architectural decision arises, create an ADR (R-SD-02).

**Exit Criteria:** Implementation is code-complete with associated tests.

---

### Phase 3: Verify
**Entry Criteria:** Phase 2 is complete.

1. Run the test suite: `[L4-DEFINED: test command]`.
2. Verify all tests pass.
3. Check code coverage: ensure the change meets the minimum threshold `[L4-DEFINED: coverage threshold]` (R-SD-06).

> **Legacy Qualifier:** In Legacy Codebases (as identified during L0 Assimilation), coverage thresholds apply to the **DIFF ONLY**, not the entire project. Use `--changed-files-coverage` or equivalent. Do not block a feature because the global repository coverage is low.

> **CI/CD Config Gate:** If the change includes CI pipeline configuration files (`.github/workflows/`, `Jenkinsfile`, `gitlab-ci.yml`), run YAML lint validation: `[L4-DEFINED: CI lint tool, e.g., actionlint]`. Push to a draft/test branch and observe the CI pipeline run before merging to the primary branch.

**Exit Criteria:** All tests pass, linting passes, diff coverage meets minimum threshold. Apply iteration limits per R-SD-25.

---

## Mid-Task Interruption Protocol

If the agent must end a session before completing all phases, it MUST commit a `WIP.md` file to the current branch before closing:

```markdown
# Work In Progress
**Last Phase Completed:** [Phase N]
**Last Step Completed:** [exact step description]
**Next Step:** [exact next step to execute]
**Open Decisions:** [any unresolved design choices]
**Blockers:** [any blockers preventing progress]
```

A resuming agent MUST read `WIP.md` in Phase 1 Step 1 before taking any action. The `WIP.md` file is deleted when the PR is merged.

### Phase 4: Review
**Entry Criteria:** Phase 3 quality gates pass.

1. Create a Pull Request / review artifact linking to the original work item (R-SD-08).
2. The PR is reviewed per the Review Principle (L1). For multi-agent setups, the reviewer MUST be a different agent.
3. Address review feedback. Iterate until convergence.
4. If review deadlocks, escalate to the human User per R-SD-26.

**Exit Criteria:** Review is approved with a documented artifact.

---

### Phase 5: Integrate
**Entry Criteria:** Phase 4 review is approved.

1. Rebase or merge the feature branch into `[L4-DEFINED: primary branch]`.
2. Verify CI pipeline passes on the target branch.
3. Delete the feature branch.
4. Update the work item status to "Done."
5. **Retrospective (shall):** Produce a brief retrospective note (inline in the PR or as a comment): what worked well, what was harder than expected, and any improvements to framework rules or workflows. If framework improvements are identified, open a governance issue.

**Exit Criteria:** Code is merged, CI is green, work item is closed, retrospective is recorded.

---

## Workflow Bypass

Per the Efficiency Principle (L1), this workflow may be shortened for **low-impact, deterministic tasks** (typo fixes, dependency version bumps, formatting changes). In bypass mode:
- Skip Phase 1 (planning).
- Phases 2-3 are combined (implement + verify in one step).
- Phase 4 is replaced by self-review.
- Phase 5 proceeds normally.

---

## Refactoring Mode

When the task is a **pure refactor** (restructuring existing code with no change in observable behavior), use this workflow variant instead of the standard phases:

1. **Baseline Green:** Run the full test suite BEFORE any changes. If the suite is not green, stop — do not refactor a broken codebase.
2. **Refactor:** Make structural changes. Do NOT add new features or change behavior.
3. **Verify Green:** Run the full test suite AFTER changes. Every test that passed before MUST still pass. Zero new tests are expected (the behavior is unchanged). If coverage drops, it indicates tests were coupled to implementation details — investigate.
4. **Review & Integrate:** Standard Phase 4-5.

> **Note on Grandfathering:** In Legacy Codebases, the Grandfathering Clause (L0 Phase 3.3) — "enforce AAIG on diff only" — applies to AAIG quality requirements, not to test correctness. A refactor in a legacy codebase still requires Baseline Green + Verify Green. The diff-only rule governs AAIG rule enforcement, not the correctness bar.

---

## Task Cancellation Protocol

When the human User cancels an in-progress task (L1 Meta-Rule 2: human authority):

1. **Mark the WIP as cancelled:** Commit a final update to `WIP.md` on the current branch: set `Status: CANCELLED` and record the reason.
2. **Preserve the history:** Open a Pull Request titled `[ABANDONED] <branch-name> — cancelled by user` and immediately close it without merging. This preserves the partial work in remote history for audit and reference.
3. **Delete the branch:** Delete the local and remote branch after the closed PR exists.
4. **Ensure no resumption:** The `CANCELLED` status in the closed PR's `WIP.md` ensures no future agent accidentally resumes the branch via the WIP check in Phase 1 Step 1.

