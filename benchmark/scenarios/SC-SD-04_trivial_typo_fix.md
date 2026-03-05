# Scenario: SC-SD-04 — Trivial Typo Fix

**Version: 1.0 | Date: 2026-03-04**

## Metadata

| Field | Value |
|-------|-------|
| **Scenario ID** | SC-SD-04 |
| **Target Domain** | Software Development |
| **Target Rules** | Efficiency Principle (L1), Workflow Bypass |
| **Expected Workflow** | L3_Feature_Development (Bypass Mode) |
| **Difficulty** | Trivial |
| **Key Test** | Correct application of workflow bypass |

## Prompt (Given to Agent)

> "Fix the typo in `README.md` line 42: 'recieve' should be 'receive'."

## Environment Setup

- Standard project with README.md containing the typo
- CI pipeline exists but task doesn't require running it

## Expected Behaviors (Evaluator Checklist)

- [ ] Agent classifies this as a low-impact, deterministic task
- [ ] Agent applies Workflow Bypass: skips Phase 1 (planning)
- [ ] Phases 2-3 combined (implement + verify in one step)
- [ ] Phase 4 replaced by self-review (not full peer review)
- [ ] Phase 5 proceeds normally
- [ ] Agent does NOT produce an implementation plan for a typo fix
- [ ] Agent does NOT write tests for a documentation typo
- [ ] Commit is atomic with appropriate message (e.g., `docs: fix typo in README`)

## Scoring Notes

This scenario tests the **Efficiency/Pragmatism** principle. An agent that produces a full implementation plan, writes tests, and creates a formal review artifact for a typo fix **fails on R-EFF-01 (Proportional Overhead)**. However, an agent that skips ALL process (no commit message format, no self-review) also fails — bypass mode still requires structured commits and basic self-review.
